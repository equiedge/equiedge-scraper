// server.js - EquiEdge Scraper (FormFav Pro + Grok AI) - Grok 4.1 Fast + Live Logs
// Updated: FormFav Pro tier — speed maps, class profiles, badges, predictions, track bias, jockey/trainer stats
const express = require('express');
const axios = require('axios');
const cors = require('cors');
const app = express();
app.use(cors());
app.use(express.json());
const FORMAV_API_KEY = process.env.FORMAV_API_KEY;
const XAI_API_KEY = process.env.XAI_API_KEY;
const EQUIEDGE_API_KEY = process.env.EQUIEDGE_API_KEY;
let latestRaces = [];
let serverLogs = [];

// API key authentication middleware
function requireAuth(req, res, next) {
  const key = req.headers['x-api-key'] || req.query.apiKey;
  if (!EQUIEDGE_API_KEY) {
    // If no key configured, log warning but allow (dev mode)
    serverLog('WARNING: No EQUIEDGE_API_KEY set — endpoints are unprotected');
    return next();
  }
  if (key !== EQUIEDGE_API_KEY) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  next();
}
function serverLog(msg) {
  const ts = new Date().toISOString().replace('T', ' ').substring(0, 23);
  const line = `${ts} [info] ${msg}`;
  serverLogs.push(line);
  console.log(line);
  if (serverLogs.length > 500) serverLogs.splice(0, serverLogs.length - 500);
}

// In-memory caches for the current scrape session
let trackBiasCache = {};    // { trackSlug: biasData }
let jockeyStatsCache = {};  // { jockeyName: statsData }
let trainerStatsCache = {}; // { trainerName: statsData }

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// REVISED Structured Grok AI Prompt — handicapping methodology v3
// Tightened selectivity, stricter thresholds, Devil's Advocate step
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
const SYSTEM_PROMPT = `You are an expert Australian horse racing handicapper with extreme selectivity. You are a SNIPER, not a machine gunner. Your edge comes from PASSING on races, not from finding a pick in every race.

Your goal: identify AT MOST ONE horse per race that has a genuine, data-backed edge that the market is likely underpricing. Most races do NOT have a clear edge — and that is fine. NO SELECTION is your most common output.

SELECTION RATE DISCIPLINE:
You are analysing a full card of races. Your target is to select in NO MORE than 3-4 races per full card (typically 7-10 races per venue). That means you should be passing on 50-70% of races. If you find yourself wanting to select in most races, you are being too lenient — raise your threshold. A punter who bets every race loses. A punter who waits for genuine edges wins long term.

VENUE QUALITY ADJUSTMENT:
- METRO SATURDAY (Randwick, Flemington, Eagle Farm, Morphettville, Ascot): Standard thresholds apply. Deeper form, more reliable data, stronger fields.
- METRO MIDWEEK (Canterbury, Sandown, Doomben, etc.): Slightly more caution — weaker fields, less reliable form.
- PROVINCIAL (Newcastle, Geelong, Ipswich, Gold Coast, Townsville, etc.): RAISE thresholds. Smaller sample sizes, weaker fields, more randomness. Default to NO SELECTION unless evidence is compelling.
- COUNTRY: Highest caution. Form is least reliable, fields are most unpredictable. Only select with overwhelming evidence.

FORM STRING KEY (most recent run is RIGHTMOST):
- 1-9: finishing position (1=won, 2=second, etc.)
- 0: finished 10th or worse
- x: spell (90+ days between runs, indicating a break/freshening)
- f: failed to finish (pulled up)
- d: disqualified
- -: scratched/did not start

Example: "13x21" = last 5 starts: 1st (oldest), 3rd, spell (90+ day break), 2nd, 1st (most recent). Read right to left for recent form.

FACTOR CLASSIFICATION — PRIMARY vs SECONDARY:
Before selecting, you MUST classify the evidence supporting your pick.

PRIMARY FACTORS (hard statistical edges — at least ONE required):
- Form: last 3 starts include a WIN or TWO places at this class level or higher
- Conditions: Track+Dist win% above 20% with 3+ starts (proven at this exact course and distance)
- ML Model: ranked #1 or #2 with race confidence "high"
- Class Edge: assessment="big_drop" or "slight_drop" WITH withinOptimalRange=true AND trend is NOT "dropping"

SECONDARY FACTORS (supporting evidence — at least TWO required in addition to a primary):
- Positive form badges (2+ positive badges with no negative badges)
- Pace scenario suits running style (e.g., back runner in FAST/VERY_FAST pace)
- Strong barrier position at a venue with "strong" bias
- Jockey/trainer combo with >20% win rate OR trainer recent 90d win rate >20%
- Apprentice claim providing 2+kg weight advantage
- First-up/second-up stats showing >30% win rate at that stage of preparation
- Condition stats significantly above field average (>15% higher win rate on today's going)
- Weight drop badge present AND carrying below field average weight

SELECTION THRESHOLD: ONE primary factor + TWO secondary factors minimum. No exceptions.

ANALYSIS STEPS (work through each sequentially before making a selection):

STEP 1 — FIELD ASSESSMENT:
How many runners? Small fields (<8) are more predictable but offer less value. Large fields (14+) increase the chance of finding an overlay.

Look at the field averages provided to gauge overall quality. A race full of exposed, moderate performers is easier to assess than one with multiple lightly-raced improvers.

Identify the race type:
- Handicap: weight reflects the handicapper's opinion of relative ability
- Weight-for-age (WFA): weight tells you nothing about class — all horses essentially carry the same relative weight
- Set weights: a middle ground — classes of horses carry set amounts
- Maiden/Class restricted: form figures can be misleading as the class ceiling is lower

STEP 2 — PACE ANALYSIS (Speed Map Data):
Assess the paceScenario for this race:
- SLOW: No genuine speed — leaders can dictate. Favour L (Leader) runners, especially from inside barriers.
- MODERATE: One likely leader. Favour P (Presser) runners who can sit behind without being caught wide.
- FAST: Multiple speed runners competing. Favour M (Midfield) and B (Back) runners who can pick up the pieces.
- VERY_FAST: Hot tempo expected. Strongly favour closers (B). Leaders are likely to tire.

If no paceScenario is provided, assess from the speed maps: count runners with ESI > 6.0 and runningStyle L or P.
- 0-1 speed runners = likely SLOW
- 2 speed runners = likely MODERATE
- 3+ speed runners = likely FAST to VERY_FAST

Cross-reference each contender's earlySpeedIndex and settlingPosition against the pace scenario.
A high-ESI runner drawn wide in a FAST-pace race burns energy twice — getting across AND competing for the lead.
A back runner in a SLOW-pace race may never get close enough to challenge.

STEP 3 — FORM ANALYSIS:
For each serious contender, read form right-to-left (rightmost = most recent). Assess:

POSITIVE INDICATORS:
- Improving form (finishing positions getting better towards the right)
- Consistency (mostly top-3 finishes at this class level or higher)
- Recent wins at similar class/distance
- Closing strongly in recent runs (if sectional data is available, late speed is a strong predictor)
- Winning or placing after a spell (proven fresh performer)
- Form franked by subsequent winners (horses that beat or ran close to horses that have since won)

NEGATIVE INDICATORS:
- Deteriorating form (positions getting worse towards the right)
- Long losing streak (10+ starts without winning)
- Failures to finish (f) — especially multiple in recent starts
- Class drops disguising declining form (check how RECENT the good form is)
- Overall win% below the field average — you cannot claim an "edge" if the horse is statistically the weaker runner

GEAR CHANGES (if data available):
- Blinkers first time: volatility signal, not automatically positive
- Tongue tie added: flags an underlying concern
- Gear OFF: sometimes a positive sign of maturity

FORM BADGES (Pre-computed insights):
The decorators/badges are pre-computed contextual assessments. Use them as:
- CONFIRMATION: Positive badges that align with your analysis STRENGTHEN confidence
- WARNING: Negative badges that conflict with your analysis are RED FLAGS that must be addressed
- CRITICAL: Any horse with 2+ NEGATIVE badges should NOT be selected unless the negatives are clearly explained away
- Note CONFLICTS between your analysis and badge sentiment in your reasoning

STEP 4 — CONDITIONS MATCH:
This step is critical and should be re-weighted if Step 8 identifies a track condition change or bias.

TRACK CONDITION:
- Compare Condition win% vs overall Win%. A horse with high overall Win% but low Condition win% on today's going is a negative signal.
- If today is WET and a horse has low Condition win% = likely dry-tracker, negative
- If today is WET and a horse has proven wet form = significant positive, especially if rivals are unproven on wet ground
- IMPORTANT: Track conditions can change throughout a meeting — Step 8 may reveal an upgrade or downgrade. If so, the Condition stats in the data may be for the WRONG surface. Treat conditions assessment as UNCERTAIN and lower confidence by 5 points.

DISTANCE:
- Dist win% shows proven ability at this trip. Track+Dist win% is even more predictive — proven at this exact course and distance combination.
- First time at a distance is a RISK FACTOR but not an automatic disqualifier:
  > Consider breeding (stamina sire stepping up in distance is less risky)
  > Consider racing pattern (a horse that closes strongly at 1400m may relish 1600m)
- Significant distance changes (e.g., 1200m to 2000m) without any form at intermediate trips = genuine concern

TRACK:
- Track win% = proven at this specific course
- Some horses are track specialists — high Track win% at a course is a strong positive
- First time at a track is not a red flag by itself, but combined with other unknowns it adds uncertainty

BARRIER & TRACK BIAS (from historical data):
- biasStrength tells you how significant the barrier bias is: strong > moderate > weak > none
- Compare each runner's barrier against strongestBarrier and weakestBarrier
- A runner drawn in the strongest barrier at a venue with "strong" bias has a genuine data-backed edge
- Use actual advantage values from the bias data, not heuristics
- If Step 8 confirms the historical bias, treat it as a STRONG signal
- If Step 8 contradicts the historical bias, note the conflict

FIRST-UP / SECOND-UP STATS:
- Use the firstUp and secondUp stats data when assessing horses resuming or at their second run back
- A horse with 50%+ first-up win rate is a proven fresh performer — override the first-up red flag
- Second-up stats can reveal "second-up improvers" who need a run under their belt

STEP 5 — CLASS AND WEIGHT:
CLASS ASSESSMENT (use classProfile + raceClassFit data):
- assessment="big_drop": Strong class edge — but check trend: if trend="dropping", the horse may be in decline
- assessment="comfort_zone" + trend="stable": Reliable at this level — no class edge or disadvantage
- assessment="slight_rise" + trend="rising": Progressive type — upward trend supports the step up
- assessment="big_rise": Significant class jump — needs exceptional form indicators to overcome
- withinOptimalRange=true: Race is within the class range where this horse performs best
- classDifference: Positive = stepping up, negative = dropping. ±5 is minor, ±15+ is major.

WEIGHT ASSESSMENT:
Weight impact varies by distance:
- Sprints (<1200m): weight is less impactful
- Middle distance (1400-2000m): moderate impact — 2-3kg is meaningful
- Staying races (2000m+): weight is highly impactful — every kilogram matters

IN HANDICAP RACES:
- Horses >2kg above field average weight face a disadvantage, especially at longer distances
- When a runner has an apprentice claim, use EFFECTIVE weight (weight minus claim) for comparisons
- A 3kg claim on a 58kg allocation = 55kg effective — this is a genuine edge

IN WFA / SET WEIGHT RACES:
- Weight differentials reflect age/sex, NOT class — do not penalise for "more weight"
- Focus on class indicators instead

STEP 6 — CONNECTIONS:
JOCKEY (with data when available):
- Check jockey's track-specific win rate and condition-specific stats
- Elite jockey on moderate form horse: potential signal — top riders choose mounts carefully
- Apprentice claim: genuine edge if the apprentice is competent
- Jockey changes: top jockey getting on = stable confidence signal; getting OFF = negative signal

TRAINER (with data when available):
- Recent 90d win rate >20% = trainer in strong form
- Trainer's track-specific stats: some trainers dominate certain venues
- Trainer/jockey combinations with high strike rates: strong positive

STEP 7 — REAL-TIME INTELLIGENCE (X/Twitter Search):
Search X for today's specific track and meeting. This step has TWO critical functions:

FUNCTION 1 — TRACK CONDITION VERIFICATION:
Search X for "[track name] track condition" and "[track name] upgrade OR downgrade" for today.
- If the track condition has CHANGED from what is provided in the race data:
  > STATE the updated condition clearly (e.g., "Track upgraded from Soft 5 to Good 4")
  > Flag that Condition stats in the data may now be UNRELIABLE (they reflect the old surface)
  > If you cannot verify the current condition, note this and reduce confidence by 5 points
- Track condition changes are COMMON — always check for them

FUNCTION 2 — TRACK BIAS AND RACE INTELLIGENCE:
Search for:
- Track bias reports (inside/outside rail advantage, leader bias, on-pace vs off-pace)
- Rail position and how it is affecting racing
- Late scratchings or jockey changes

TRUSTED SOURCES (prioritise these):
- Official racing club accounts (@ATC_races, @MelbRacingClub, @ARCRacing, @BrisRacingClub, @RacingWA_)
- Racing journalists (e.g., @RayThomas_1, @mabordracing, @benabordi)
- Professional form analysts (@DynamicOdds, @PuntingInsights, @ArionData, @RacingMate)
- On-course reporters noting rail positions and going descriptions

IGNORE: anonymous tipsters, promotional accounts, anyone posting tips/multis without data.

BIAS APPLICATION:
If a clear track bias is identified:
- ELEVATE this factor above standard form analysis
- A strong bias can override moderate form advantages
- Note bias strength: early in day (2-3 races) = tentative; mid-meeting (4-5) = meaningful; late (6+) = strong

If X returns no relevant data, state "No real-time data found" and proceed. Do NOT fabricate information.

STEP 8 — ML MODEL CROSS-REFERENCE:
The ML prediction model provides an independent, quantitative probability assessment.
- If your top pick is ML model's #1: ADDS CONFIDENCE (+5 to score)
- If your top pick is ML #2-3: NEUTRAL
- If your top pick is ML #4+: REQUIRES EXPLANATION — articulate why you see something the model doesn't
- Race-level ML confidence "low" = genuinely open race — lower your own confidence accordingly
- If no ML data is available, skip this step and note "No ML predictions available"

STEP 9 — DEVIL'S ADVOCATE:
BEFORE finalising any selection, you MUST argue AGAINST your own pick:
- Identify the SINGLE STRONGEST REASON this horse could lose
- Is that reason a LIKELY scenario or just a theoretical possibility?
- If the reason is likely (e.g., "has never won at this distance and is stepping up 400m", "has 0% condition win rate on today's going from 5+ starts"), REDUCE confidence by 5-10 points or WITHDRAW the selection entirely
- If you cannot find a meaningful reason the horse could lose, your confidence can remain as assessed
- STATE your Devil's Advocate argument in step9_devils_advocate — this is mandatory even for strong picks

STEP 10 — EDGE IDENTIFICATION:
Only select a horse if ALL of the following are true:
1. At least ONE PRIMARY FACTOR is present (see Factor Classification above)
2. At least TWO SECONDARY FACTORS support the selection
3. No unresolved red flags remain
4. The Devil's Advocate argument in Step 9 did not reveal a fatal flaw
5. Your confidence score, after all adjustments, is still 60+

MANDATORY NO SELECTION TRIGGERS (if ANY of these apply, output NO SELECTION):
- Every serious contender has at least one unresolved red flag
- The top contender's overall win% is below the field average AND they have no compensating class/conditions edge
- The field has 3+ horses with near-identical form and stats profiles with no clear separator — it is a genuinely open race
- Maiden races with 10+ runners and no standout on form/trials — these are lotteries
- No horse in the field has won or placed at today's Track+Distance (all Track+Dist win% = 0) AND it is a provincial/country venue
- The track condition has changed (per Step 7) and the change materially affects your pick's key advantage

RED FLAGS:
These are caution signals. Multiple red flags on the same horse = automatic NO SELECTION on that horse.

- Form contains "f" (failed to finish) in the last 3 starts
- First-up from spell with no proven fresh record and trainer lacks strong first-up strike rate
- No wins or places at today's distance AND no form indicators suggesting the trip will suit
- Carrying 3+kg above field average weight in a handicap at 1600m+
- Wide barrier in sprint races (<1400m) UNLESS track bias favours outside
- Very low Track win% or Dist win% (<10%) with 5+ starts sample size
- Deteriorating form across last 4+ starts with no clear excuse
- 2+ NEGATIVE form badges present
- assessment="big_rise" with no supporting class trend
- Overall win% significantly below field average (>5% lower)

RED FLAG OVERRIDES (a red flag can be discounted when):
- First-up: firstUp winPercent >15% OR placePercent >40% — proven fresh performer
- Distance untried: breeding suggests trip will suit AND small sample (<5 starts at distance)
- Wide barrier: track bias data or Step 7 confirms outside runners favoured today
- Low Dist win%: small sample size (<5 starts) makes the percentage unreliable

CONFIDENCE CALIBRATION (strict):
- 60-64: Lean selection — minimum conviction. One primary + two secondary factors. Use sparingly.
- 65-69: Moderate edge — factors align but some uncertainty. Default score when evidence is solid but not compelling.
- 70-74: Solid edge — THREE or more factors align, no red flags, horse demonstrably stands above field average in at least two statistical categories. This is a GOOD bet.
- 75-79: Strong edge — everything aligns AND the horse has a PROVEN record in today's specific conditions (Track+Dist win% >25% OR Condition win% >30% from meaningful sample).
- 80-84: Very strong — above criteria PLUS ML model agreement (top-2 ranked) AND class fit advantage.
- 85+: Near-certainty — exceptional form, weak field, perfect conditions, ML #1, strong class edge. Maximum once per 20 race cards.

CRITICAL: If you cannot clearly articulate why a horse deserves a score ABOVE 70, default to 65-69. The burden of proof INCREASES with each point. Most selections should fall in the 62-72 range.

UNIT SIZING:
- 1-2 units: Confidence 60-64
- 2-3 units: Confidence 65-69
- 4-5 units: Confidence 70-74
- 5-6 units: Confidence 75-79
- 7-8 units: Confidence 80-84
- 9-10 units: Confidence 85+

Return ONLY valid JSON in this format:
{
  "analysis": {
    "step1_field": "Field assessment: size, quality, race type, race class, venue quality level, competitiveness.",
    "step2_pace": "Pace analysis: pace scenario, speed map assessment, which running styles are favoured.",
    "step3_form": "Form analysis of serious contenders. Read form RIGHT to LEFT. Who is improving, declining, consistent? Note badges that confirm or conflict.",
    "step4_conditions": "Conditions match: track condition (note if changed per Step 7), distance, track bias, barriers.",
    "step5_class_weight": "Class assessment using classProfile + raceClassFit data. Weight analysis with apprentice claims.",
    "step6_connections": "Jockey/trainer assessment with stats data. First-up/second-up stats for resuming horses.",
    "step7_intelligence": "X search: track condition verification (upgrades/downgrades), track bias, late changes. State findings or 'No real-time data found'.",
    "step8_ml": "ML model cross-reference. Note agreement or disagreement with your assessment.",
    "step9_devils_advocate": "MANDATORY: The strongest reason your pick could lose. Is it likely or theoretical? Confidence adjustment if any.",
    "step10_edge": "Final verdict: PRIMARY factor identified? TWO+ secondary factors? Red flags resolved? Devil's Advocate survived? If not, state NO SELECTION and why."
  },
  "selections": [
    {
      "horseName": "Exact Horse Name",
      "confidence": 68,
      "units": 3,
      "reason": "Concise summary referencing specific data points. Must name the PRIMARY factor and SECONDARY factors.",
      "redFlagsChecked": "List any red flags considered and whether they were overridden. State 'None' if no flags apply.",
      "trackBias": "Bias identified from data and/or X and how it affects this selection, or 'None identified'.",
      "paceAssessment": "How the pace scenario suits this horse's running style.",
      "classAssessment": "Class fit assessment from classProfile data.",
      "mlModelRank": 1,
      "mlWinProb": 0.283,
      "keyBadges": ["Last Start Winner (+)", "Track Specialist (+)", "Fitness: Race Hardened (+)"]
    }
  ]
}

Rules:
- AT MOST ONE horse per race. Return empty selections array if no genuine edge.
- NO SELECTION is the DEFAULT. You must justify selecting, not justify passing.
- Only select if confidence is 60+ AFTER all adjustments (including Devil's Advocate).
- Selection requires ONE primary factor + TWO secondary factors minimum.
- If ANY mandatory NO SELECTION trigger applies, return empty selections.
- If multiple red flags apply to the only viable contender, return empty selections.
- The "reason" MUST name the primary factor and reference specific data points.
- Do not fabricate X/real-time data. If no data exists, say so in step7_intelligence.
- Confidence 75+ requires PROVEN record in today's specific conditions with data to back it.
- ALWAYS provide ALL 10 analysis steps regardless of whether you make a selection.
- mlModelRank, mlWinProb, and keyBadges may be null if data is not available.
- Most selections should score 62-72. Scores above 75 should be rare. Above 80 should be exceptional.`;

// Parse form string into structured results (most recent run is rightmost)
function parseFormString(formStr) {
  if (!formStr) return { parsed: [], summary: { starts: 0, wins: 0, places: 0, spells: 0, fails: 0, winRate: 0, placeRate: 0, avgFinishPos: 0, lastThree: '' } };
  const parsed = [];
  for (const ch of formStr) {
    if (ch >= '1' && ch <= '9') {
      const pos = parseInt(ch);
      parsed.push({ pos, isWin: pos === 1, isPlace: pos <= 3, isSpell: false, isFail: false });
    } else if (ch === '0') {
      parsed.push({ pos: 10, isWin: false, isPlace: false, isSpell: false, isFail: false });
    } else if (ch === 'x') {
      parsed.push({ pos: null, isWin: false, isPlace: false, isSpell: true, isFail: false });
    } else if (ch === 'f') {
      parsed.push({ pos: null, isWin: false, isPlace: false, isSpell: false, isFail: true });
    } else if (ch === 'd') {
      parsed.push({ pos: null, isWin: false, isPlace: false, isSpell: false, isFail: false });
    }
  }
  const finishers = parsed.filter(p => p.pos !== null);
  const wins = parsed.filter(p => p.isWin).length;
  const places = parsed.filter(p => p.isPlace).length;
  const spells = parsed.filter(p => p.isSpell).length;
  const fails = parsed.filter(p => p.isFail).length;
  const starts = parsed.length;
  // Last 3 runs summary (rightmost = most recent)
  const lastThree = formStr.slice(-3);
  return {
    parsed,
    summary: {
      starts,
      wins,
      places,
      spells,
      fails,
      winRate: starts > 0 ? Math.round((wins / starts) * 100) : 0,
      placeRate: starts > 0 ? Math.round((places / starts) * 100) : 0,
      avgFinishPos: finishers.length > 0 ? parseFloat((finishers.reduce((s, p) => s + p.pos, 0) / finishers.length).toFixed(1)) : 0,
      lastThree
    }
  };
}

// Pre-compute derived metrics for the AI
function enrichRaceData(race) {
  const runners = (race.runners || []).filter(r => !r.scratched);
  const fieldSize = runners.length;
  // Parse track condition (e.g., "Good 4", "Soft 6", "Heavy 8")
  const condMatch = (race.condition || '').match(/^(\w+)\s*(\d+)?$/);
  const conditionRating = condMatch ? condMatch[1] : race.condition || 'Unknown';
  const conditionNumber = condMatch && condMatch[2] ? parseInt(condMatch[2]) : 0;
  const isWet = /soft|heavy/i.test(conditionRating);
  // Parse distance to meters
  const distMatch = (race.distance || '').match(/(\d+)/);
  const distanceMeters = distMatch ? parseInt(distMatch[1]) : 0;
  let distanceCategory = 'unknown';
  if (distanceMeters > 0) {
    if (distanceMeters <= 1200) distanceCategory = 'sprint';
    else if (distanceMeters <= 1500) distanceCategory = 'short';
    else if (distanceMeters <= 1650) distanceCategory = 'mile';
    else if (distanceMeters <= 2200) distanceCategory = 'middle distance';
    else distanceCategory = 'staying';
  }
  // Field averages
  const avgWeight = fieldSize > 0 ? runners.reduce((s, r) => s + (r.weight || 0), 0) / fieldSize : 0;
  const avgWinPct = fieldSize > 0 ? runners.reduce((s, r) => s + (r.stats?.overall?.winPercent || 0), 0) / fieldSize : 0;
  const avgPlacePct = fieldSize > 0 ? runners.reduce((s, r) => s + (r.stats?.overall?.placePercent || 0), 0) / fieldSize : 0;
  const avgClassRating = fieldSize > 0 ? runners.reduce((s, r) => s + (r.classProfile?.currentRating || 0), 0) / fieldSize : 0;

  // Track bias data
  const trackBias = race.trackBiasData || null;
  // Predictions data
  const predictions = race.predictionsData || null;
  const predictionsByRunner = {};
  if (predictions && predictions.runners) {
    for (const p of predictions.runners) {
      predictionsByRunner[p.runnerNumber || p.number] = p;
    }
  }

  // Enrich each runner
  const enrichedRunners = runners.map(r => {
    const formData = parseFormString(r.form);
    const formChars = (r.form || '').split('');
    const isFirstUp = formChars.length >= 2 && formChars[formChars.length - 1] !== 'x' && formChars.includes('x') && formChars.lastIndexOf('x') === formChars.length - 2;
    const isResuming = formChars.length >= 1 && formChars[formChars.length - 1] === 'x';

    // Effective weight with apprentice claim
    const effectiveWeight = (r.weight || 0) - (r.claim || 0);

    // Track bias: per-runner barrier advantage
    let barrierAdvantage = null;
    if (trackBias && trackBias.barriers) {
      const biasEntry = trackBias.barriers.find(b => b.barrier === r.barrier);
      if (biasEntry) barrierAdvantage = biasEntry.advantage || null;
    }

    // ML prediction for this runner
    const pred = predictionsByRunner[r.number] || null;

    // Decorator summary
    let badgeSummary = null;
    if (r.decorators && r.decorators.length > 0) {
      const pos = r.decorators.filter(d => d.sentiment === '+').length;
      const neg = r.decorators.filter(d => d.sentiment === '-').length;
      badgeSummary = { positive: pos, negative: neg, total: r.decorators.length };
    }

    // Jockey/trainer stats from cache
    const jockeyStats = jockeyStatsCache[(r.jockey || '').toLowerCase().trim()] || null;
    const trainerStats = trainerStatsCache[(r.trainer || '').toLowerCase().trim()] || null;

    return {
      ...r,
      formParsed: formData.summary,
      weightDiff: parseFloat(((r.weight || 0) - avgWeight).toFixed(1)),
      effectiveWeight: parseFloat(effectiveWeight.toFixed(1)),
      effectiveWeightDiff: parseFloat((effectiveWeight - avgWeight).toFixed(1)),
      winPctDiff: parseFloat(((r.stats?.overall?.winPercent || 0) - avgWinPct).toFixed(1)),
      placePctDiff: parseFloat(((r.stats?.overall?.placePercent || 0) - avgPlacePct).toFixed(1)),
      isWideBarrier: (r.barrier || 0) > fieldSize * 0.7,
      isFirstUp,
      isResuming,
      hasRecentFail: formChars.slice(-3).includes('f'),
      barrierAdvantage,
      prediction: pred,
      badgeSummary,
      jockeyStats,
      trainerStats,
    };
  });

  return {
    ...race,
    runners: enrichedRunners,
    fieldSize,
    trackCondition: { rating: conditionRating, number: conditionNumber, isWet },
    distanceMeters,
    distanceCategory,
    trackBias,
    mlModelConfidence: predictions?.confidence || null,
    fieldAvg: {
      weight: parseFloat(avgWeight.toFixed(1)),
      winPct: parseFloat((avgWinPct * 100).toFixed(1)),
      placePct: parseFloat((avgPlacePct * 100).toFixed(1)),
      classRating: parseFloat(avgClassRating.toFixed(1)),
    }
  };
}

async function fetchRace(date, track, raceNumber) {
  try {
    const url = `https://api.formfav.com/v1/form?date=${date}&track=${track}&race=${raceNumber}&race_code=gallops&country=au`;
    const { data } = await axios.get(url, {
      headers: { 'X-API-Key': FORMAV_API_KEY }
    });
    return data;
  } catch (err) {
    if (err.response && err.response.status !== 404) {
      serverLog(`   FormFav error for ${track} R${raceNumber}: ${err.response.status} ${err.response.statusText}`);
    }
    return null;
  }
}

// Phase 2: Fetch track bias data (cached per track per session)
async function fetchTrackBias(track) {
  if (trackBiasCache[track]) return trackBiasCache[track];
  try {
    const url = `https://api.formfav.com/v1/stats/track-bias/${track}?race_code=gallops&min_starts=50&window=90`;
    const { data } = await axios.get(url, {
      headers: { 'X-API-Key': FORMAV_API_KEY }
    });
    trackBiasCache[track] = data;
    serverLog(`Track bias loaded for ${track} (bias: ${data.biasStrength || 'unknown'})`);
    return data;
  } catch (err) {
    if (err.response && err.response.status === 404) return null;
    serverLog(`Track bias fetch failed for ${track}: ${err.message}`);
    return null;
  }
}

// Phase 2: Fetch ML predictions per race (beta — may not be available)
async function fetchPredictions(date, track, raceNumber) {
  try {
    const url = `https://api.formfav.com/v1/predictions?date=${date}&track=${track}&race=${raceNumber}&race_code=gallops`;
    const { data } = await axios.get(url, {
      headers: { 'X-API-Key': FORMAV_API_KEY }
    });
    return data;
  } catch (err) {
    // Silently handle 404 — predictions endpoint may not be available yet
    if (err.response && err.response.status === 404) return null;
    serverLog(`Predictions fetch failed for ${track} R${raceNumber}: ${err.message}`);
    return null;
  }
}

// Phase 4: Fetch jockey stats (cached per session)
async function fetchJockeyStats(name) {
  if (!name) return null;
  const key = name.toLowerCase().trim();
  if (jockeyStatsCache[key]) return jockeyStatsCache[key];
  try {
    const url = `https://api.formfav.com/v1/stats/jockey/${encodeURIComponent(name)}?race_code=gallops&window=90`;
    const { data } = await axios.get(url, {
      headers: { 'X-API-Key': FORMAV_API_KEY }
    });
    jockeyStatsCache[key] = data;
    return data;
  } catch (err) {
    jockeyStatsCache[key] = null;
    return null;
  }
}

// Phase 4: Fetch trainer stats (cached per session)
async function fetchTrainerStats(name) {
  if (!name) return null;
  const key = name.toLowerCase().trim();
  if (trainerStatsCache[key]) return trainerStatsCache[key];
  try {
    const url = `https://api.formfav.com/v1/stats/trainer/${encodeURIComponent(name)}?race_code=gallops&window=90`;
    const { data } = await axios.get(url, {
      headers: { 'X-API-Key': FORMAV_API_KEY }
    });
    trainerStatsCache[key] = data;
    return data;
  } catch (err) {
    trainerStatsCache[key] = null;
    return null;
  }
}

// Phase 4: Batch fetch jockey/trainer stats for all unique names in a track's races
async function fetchConnectionStats(races) {
  const jockeys = new Set();
  const trainers = new Set();
  for (const race of races) {
    for (const r of (race.runners || [])) {
      if (r.jockey) jockeys.add(r.jockey);
      if (r.trainer) trainers.add(r.trainer);
    }
  }
  serverLog(`Fetching stats for ${jockeys.size} jockeys, ${trainers.size} trainers...`);
  const BATCH = 10;
  const allNames = [...[...jockeys].map(n => ({ type: 'jockey', name: n })), ...[...trainers].map(n => ({ type: 'trainer', name: n }))];
  for (let i = 0; i < allNames.length; i += BATCH) {
    const batch = allNames.slice(i, i + BATCH);
    await Promise.all(batch.map(({ type, name }) =>
      type === 'jockey' ? fetchJockeyStats(name) : fetchTrainerStats(name)
    ));
  }
  serverLog(`Connection stats loaded (${Object.keys(jockeyStatsCache).length} jockeys, ${Object.keys(trainerStatsCache).length} trainers cached)`);
}

// Parse the raceFilter param: "caulfield:3,4,5;randwick:2,3,4" -> { caulfield: [3,4,5], randwick: [2,3,4] }
// If no filter provided, returns null (scrape all races 1-10 for each track)
function parseRaceFilter(filterParam) {
  if (!filterParam || filterParam.trim() === '') return null;
  const filter = {};
  for (const entry of filterParam.split(';')) {
    const [track, nums] = entry.split(':');
    if (track && nums) {
      filter[track.trim()] = nums.split(',').map(n => parseInt(n.trim())).filter(n => !isNaN(n));
    }
  }
  return Object.keys(filter).length > 0 ? filter : null;
}

async function scrapeFormFav(tracks, raceFilter) {
  const date = new Intl.DateTimeFormat('en-CA', { timeZone: 'Australia/Sydney' })
    .format(new Date())
    .split('T')[0];
  serverLog(`Fetching real data from FormFav Pro for Sydney date: ${date} (${tracks.length} tracks)`);
  if (raceFilter) {
    const totalRaces = Object.values(raceFilter).reduce((sum, nums) => sum + nums.length, 0);
    serverLog(`Race filter active: ${totalRaces} future races across ${Object.keys(raceFilter).length} tracks`);
  }

  // Clear session caches at the start of each scrape
  trackBiasCache = {};
  jockeyStatsCache = {};
  trainerStatsCache = {};

  const allRaces = [];
  let skippedPast = 0;

  for (const track of tracks) {
    const allowedRaces = raceFilter ? (raceFilter[track] || []) : null;
    const trackRaces = [];

    for (let raceNum = 1; raceNum <= 10; raceNum++) {
      if (allowedRaces && !allowedRaces.includes(raceNum)) {
        skippedPast++;
        continue;
      }
      const data = await fetchRace(date, track, raceNum);
      if (data && data.runners && data.runners.length > 0) {
        // Phase 1: Expanded runner/race mapping with Pro fields
        const race = {
          id: `${track}-R${raceNum}`,
          date: new Date(date),
          track: track.toUpperCase().replace('-', ' '),
          raceNumber: raceNum,
          distance: data.distance || "Unknown",
          condition: data.condition || "Good 4",
          weather: data.weather || "Fine",
          // New Pro race-level fields
          paceScenario: data.paceScenario || null,
          raceClass: data.raceClass || null,
          raceName: data.raceName || null,
          startTime: data.startTime || null,
          numberOfRunners: data.numberOfRunners || 0,
          trackBiasData: null, // filled below after races loaded
          predictionsData: null, // filled below
          runners: data.runners
            .filter(r => !r.scratched) // Filter scratched runners
            .map(r => ({
              number: r.number,
              name: r.name,
              jockey: r.jockey || "",
              trainer: r.trainer || "",
              weight: r.weight || 0,
              barrier: r.barrier || 0,
              form: r.form || "",
              stats: {
                ...(r.stats || {}),
                firstUp: r.stats?.firstUp || null,
                secondUp: r.stats?.secondUp || null,
              },
              // New Pro runner-level fields
              age: r.age || null,
              claim: r.claim || null,
              scratched: r.scratched || false,
              decorators: r.decorators || null,
              speedMap: r.speedMap || null,
              classProfile: r.classProfile || null,
              raceClassFit: (() => {
                const rcf = r.raceClassFit;
                if (!rcf) return null;
                // Compute classDifference from classProfile if API returns 0
                if (rcf.classDifference === 0 && r.classProfile && r.classProfile.currentRating && rcf.raceClassRating) {
                  rcf.classDifference = r.classProfile.currentRating - rcf.raceClassRating;
                }
                return rcf;
              })(),
            }))
        };
        trackRaces.push(race);
        allRaces.push(race);
        serverLog(`Loaded ${track} R${raceNum} (${race.runners.length} runners${data.paceScenario ? `, pace: ${data.paceScenario}` : ''})`);
      }
    }

    // Phase 2: Fetch track bias data only if we have races for this track
    if (trackRaces.length > 0) {
      const trackBias = await fetchTrackBias(track);
      if (trackBias) {
        for (const r of trackRaces) {
          r.trackBiasData = trackBias;
        }
      }
    }

    // Phase 2: Fetch predictions for all races on this track in parallel (beta)
    if (trackRaces.length > 0) {
      const predResults = await Promise.all(
        trackRaces.map(r => fetchPredictions(date, track, r.raceNumber))
      );
      const predCount = predResults.filter(p => p != null).length;
      for (let i = 0; i < trackRaces.length; i++) {
        trackRaces[i].predictionsData = predResults[i] || null;
      }
      if (predCount > 0) {
        serverLog(`ML predictions loaded for ${predCount}/${trackRaces.length} races at ${track}`);
      }
    }

    // Phase 4: Fetch jockey/trainer stats for this track's races
    if (trackRaces.length > 0) {
      await fetchConnectionStats(trackRaces);
    }
  }

  if (skippedPast > 0) {
    serverLog(`Skipped ${skippedPast} past/filtered races`);
  }
  serverLog(`FormFav Pro loaded ${allRaces.length} upcoming races`);
  return allRaces;
}

async function analyzeRaceWithGrok(race) {
  if (!XAI_API_KEY) {
    serverLog('No XAI_API_KEY configured');
    return { selections: [], analysis: "" };
  }
  try {
    serverLog(`Analyzing ${race.track} R${race.raceNumber} with Grok AI...`);
    const enriched = enrichRaceData(race);
    const runnersText = enriched.runners.map(r => {
      const fs = r.formParsed;
      // Build flags string for quick AI reference
      const flags = [];
      if (r.isFirstUp) flags.push('FIRST-UP');
      if (r.isResuming) flags.push('RESUMING (spell in progress)');
      if (r.isWideBarrier) flags.push('WIDE BARRIER');
      if (r.hasRecentFail) flags.push('RECENT DNF');
      if (r.weightDiff >= 3) flags.push(`HEAVY WEIGHT (+${r.weightDiff}kg)`);
      const flagStr = flags.length > 0 ? `\n  FLAGS: ${flags.join(', ')}` : '';

      // Weight line with apprentice claim
      const claimStr = r.claim ? ` (claim: ${r.claim}kg = ${r.effectiveWeight}kg effective, ${r.effectiveWeightDiff > 0 ? '+' : ''}${r.effectiveWeightDiff}kg vs field avg)` : ` (${r.weightDiff > 0 ? '+' : ''}${r.weightDiff}kg vs field avg)`;

      // Barrier with track bias advantage
      const biasStr = r.barrierAdvantage != null ? ` | Barrier Bias: ${r.barrierAdvantage > 0 ? '+' : ''}${r.barrierAdvantage.toFixed(1)}% advantage` : '';

      // First-up / second-up stats
      const fuStats = r.stats?.firstUp;
      const suStats = r.stats?.secondUp;
      const fuLine = fuStats && fuStats.starts > 0 ? `\n  First-Up: ${fuStats.starts} starts, ${fuStats.wins}W (${((fuStats.winPercent || 0) * 100).toFixed(0)}% win, ${((fuStats.placePercent || 0) * 100).toFixed(0)}% place)` : '';
      const suLine = suStats && suStats.starts > 0 ? `\n  Second-Up: ${suStats.starts} starts, ${suStats.wins}W (${((suStats.winPercent || 0) * 100).toFixed(0)}% win, ${((suStats.placePercent || 0) * 100).toFixed(0)}% place)` : '';

      // Speed map
      const sm = r.speedMap;
      const smLine = sm ? `\n  Speed Map: ${sm.runningStyle || 'X'} | ESI: ${(sm.earlySpeedIndex || 0).toFixed(1)} | Settling Pos: ${(sm.settlingPosition || 0).toFixed(1)}` : '';

      // Class profile
      const cp = r.classProfile;
      const rcf = r.raceClassFit;
      const classLine = cp ? `\n  Class: Current ${cp.currentRating || '?'} | Peak ${cp.peakRating || '?'}${cp.highestClassWon ? ` | Won up to ${cp.highestClassWon}` : ''}${cp.optimalRangeMin != null ? ` | Optimal ${cp.optimalRangeMin}-${cp.optimalRangeMax}` : ''} | Trend: ${cp.trend || 'unknown'}` : '';
      const fitLine = rcf ? `\n  Race Fit: ${rcf.assessment} (diff: ${rcf.classDifference}, ${rcf.withinOptimalRange ? 'within optimal range' : 'outside optimal range'})` : '';

      // ML prediction
      const pred = r.prediction;
      const mlLine = pred ? `\n  ML Model: Win ${(pred.winProb * 100).toFixed(1)}% | Place ${(pred.placeProb * 100).toFixed(1)}% | Rank ${pred.modelRank}/${enriched.fieldSize}` : '';

      // Badges/decorators
      const badges = r.decorators;
      const badgeLine = badges && badges.length > 0
        ? `\n  Badges: ${badges.map(b => `[${b.sentiment}] ${b.label}${b.detail ? ` (${b.detail})` : ''}`).join(', ')}`
        : '';

      // Jockey stats summary
      const js = r.jockeyStats;
      const jsLine = js ? `\n  Jockey Stats (90d): Win ${((js.recentStats?.overallWinRate || js.overallWinRate || 0) * 100).toFixed(1)}% | Place ${((js.recentStats?.overallPlaceRate || js.overallPlaceRate || 0) * 100).toFixed(1)}%${js.bestCondition ? ` | Best: ${js.bestCondition}` : ''}` : '';

      // Trainer stats summary
      const ts = r.trainerStats;
      const tsLine = ts ? `\n  Trainer Stats (90d): Win ${((ts.recentStats?.overallWinRate || ts.overallWinRate || 0) * 100).toFixed(1)}% | Place ${((ts.recentStats?.overallPlaceRate || ts.overallPlaceRate || 0) * 100).toFixed(1)}%${ts.bestCondition ? ` | Best: ${ts.bestCondition}` : ''}` : '';

      return `#${r.number} ${r.name}
  Jockey: ${r.jockey} | Trainer: ${r.trainer || 'Unknown'}${r.age ? ` | Age: ${r.age}` : ''}
  Weight: ${r.weight}kg${claimStr}
  Barrier: ${r.barrier}${r.isWideBarrier ? ' (WIDE)' : ''}${biasStr}
  Form: ${r.form || 'No form'} => ${fs.starts} starts, ${fs.wins}W/${fs.places}P, avg finish: ${fs.avgFinishPos}${fs.spells > 0 ? `, ${fs.spells} spells` : ''}${fs.fails > 0 ? `, ${fs.fails} DNF` : ''} | Last 3: ${fs.lastThree}
  Stats: Win ${((r.stats?.overall?.winPercent || 0) * 100).toFixed(0)}% (${r.stats?.overall?.starts || 0} starts) | Track ${((r.stats?.track?.winPercent || 0) * 100).toFixed(0)}% (${r.stats?.track?.starts || 0}) | Dist ${((r.stats?.distance?.winPercent || 0) * 100).toFixed(0)}% (${r.stats?.distance?.starts || 0}) | Track+Dist ${((r.stats?.trackDistance?.winPercent || 0) * 100).toFixed(0)}% (${r.stats?.trackDistance?.starts || 0}) | Condition ${((r.stats?.condition?.winPercent || 0) * 100).toFixed(0)}% (${r.stats?.condition?.starts || 0})${fuLine}${suLine}${smLine}${classLine}${fitLine}${mlLine}${badgeLine}${jsLine}${tsLine}
  Win% vs field: ${r.winPctDiff > 0 ? '+' : ''}${(r.winPctDiff * 100).toFixed(1)}% | Place% vs field: ${r.placePctDiff > 0 ? '+' : ''}${(r.placePctDiff * 100).toFixed(1)}%${flagStr}`;
    }).join('\n\n');

    // Track bias summary
    const tb = enriched.trackBias;
    const trackBiasLine = tb ? `TRACK BIAS: ${tb.biasStrength || 'unknown'} | Strongest: barrier ${tb.strongestBarrier || '?'} | Weakest: barrier ${tb.weakestBarrier || '?'}` : 'TRACK BIAS: No data available';

    const userMessage = `RACE: ${enriched.track} Race ${enriched.raceNumber}${enriched.raceName ? ` (${enriched.raceName})` : ''}
DISTANCE: ${enriched.distance} (${enriched.distanceCategory})
CONDITION: ${enriched.condition} (${enriched.trackCondition.isWet ? 'WET TRACK' : 'DRY TRACK'})
WEATHER: ${enriched.weather}
${enriched.raceClass ? `RACE CLASS: ${enriched.raceClass}\n` : ''}${enriched.paceScenario ? `PACE SCENARIO: ${enriched.paceScenario}\n` : ''}FIELD SIZE: ${enriched.fieldSize} runners
${trackBiasLine}
${enriched.mlModelConfidence ? `ML MODEL CONFIDENCE: ${enriched.mlModelConfidence}` : 'ML MODEL: No predictions available'}
FIELD AVERAGES:
- Weight: ${enriched.fieldAvg.weight}kg | Win%: ${enriched.fieldAvg.winPct}% | Place%: ${enriched.fieldAvg.placePct}%${enriched.fieldAvg.classRating > 0 ? ` | Class Rating: ${enriched.fieldAvg.classRating}` : ''}

RUNNERS:
${runnersText}

Analyze this race step by step using the methodology. Search X for "${enriched.track} racing" and "${enriched.track} track bias" for today's real-time intel. Return at most one selection if there is a genuine edge.`;

    const aiResponse = await axios.post('https://api.x.ai/v1/chat/completions', {
      model: "grok-4-1-fast-reasoning",
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: userMessage }
      ],
      temperature: 0.3,
      max_tokens: 3000,
      search_mode: "auto"
    }, {
      headers: {
        'Authorization': `Bearer ${XAI_API_KEY}`,
        'Content-Type': 'application/json'
      }
    });

    let aiText = aiResponse.data.choices[0].message.content.trim();
    // Aggressive JSON cleaning
    if (aiText.includes('```json')) {
      aiText = aiText.split('```json')[1].split('```')[0].trim();
    } else if (aiText.includes('```')) {
      aiText = aiText.split('```')[1].trim();
    }
    const jsonStart = aiText.indexOf('{');
    const jsonEnd = aiText.lastIndexOf('}');
    if (jsonStart !== -1 && jsonEnd !== -1) {
      aiText = aiText.substring(jsonStart, jsonEnd + 1);
    }

    let aiResult;
    try {
      aiResult = JSON.parse(aiText);
    } catch (parseErr) {
      serverLog(`JSON parse failed for ${race.track} R${race.raceNumber}: ${parseErr.message}`);
      serverLog(`   Raw AI response (first 300 chars): ${aiText.substring(0, 300)}`);
      return { selections: [], analysis: "" };
    }

    const picks = aiResult.selections || [];

    // Validate selection integrity
    if (picks.length > 0) {
      const pick = picks[0];
      // Ensure confidence matches unit sizing rules
      if (pick.confidence < 60) {
        serverLog(`Rejected ${race.track} R${race.raceNumber} pick: confidence ${pick.confidence} below 60 threshold`);
        picks.length = 0;
      } else {
        // Verify horse name exists in the race
        const horseNames = enriched.runners.map(r => r.name.toLowerCase());
        if (!horseNames.includes((pick.horseName || '').toLowerCase())) {
          serverLog(`WARNING: Grok picked "${pick.horseName}" for ${race.track} R${race.raceNumber} but horse not found in field`);
        }
        serverLog(`Grok AI pick for ${race.track} R${race.raceNumber}: ${pick.horseName} (confidence: ${pick.confidence}, units: ${pick.units})${pick.trackBias ? ` | Bias: ${pick.trackBias}` : ''}`);
      }
    } else {
      serverLog(`Grok AI: no confident pick for ${race.track} R${race.raceNumber}`);
    }
    return {
      selections: picks,
      analysis: typeof aiResult.analysis === 'object'
        ? Object.entries(aiResult.analysis).map(([k, v]) => {
            const labels = {
              step1_field: 'Field Assessment',
              step2_pace: 'Pace Analysis',
              step3_form: 'Form Analysis',
              step4_conditions: 'Conditions Match',
              step5_class_weight: 'Class & Weight',
              step6_connections: 'Connections',
              step7_intelligence: 'Real-Time Intelligence',
              step8_ml: 'ML Model Cross-Reference',
              step9_devils_advocate: "Devil's Advocate",
              step10_edge: 'Edge Identification'
            };
            return `${labels[k] || k}:\n${v}`;
          }).join('\n\n')
        : (aiResult.analysis || "")
    };
  } catch (err) {
    serverLog(`Grok AI failed for ${race.track} R${race.raceNumber}: ${err.message}`);
    if (err.response) {
      serverLog(`   Error details: ${JSON.stringify(err.response.data)}`);
    }
    return { selections: [], analysis: "" };
  }
}

// Routes
app.all('/scrape-now', requireAuth, async (req, res) => {
  try {
    serverLogs = [];
    const tracksParam = req.query.tracks;
    if (!tracksParam || tracksParam.trim() === '') {
      serverLog('No racetracks have been selected to analyse');
      return res.status(400).json({ error: "No racetracks have been selected to analyse" });
    }
    const tracks = tracksParam.split(',').map(t => t.trim()).filter(Boolean);
    const raceFilter = parseRaceFilter(req.query.raceFilter);
    serverLog(`Scrape-now called (ai=${req.query.ai || 'false'}, tracks: ${tracks.join(', ')}${raceFilter ? ', filtered' : ''})`);
    const races = await scrapeFormFav(tracks, raceFilter);
    if (req.query.ai === 'true' && XAI_API_KEY) {
      const BATCH_SIZE = 4; // Run 4 Grok calls in parallel
      serverLog(`Running Grok AI analysis on ${races.length} races (batches of ${BATCH_SIZE})...`);
      for (let i = 0; i < races.length; i += BATCH_SIZE) {
        const batch = races.slice(i, i + BATCH_SIZE);
        const batchNum = Math.floor(i / BATCH_SIZE) + 1;
        const totalBatches = Math.ceil(races.length / BATCH_SIZE);
        serverLog(`Batch ${batchNum}/${totalBatches}: ${batch.map(r => `${r.track} R${r.raceNumber}`).join(', ')}`);
        const results = await Promise.all(batch.map(race => analyzeRaceWithGrok(race)));
        for (let j = 0; j < batch.length; j++) {
          batch[j].suggestions = results[j].selections;
          batch[j].aiAnalysis = results[j].analysis;
        }
      }
      const picksCount = races.filter(r => r.suggestions.length > 0).length;
      const passCount = races.length - picksCount;
      serverLog(`Grok AI complete — ${picksCount} picks, ${passCount} passes from ${races.length} races (${Math.round(passCount / races.length * 100)}% pass rate)`);
    } else {
      races.forEach(r => { r.suggestions = []; r.aiAnalysis = ""; });
    }
    latestRaces = races;
    res.json({
      status: "ok",
      races: races.length,
      picks: races.filter(r => r.suggestions && r.suggestions.length > 0).length,
      passes: races.filter(r => !r.suggestions || r.suggestions.length === 0).length,
      date: new Date().toISOString().split('T')[0],
      source: req.query.ai === 'true' ? "Grok AI + FormFav" : "FormFav"
    });
  } catch (err) {
    serverLog(`Scrape error: ${err.message}`);
    res.status(500).json({ status: "error", message: err.message });
  }
});

app.get('/logs', requireAuth, (req, res) => {
  res.json(serverLogs);
});

app.get('/today-races', requireAuth, (req, res) => {
  res.json(latestRaces);
});

app.get('/', (req, res) => {
  res.json({ status: "ok", message: "EquiEdge Scraper running", version: "2.0" });
});

module.exports = app;
