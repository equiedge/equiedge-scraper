// lib/resultsBuilder.js
// Builds a draft results bundle from resolved selections.

const UNIT_STAKE = 10; // $10 per unit

// Confidence band definitions
const BANDS = [
  { min: 60, max: 64, label: '60-64' },
  { min: 65, max: 69, label: '65-69' },
  { min: 70, max: 74, label: '70-74' },
  { min: 75, max: 79, label: '75-79' },
  { min: 80, max: 84, label: '80-84' },
  { min: 85, max: 100, label: '85+' },
];

function getBand(confidence) {
  return BANDS.find(b => confidence >= b.min && confidence <= b.max) || null;
}

// Build rows from resolved selections
function buildRows(selections) {
  return selections.map(sel => {
    const stake = sel.units * UNIT_STAKE;
    let returnAmt = 0;
    let profit = 0;

    if (sel.result === 'win' && sel.finalFixedOdds != null) {
      returnAmt = parseFloat((sel.finalFixedOdds * stake).toFixed(2));
      profit = parseFloat((returnAmt - stake).toFixed(2));
    } else if (sel.result === 'loss') {
      returnAmt = 0;
      profit = -stake;
    }
    // 'unknown' and 'scratched' get 0 profit (excluded from summary)

    return {
      date: sel.date,
      track: sel.track,
      raceNumber: sel.raceNumber,
      raceName: sel.raceName || '',
      horseName: sel.horseName,
      confidence: sel.confidence,
      units: sel.units,
      fixedOddsAtPick: sel.fixedWinOddsAtPick,
      finalFixedOdds: sel.finalFixedOdds,
      result: sel.result,
      stake,
      return: returnAmt,
      profit,
      needsManualReview: sel.needsManualReview || false,
      reviewReason: sel.reviewReason || null,
      notes: '',
    };
  }).sort((a, b) => {
    if (a.date !== b.date) return a.date.localeCompare(b.date);
    if (a.track !== b.track) return a.track.localeCompare(b.track);
    return a.raceNumber - b.raceNumber;
  });
}

// Compute summary from rows (only counts win/loss, excludes unknown/scratched)
function computeSummary(rows) {
  const countable = rows.filter(r => r.result === 'win' || r.result === 'loss');
  const wins = countable.filter(r => r.result === 'win').length;
  const losses = countable.filter(r => r.result === 'loss').length;
  const totalBets = countable.length;
  const totalUnits = countable.reduce((s, r) => s + r.units, 0);
  const totalStaked = countable.reduce((s, r) => s + r.stake, 0);
  const profit = parseFloat(countable.reduce((s, r) => s + r.profit, 0).toFixed(2));
  const roi = totalStaked > 0 ? parseFloat((profit / totalStaked).toFixed(4)) : 0;

  return { totalBets, wins, losses, totalUnits, totalStaked, profit, roi };
}

// Compute confidence band breakdown
function computeConfidenceBands(rows) {
  const countable = rows.filter(r => r.result === 'win' || r.result === 'loss');

  return BANDS.map(band => {
    const bandRows = countable.filter(r => r.confidence >= band.min && r.confidence <= band.max);
    const bets = bandRows.length;
    const wins = bandRows.filter(r => r.result === 'win').length;
    const units = bandRows.reduce((s, r) => s + r.units, 0);
    const staked = bandRows.reduce((s, r) => s + r.stake, 0);
    const profit = parseFloat(bandRows.reduce((s, r) => s + r.profit, 0).toFixed(2));
    const roi = staked > 0 ? parseFloat((profit / staked).toFixed(4)) : 0;

    return { band: band.label, bets, wins, units, staked, profit, roi };
  }).filter(b => b.bets > 0);
}

// Build a complete draft bundle
function buildDraft(weekLabel, periodStart, periodEnd, selections) {
  const rows = buildRows(selections);
  const summary = computeSummary(rows);
  const confidenceBands = computeConfidenceBands(rows);

  return {
    week: weekLabel,
    status: 'draft',
    periodStart,
    periodEnd,
    generatedAt: new Date().toISOString(),
    summary,
    confidenceBands,
    rows,
  };
}

// Recompute summary and bands from edited rows (used by PATCH endpoint)
function recomputeAggregates(draft) {
  draft.summary = computeSummary(draft.rows);
  draft.confidenceBands = computeConfidenceBands(draft.rows);
  return draft;
}

module.exports = {
  buildDraft,
  recomputeAggregates,
  computeSummary,
  computeConfidenceBands,
  buildRows,
  UNIT_STAKE,
};
