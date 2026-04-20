// betfair/markets.js
// High-level fetchers for Betfair meetings and per-race markets.
//
// Consumers:
//   fetchBetfairMeetings(date, logger) -> Map of formfav-slug -> meetingContext
//   fetchBetfairMarket(meetingContext, raceNumber, runnerNames, logger) -> marketData or null
//
// meetingContext is opaque to the caller but contains the Betfair eventId and
// the already-fetched market catalogue, so per-race calls are cheap.

const client = require('./client');
const matching = require('./matching');

const HORSE_RACING_EVENT_TYPE_ID = '7';

// ───────────────────────────────────────────────────────────────
// In-process caches
// ───────────────────────────────────────────────────────────────
// Meetings cache keyed by ISO date. Value is a map of slug -> meetingContext.
// TTL 10 minutes — fields on a race day can change (late scratchings, market restructures).
const meetingsCache = new Map();
const MEETINGS_TTL_MS = 10 * 60 * 1000;

// Market book (prices) cache keyed by marketId. TTL 60 seconds — we want
// prices that are fresh without hammering the API.
const marketBookCache = new Map();
const BOOK_TTL_MS = 60 * 1000;

function clearCaches() {
  meetingsCache.clear();
  marketBookCache.clear();
}

// ───────────────────────────────────────────────────────────────
// Meetings + market catalogue
// ───────────────────────────────────────────────────────────────
// Pulls Australian horse-racing events for the given date, then for each
// event pulls the WIN market catalogue. Returns a Map keyed by the
// FormFav-style track slug so the rest of the code can look up "randwick".
//
// date: ISO yyyy-mm-dd (in Australia/Sydney timezone, to align with scrapeFormFav)
async function fetchBetfairMeetings(date, logger = console) {
  // cache check
  const cached = meetingsCache.get(date);
  if (cached && (Date.now() - cached.fetchedAt) < MEETINGS_TTL_MS) {
    return cached.byTrack;
  }

  try {
    // day window in UTC — Betfair interprets marketStartTime in UTC
    const from = new Date(`${date}T00:00:00+10:00`).toISOString();
    const to = new Date(`${date}T23:59:59+10:00`).toISOString();

    const events = await client.rpc('listEvents', {
      filter: {
        eventTypeIds: [HORSE_RACING_EVENT_TYPE_ID],
        marketCountries: ['AU'],
        marketStartTime: { from, to },
      },
    }, { logger });

    if (!Array.isArray(events) || events.length === 0) {
      logger.log && logger.log(`Betfair: no AU horse-racing events found for ${date}`);
      meetingsCache.set(date, { fetchedAt: Date.now(), byTrack: new Map() });
      return new Map();
    }

    logger.log && logger.log(`Betfair: ${events.length} AU horse-racing meetings found for ${date}`);

    // For each event, pull its WIN markets. Batch into groups of ~5 to stay polite.
    const byTrack = new Map();
    const eventIds = events.map(e => e.event.id);

    // One listMarketCatalogue call per 5 events — avoids over-large responses
    const BATCH = 5;
    for (let i = 0; i < eventIds.length; i += BATCH) {
      const batchIds = eventIds.slice(i, i + BATCH);
      const markets = await client.rpc('listMarketCatalogue', {
        filter: {
          eventIds: batchIds,
          eventTypeIds: [HORSE_RACING_EVENT_TYPE_ID],
          marketTypeCodes: ['WIN'],
        },
        maxResults: 200,
        marketProjection: ['MARKET_START_TIME', 'RUNNER_DESCRIPTION', 'EVENT'],
      }, { logger });

      if (Array.isArray(markets)) {
        // Group markets by eventId
        for (const market of markets) {
          const eventId = market.event && market.event.id;
          if (!eventId) continue;
          const event = events.find(e => e.event.id === eventId);
          if (!event) continue;

          const venue = event.event.venue || event.event.name;
          const slugKey = normaliseVenueToSlug(venue);

          if (!byTrack.has(slugKey)) {
            byTrack.set(slugKey, {
              eventId,
              eventName: event.event.name,
              venue,
              markets: [],
            });
          }
          byTrack.get(slugKey).markets.push(market);
        }
      }
    }

    logger.log && logger.log(`Betfair: market catalogue loaded for ${byTrack.size} venues`);
    meetingsCache.set(date, { fetchedAt: Date.now(), byTrack });
    return byTrack;
  } catch (err) {
    logger.log && logger.log(`Betfair meetings fetch failed: ${err.message}`);
    return new Map();
  }
}

// Convert "Randwick (AUS)" -> "randwick" style slug for lookup
function normaliseVenueToSlug(venue) {
  return matching
    .normaliseBetfairVenue(venue)
    .toLowerCase()
    .replace(/\s+/g, '-');
}

// Public helper: given a FormFav slug, return the meeting's Betfair context
// including the market catalogue. Used by fetchBetfairMarket.
function getMeetingContext(formFavSlug, byTrackMap, logger = console) {
  const slug = (formFavSlug || '').toLowerCase().trim();
  // try slug-direct hit first
  if (byTrackMap.has(slug)) return byTrackMap.get(slug);
  // fall back to candidate venue names
  const candidates = matching.candidateBetfairVenues(slug).map(c => c.toLowerCase().replace(/\s+/g, '-'));
  for (const c of candidates) {
    if (byTrackMap.has(c)) return byTrackMap.get(c);
  }
  logger.log && logger.log(`Betfair: no meeting match for "${slug}" (tried: ${candidates.join(', ')})`);
  return null;
}

// ───────────────────────────────────────────────────────────────
// Per-race market book (prices)
// ───────────────────────────────────────────────────────────────
// Given a meeting context and a FormFav race number + runner list, returns
// { marketId, marketTime, totalMatched, runners: [{ name, selectionId, backPrice, layPrice, impliedProb, matchedVolume, matchType }] }
// or null if matching fails.
async function fetchBetfairMarket(meetingContext, raceNumber, formFavRunners, logger = console) {
  if (!meetingContext) return null;

  const market = matching.matchRace(raceNumber, meetingContext.markets || []);
  if (!market) {
    logger.log && logger.log(`Betfair: no market for ${meetingContext.venue} R${raceNumber}`);
    return null;
  }

  // Match each FormFav runner -> Betfair selection
  const runnerMatches = [];
  const unmatched = [];
  for (const runner of (formFavRunners || [])) {
    const match = matching.matchHorse(runner.name, market.runners || [], logger);
    if (match) {
      runnerMatches.push({ runner, selectionId: match.selectionId, runnerName: match.runnerName, matchType: match.matchType });
    } else {
      unmatched.push(runner.name);
    }
  }

  if (unmatched.length > 0) {
    logger.log && logger.log(`Betfair: ${meetingContext.venue} R${raceNumber} — ${unmatched.length} unmatched runners: ${unmatched.slice(0, 4).join(', ')}${unmatched.length > 4 ? ', ...' : ''}`);
  }

  // Pull prices with caching
  const book = await fetchMarketBook(market.marketId, logger);
  if (!book) return null;

  // Build output, zipping FormFav runner data with Betfair prices
  const bookRunnersById = {};
  for (const br of (book.runners || [])) {
    bookRunnersById[br.selectionId] = br;
  }

  const runners = runnerMatches.map(({ runner, selectionId, runnerName, matchType }) => {
    const br = bookRunnersById[selectionId] || {};
    const backLadder = (br.ex && br.ex.availableToBack) || [];
    const layLadder = (br.ex && br.ex.availableToLay) || [];
    const backPrice = backLadder[0] ? backLadder[0].price : null;
    const layPrice = layLadder[0] ? layLadder[0].price : null;
    const impliedProb = backPrice ? 1 / backPrice : null;
    return {
      formFavNumber: runner.number,
      formFavName: runner.name,
      betfairSelectionId: selectionId,
      betfairRunnerName: runnerName,
      matchType,
      backPrice,
      layPrice,
      impliedProb: impliedProb != null ? parseFloat(impliedProb.toFixed(4)) : null,
      matchedVolume: br.totalMatched || 0,
      status: br.status || 'UNKNOWN',
    };
  });

  const favorite = runners.filter(r => r.backPrice != null).sort((a, b) => a.backPrice - b.backPrice)[0] || null;

  return {
    marketId: market.marketId,
    marketName: market.marketName,
    marketTime: market.marketStartTime,
    venue: meetingContext.venue,
    raceNumber,
    status: book.status,
    totalMatched: book.totalMatched || 0,
    runners,
    favorite: favorite ? { name: favorite.formFavName, number: favorite.formFavNumber, price: favorite.backPrice } : null,
    unmatchedRunners: unmatched,
    fetchedAt: new Date().toISOString(),
  };
}

async function fetchMarketBook(marketId, logger = console) {
  const cached = marketBookCache.get(marketId);
  if (cached && (Date.now() - cached.fetchedAt) < BOOK_TTL_MS) {
    return cached.book;
  }
  try {
    const res = await client.rpc('listMarketBook', {
      marketIds: [marketId],
      priceProjection: {
        priceData: ['EX_BEST_OFFERS'],
        virtualise: true,
      },
    }, { logger });
    const book = Array.isArray(res) && res[0] ? res[0] : null;
    if (book) marketBookCache.set(marketId, { fetchedAt: Date.now(), book });
    return book;
  } catch (err) {
    logger.log && logger.log(`Betfair listMarketBook failed for ${marketId}: ${err.message}`);
    return null;
  }
}

module.exports = {
  fetchBetfairMeetings,
  fetchBetfairMarket,
  getMeetingContext,
  clearCaches,
};
