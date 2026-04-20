// betfair/matching.js
// Maps FormFav race/runner identifiers to Betfair equivalents.
//
// The two hard parts are:
//   1. Track name reconciliation — FormFav uses slug ("randwick"), Betfair uses venue names ("Randwick (AUS)").
//   2. Horse name reconciliation — Betfair prefixes numbers and sometimes appends country codes.
//
// Both use a normalise-then-compare-then-fuzzy-fallback chain, with an
// overrides.json for the stubborn cases.

const overrides = require('./overrides.json');

// ───────────────────────────────────────────────────────────────
// Track matching
// ───────────────────────────────────────────────────────────────

// Most FormFav slugs map to Betfair's venue name by simple title-casing
// and hyphen-to-space conversion. Exceptions go in the override file.
const STATIC_TRACK_OVERRIDES = {
  'eagle-farm': 'Eagle Farm',
  'gold-coast': 'Gold Coast',
  'sunshine-coast': 'Sunshine Coast',
  'gold-coast-poly': 'Gold Coast Poly',
  'morphettville-parks': 'Morphettville Parks',
  'canterbury-park': 'Canterbury',
  'royal-randwick': 'Randwick',
  'bendigo-synthetic': 'Bendigo',
  'pakenham-synthetic': 'Pakenham Synthetic',
};

function slugToTitleCase(slug) {
  return slug
    .split('-')
    .map(s => s.charAt(0).toUpperCase() + s.slice(1))
    .join(' ');
}

function normaliseBetfairVenue(name) {
  // "Randwick (AUS)" -> "Randwick"; "Eagle Farm" -> "Eagle Farm"
  return (name || '').replace(/\s*\(AUS\)\s*/gi, '').replace(/\s+/g, ' ').trim();
}

// Given a FormFav track slug, return the expected Betfair venue name(s) to try.
function candidateBetfairVenues(formFavSlug) {
  const slug = (formFavSlug || '').toLowerCase().trim();
  const candidates = [];
  // 1. overrides file wins
  if (overrides.tracks && overrides.tracks[slug]) {
    candidates.push(overrides.tracks[slug]);
  }
  // 2. static overrides
  if (STATIC_TRACK_OVERRIDES[slug]) {
    candidates.push(STATIC_TRACK_OVERRIDES[slug]);
  }
  // 3. title-cased slug
  candidates.push(slugToTitleCase(slug));
  // dedupe, keep order
  return [...new Set(candidates)];
}

// Find the Betfair event (meeting) that matches this FormFav track slug.
// events is an array of { event: { id, name, venue, openDate, countryCode } }
function matchMeeting(formFavSlug, events, logger = console) {
  const candidates = candidateBetfairVenues(formFavSlug);
  const auEvents = events.filter(e => (e.event.countryCode || '').toUpperCase() === 'AU');

  for (const candidate of candidates) {
    const target = candidate.toLowerCase();
    const hit = auEvents.find(e => normaliseBetfairVenue(e.event.venue || e.event.name).toLowerCase() === target);
    if (hit) return hit;
  }

  // Last resort: loose contains match
  const firstCandidate = (candidates[0] || '').toLowerCase();
  const loose = auEvents.find(e => normaliseBetfairVenue(e.event.venue || e.event.name).toLowerCase().includes(firstCandidate));
  if (loose) {
    logger.log && logger.log(`Meeting match: loose hit for ${formFavSlug} -> ${loose.event.name} (${loose.event.venue})`);
    return loose;
  }

  return null;
}

// ───────────────────────────────────────────────────────────────
// Race (market) matching within a meeting
// ───────────────────────────────────────────────────────────────

// Betfair market names are usually like "R6 1400m Hcp" or "R6 1400m HCAP".
// Pull the race number from the leading "R<digit>".
function extractRaceNumber(marketName) {
  const m = (marketName || '').match(/^R\s*(\d+)/i);
  return m ? parseInt(m[1], 10) : null;
}

// markets is an array of Betfair MarketCatalogue entries for one meeting.
function matchRace(raceNumber, markets, { marketTypeCode = 'WIN' } = {}) {
  const winMarkets = markets.filter(m => (m.description && m.description.marketType === marketTypeCode) || marketTypeCode === 'WIN');
  return winMarkets.find(m => extractRaceNumber(m.marketName) === raceNumber) || null;
}

// ───────────────────────────────────────────────────────────────
// Horse (runner / selection) matching
// ───────────────────────────────────────────────────────────────

function normaliseHorseName(name) {
  if (!name) return '';
  return name
    .toLowerCase()
    .replace(/^\d+\.\s*/, '')       // strip leading "12. "
    .replace(/\([a-z]{2,3}\)\s*$/i, '') // strip trailing "(NZ)" / "(AUS)"
    .replace(/['’`]/g, '')          // apostrophes
    .replace(/[^a-z0-9\s]/g, '')    // punctuation
    .replace(/\s+/g, ' ')
    .trim();
}

// Levenshtein distance — small, O(m*n), fine for horse names.
function levenshtein(a, b) {
  if (a === b) return 0;
  if (!a.length) return b.length;
  if (!b.length) return a.length;
  const v0 = new Array(b.length + 1);
  const v1 = new Array(b.length + 1);
  for (let i = 0; i <= b.length; i++) v0[i] = i;
  for (let i = 0; i < a.length; i++) {
    v1[0] = i + 1;
    for (let j = 0; j < b.length; j++) {
      const cost = a[i] === b[j] ? 0 : 1;
      v1[j + 1] = Math.min(v1[j] + 1, v0[j + 1] + 1, v0[j] + cost);
    }
    for (let j = 0; j <= b.length; j++) v0[j] = v1[j];
  }
  return v1[b.length];
}

// Match a FormFav runner name against a list of Betfair selections.
// selections: [{ selectionId, runnerName, handicap, sortPriority }]
// Returns { selectionId, runnerName, matchType: 'override'|'exact'|'fuzzy', distance } or null.
function matchHorse(formFavName, selections, logger = console) {
  const target = normaliseHorseName(formFavName);
  if (!target) return null;

  // 1. overrides
  if (overrides.horses && overrides.horses[target]) {
    const overrideTarget = overrides.horses[target];
    const hit = selections.find(s => normaliseHorseName(s.runnerName) === overrideTarget);
    if (hit) return { selectionId: hit.selectionId, runnerName: hit.runnerName, matchType: 'override', distance: 0 };
  }

  // 2. exact after normalisation
  const exact = selections.find(s => normaliseHorseName(s.runnerName) === target);
  if (exact) return { selectionId: exact.selectionId, runnerName: exact.runnerName, matchType: 'exact', distance: 0 };

  // 3. fuzzy (distance <= 2 AND length-ratio within 20%)
  let best = null;
  let bestDist = Infinity;
  for (const s of selections) {
    const candidate = normaliseHorseName(s.runnerName);
    if (!candidate) continue;
    const lenRatio = Math.min(candidate.length, target.length) / Math.max(candidate.length, target.length);
    if (lenRatio < 0.8) continue;
    const d = levenshtein(candidate, target);
    if (d < bestDist) {
      bestDist = d;
      best = s;
    }
  }
  if (best && bestDist <= 2) {
    logger.log && logger.log(`Horse match: fuzzy "${formFavName}" -> "${best.runnerName}" (distance ${bestDist})`);
    return { selectionId: best.selectionId, runnerName: best.runnerName, matchType: 'fuzzy', distance: bestDist };
  }

  return null;
}

module.exports = {
  candidateBetfairVenues,
  normaliseBetfairVenue,
  matchMeeting,
  extractRaceNumber,
  matchRace,
  normaliseHorseName,
  matchHorse,
  levenshtein,   // exported for unit-testing
};
