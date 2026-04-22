// lib/results/betfairResults.js
// Resolves race results + final odds via Betfair SP for weekly results automation.
// Runs on Lambda (900s budget) — safe for fan-out across many markets.

const betfairClient = require('../../betfair/client');
const betfairAuth = require('../../betfair/auth');
const betfairMarkets = require('../../betfair/markets');
const matching = require('../../betfair/matching');

const CONCURRENCY = 3;

// Simple p-limit implementation (avoids adding dep)
function pLimit(concurrency) {
  let active = 0;
  const queue = [];
  function next() {
    if (active >= concurrency || queue.length === 0) return;
    active++;
    const { fn, resolve, reject } = queue.shift();
    fn().then(resolve, reject).finally(() => { active--; next(); });
  }
  return function limit(fn) {
    return new Promise((resolve, reject) => {
      queue.push({ fn, resolve, reject });
      next();
    });
  };
}

// Retry with exponential backoff, auto re-auth on session errors
async function withRetry(fn, logger, retries = 3) {
  for (let attempt = 1; attempt <= retries; attempt++) {
    try {
      return await fn();
    } catch (err) {
      const msg = err.message || '';
      const isSessionError = msg.includes('INVALID_SESSION_INFORMATION') ||
                             msg.includes('NO_SESSION') ||
                             (err.response && err.response.status === 401);
      if (isSessionError && attempt < retries) {
        logger.log && logger.log(`Betfair session error — re-authing (attempt ${attempt}/${retries})`);
        await betfairAuth.invalidateSession(logger);
        continue;
      }
      if (attempt < retries) {
        const delay = Math.pow(2, attempt) * 1000;
        logger.log && logger.log(`Betfair call failed (attempt ${attempt}/${retries}), retrying in ${delay}ms: ${msg}`);
        await new Promise(r => setTimeout(r, delay));
        continue;
      }
      throw err;
    }
  }
}

// Fetch market book with SP data for a settled market
async function fetchMarketBookWithSP(marketId, logger) {
  return withRetry(async () => {
    const res = await betfairClient.rpc('listMarketBook', {
      marketIds: [marketId],
      priceProjection: {
        priceData: ['SP_AVAILABLE', 'SP_TRADED', 'EX_TRADED'],
      },
    }, { logger });
    return Array.isArray(res) && res[0] ? res[0] : null;
  }, logger);
}

// Get final odds from Betfair runner data.
// Priority: sp.actualSP -> sp.nearPrice -> lastPriceTraded
function extractFinalOdds(bookRunner) {
  if (!bookRunner) return null;
  const sp = bookRunner.sp || {};
  if (sp.actualSP && sp.actualSP > 0) return parseFloat(sp.actualSP.toFixed(2));
  if (sp.nearPrice && sp.nearPrice > 0) return parseFloat(sp.nearPrice.toFixed(2));
  if (bookRunner.lastPriceTraded && bookRunner.lastPriceTraded > 0) {
    return parseFloat(bookRunner.lastPriceTraded.toFixed(2));
  }
  return null;
}

// Map Betfair runner status to our result enum
function mapResult(status) {
  if (status === 'WINNER') return 'win';
  if (status === 'REMOVED') return 'scratched';
  return 'loss'; // LOSER or anything else
}

// Resolve results for a list of selections.
// Selections grouped by {track, date, raceNumber} to minimize API calls.
// Returns selections enriched with: result, finalFixedOdds, needsManualReview
async function resolveSelections(selections, logger = console) {
  const limit = pLimit(CONCURRENCY);

  // Group selections by unique race (track+date+raceNumber)
  const raceGroups = new Map();
  for (const sel of selections) {
    const key = `${sel.track}|${sel.date}|${sel.raceNumber}`;
    if (!raceGroups.has(key)) {
      raceGroups.set(key, { track: sel.track, date: sel.date, raceNumber: sel.raceNumber, selections: [] });
    }
    raceGroups.get(key).selections.push(sel);
  }

  // Cache meetings by date to avoid redundant fetches
  const meetingsCache = new Map();

  async function getMeetings(date) {
    if (meetingsCache.has(date)) return meetingsCache.get(date);
    const meetings = await withRetry(() => betfairMarkets.fetchBetfairMeetings(date, logger), logger);
    meetingsCache.set(date, meetings);
    return meetings;
  }

  // Market book cache (keyed by marketId) to avoid re-fetching for same race
  const bookCache = new Map();

  const tasks = [...raceGroups.values()].map(group => {
    return limit(async () => {
      try {
        const meetings = await getMeetings(group.date);
        const trackSlug = group.track.toLowerCase().replace(/\s+/g, '-');
        const meetingCtx = betfairMarkets.getMeetingContext(trackSlug, meetings, logger);

        if (!meetingCtx) {
          logger.log && logger.log(`No Betfair meeting for ${group.track} on ${group.date}`);
          for (const sel of group.selections) {
            sel.result = 'unknown';
            sel.finalFixedOdds = null;
            sel.needsManualReview = true;
            sel.reviewReason = 'No Betfair meeting found';
          }
          return;
        }

        // Find the WIN market for this race number
        const market = matching.matchRace(group.raceNumber, meetingCtx.markets || []);
        if (!market) {
          logger.log && logger.log(`No Betfair market for ${group.track} R${group.raceNumber} on ${group.date}`);
          for (const sel of group.selections) {
            sel.result = 'unknown';
            sel.finalFixedOdds = null;
            sel.needsManualReview = true;
            sel.reviewReason = 'No Betfair market found';
          }
          return;
        }

        // Fetch market book (with SP data)
        let book = bookCache.get(market.marketId);
        if (!book) {
          book = await fetchMarketBookWithSP(market.marketId, logger);
          if (book) bookCache.set(market.marketId, book);
        }

        if (!book || !book.runners) {
          for (const sel of group.selections) {
            sel.result = 'unknown';
            sel.finalFixedOdds = null;
            sel.needsManualReview = true;
            sel.reviewReason = 'Market book unavailable';
          }
          return;
        }

        // Build lookup of Betfair runners by normalised name
        const bfRunners = (market.runners || []).map(r => ({
          selectionId: r.selectionId,
          runnerName: r.runnerName,
          normalised: matching.normaliseHorseName(r.runnerName),
        }));

        for (const sel of group.selections) {
          try {
            // Use existing matching module (exact + fuzzy with Levenshtein)
            const match = matching.matchHorse(sel.horseName, market.runners || [], logger);

            if (!match) {
              sel.result = 'unknown';
              sel.finalFixedOdds = null;
              sel.needsManualReview = true;
              sel.reviewReason = `No runner match for "${sel.horseName}"`;
              continue;
            }

            // Find this runner in the book
            const bookRunner = book.runners.find(r => r.selectionId === match.selectionId);
            if (!bookRunner) {
              sel.result = 'unknown';
              sel.finalFixedOdds = null;
              sel.needsManualReview = true;
              sel.reviewReason = 'Runner not in market book';
              continue;
            }

            sel.result = mapResult(bookRunner.status);
            sel.finalFixedOdds = extractFinalOdds(bookRunner);
            sel.needsManualReview = false;
            sel.reviewReason = null;

            // Flag scratched for manual review (refund handling)
            if (sel.result === 'scratched') {
              sel.needsManualReview = true;
              sel.reviewReason = 'Scratched — confirm refund';
            }

            // Flag if no odds available
            if (sel.finalFixedOdds === null && sel.result !== 'scratched') {
              sel.needsManualReview = true;
              sel.reviewReason = 'No SP/odds available';
            }

          } catch (err) {
            logger.log && logger.log(`Error resolving ${sel.horseName} in ${sel.track} R${sel.raceNumber}: ${err.message}`);
            sel.result = 'unknown';
            sel.finalFixedOdds = null;
            sel.needsManualReview = true;
            sel.reviewReason = `Error: ${err.message}`;
          }
        }

      } catch (err) {
        logger.log && logger.log(`Error resolving race group ${group.track} R${group.raceNumber}: ${err.message}`);
        for (const sel of group.selections) {
          sel.result = 'unknown';
          sel.finalFixedOdds = null;
          sel.needsManualReview = true;
          sel.reviewReason = `Race-level error: ${err.message}`;
        }
      }
    });
  });

  await Promise.all(tasks);

  const resolved = selections.filter(s => s.result && s.result !== 'unknown').length;
  const needReview = selections.filter(s => s.needsManualReview).length;
  logger.log && logger.log(`Betfair resolution complete: ${resolved}/${selections.length} resolved, ${needReview} need review`);

  return selections;
}

module.exports = {
  resolveSelections,
  extractFinalOdds,
  mapResult,
};
