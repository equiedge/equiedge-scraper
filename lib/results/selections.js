// lib/results/selections.js
// Loads last week's metro AI selections from Upstash Redis cache.

const { Redis } = require('@upstash/redis');

const METRO_TRACKS = [
  'Randwick', 'Randwick Kensington', 'Rosehill',
  'Darwin', 'Doomben', 'Eagle Farm',
  'Caulfield', 'Caulfield Heath', 'Flemington', 'Sandown',
  'Morphettville', 'Morphettville Parks',
  'Ascot', 'Belmont',
];

// Track name -> cache key slug (matches server.js cacheKey format)
function trackToSlug(track) {
  return track.toLowerCase().replace(/\s+/g, '-');
}

// Returns { startMon, endSun, weekLabel } for the Mon-Sun window before `now`.
// weekLabel is derived from the Monday date to avoid ISO week boundary issues.
function previousWeekRange(now = new Date()) {
  // Get today's date in AEST/AEDT as YYYY-MM-DD
  const aestDate = new Intl.DateTimeFormat('en-CA', { timeZone: 'Australia/Sydney' }).format(now);
  // Parse into a local date (year-month-day only, no timezone shift)
  const [y, m, d] = aestDate.split('-').map(Number);
  const today = new Date(y, m - 1, d);
  const dayOfWeek = today.getDay(); // 0=Sun, 1=Mon, ...
  // Days since this week's Monday
  const daysToThisMon = dayOfWeek === 0 ? 6 : dayOfWeek - 1;
  // Previous week's Monday = this Monday - 7
  const prevMon = new Date(today);
  prevMon.setDate(today.getDate() - daysToThisMon - 7);
  const prevSun = new Date(prevMon);
  prevSun.setDate(prevMon.getDate() + 6);

  const startMon = formatDate(prevMon);
  const endSun = formatDate(prevSun);
  const weekLabel = isoWeekLabel(prevMon);

  return { startMon, endSun, weekLabel };
}

function formatDate(d) {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

// Derive "YYYY-Www" from a date (based on ISO 8601 week calculation)
function isoWeekLabel(date) {
  const d = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()));
  d.setUTCDate(d.getUTCDate() + 4 - (d.getUTCDay() || 7));
  const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
  const weekNo = Math.ceil(((d - yearStart) / 86400000 + 1) / 7);
  return `${d.getUTCFullYear()}-W${String(weekNo).padStart(2, '0')}`;
}

// Generate all 7 dates (YYYY-MM-DD) between startMon and endSun inclusive
function dateRange(startMon, endSun) {
  const dates = [];
  const cur = new Date(startMon + 'T00:00:00');
  const end = new Date(endSun + 'T00:00:00');
  while (cur <= end) {
    dates.push(formatDate(cur));
    cur.setDate(cur.getDate() + 1);
  }
  return dates;
}

// Load all metro selections for a given week from Redis.
// Returns flat array of selection objects.
async function loadWeekMetroSelections({ startMon, endSun }, logger = console) {
  const redis = new Redis({
    url: process.env.UPSTASH_REDIS_REST_URL,
    token: process.env.UPSTASH_REDIS_REST_TOKEN,
  });

  const dates = dateRange(startMon, endSun);
  // Build all 98 candidate keys
  const keys = [];
  for (const date of dates) {
    for (const track of METRO_TRACKS) {
      keys.push({ key: `cache:${trackToSlug(track)}_${date}`, track, date });
    }
  }

  const keyNames = keys.map(k => k.key);
  logger.log && logger.log(`Fetching ${keyNames.length} cache keys via MGET...`);

  const values = await redis.mget(...keyNames);

  const selections = [];
  for (let i = 0; i < keys.length; i++) {
    const raw = values[i];
    if (!raw) continue;

    const races = typeof raw === 'string' ? JSON.parse(raw) : raw;
    if (!Array.isArray(races)) continue;

    for (const race of races) {
      if (!race.suggestions || !Array.isArray(race.suggestions)) continue;
      for (const sel of race.suggestions) {
        if (!sel.horseName || sel.confidence == null) continue;
        selections.push({
          date: keys[i].date,
          track: race.track || keys[i].track,
          raceNumber: race.raceNumber,
          raceName: race.raceName || '',
          horseName: sel.horseName,
          confidence: sel.confidence,
          units: sel.units || 1,
          fixedWinOddsAtPick: sel.marketBackPrice || null,
          aiReason: sel.reason || '',
        });
      }
    }
  }

  logger.log && logger.log(`Loaded ${selections.length} metro selections from ${startMon} to ${endSun}`);
  return selections;
}

module.exports = {
  METRO_TRACKS,
  trackToSlug,
  previousWeekRange,
  dateRange,
  isoWeekLabel,
  loadWeekMetroSelections,
};
