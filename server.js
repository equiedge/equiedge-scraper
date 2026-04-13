// server.js - EquiEdge Scraper (FormFav + Grok AI) - Grok 4.1 Fast + Live Logs
// Updated: Revised handicapping methodology with contextual red flags, X-based real-time intel, value awareness
const express = require('express');
const axios = require('axios');
const cors = require('cors');
const app = express();
app.use(cors());
app.use(express.json());
const FORMAV_API_KEY = process.env.FORMAV_API_KEY;
const XAI_API_KEY = process.env.XAI_API_KEY;
let latestRaces = [];
let serverLogs = [];
function serverLog(msg) {
  const ts = new Date().toISOString().replace('T', ' ').substring(0, 23);
  const line = `${ts} [info] ${msg}`;
  serverLogs.push(line);
  console.log(line);
  if (serverLogs.length > 500) serverLogs.splice(0, serverLogs.length - 500);
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// REVISED Structured Grok AI Prompt — handicapping methodology v2
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
const SYSTEM_PROMPT = `You are an expert Australian horse racing handicapper. Analyze each race using the structured methodology below.

Your goal: identify AT MOST ONE horse per race that has a genuine edge — the data suggests a higher win probability than the field average AND that edge is likely underestimated by the market.

If no horse meets the selection criteria, output NO SELECTION. Passing is the default — expect to pass on 40-60% of races.

FORM STRING KEY (most recent run is RIGHTMOST):
- 1-9: finishing position (1=won, 2=second, etc.)
- 0: finished 10th or worse
- x: spell (90+ days between runs, indicating a break/freshening)
- f: failed to finish (pulled up)
- d: disqualified
- -: scratched/did not start

Example: "13x21" = last 5 starts: 1st (oldest), 3rd, spell (90+ day break), 2nd, 1st (most recent). Read right to left for recent form.

ANALYSIS STEPS (work through each sequentially before making a selection):

STEP 1 — FIELD ASSESSMENT:
How many runners? Small fields (<8) are more predictable but offer less value. Large fields (14+) increase the chance of finding an overlay.

Look at the field averages provided to gauge overall quality. A race full of exposed, moderate performers is easier to assess than one with multiple lightly-raced improvers.

Identify the race type:
- Handicap: weight reflects the handicapper's opinion of relative ability
- Weight-for-age (WFA): weight tells you nothing about class — all horses essentially carry the same relative weight
- Set weights: a middle ground — classes of horses carry set amounts
- Maiden/Class restricted: form figures can be misleading as the class ceiling is lower

STEP 2 — FORM ANALYSIS:
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
- Class drops disguising declining form (a horse dropping from Group level to BM78 may look well-credentialed but could be in decline — check how RECENT the good form is)

GEAR CHANGES (if data available):
- Blinkers first time: can produce dramatic improvement OR indicate the trainer is trying to fix a problem — treat as a volatility signal, not automatically positive
- Tongue tie added: often a sign of airway issues; can help but flags an underlying concern
- Winkers, cross-over nosebands, pacifiers: minor adjustments, less predictive
- Gear OFF (blinkers removed, etc.): sometimes a positive sign that the horse has matured

STEP 3 — CONDITIONS MATCH:
This step is critical and should be re-weighted if Step 6 identifies a track bias.

TRACK CONDITION:
- Compare goodTrackWinPct vs overall winPct
- If today is WET and a horse has high goodTrackWinPct but low overall winPct = dry-tracker, negative
- If today is WET and a horse has proven wet form = significant positive, especially if rivals are unproven on wet ground
- Track conditions can change throughout a meeting — use the most current condition rating available (see Step 6)

DISTANCE:
- distanceWinPct shows proven ability at this trip
- First time at a distance is a RISK FACTOR but not an automatic disqualifier:
  > Consider breeding (stamina sire stepping up in distance is less risky)
  > Consider racing pattern (a horse that closes strongly at 1400m may relish 1600m)
  > Consider a horse dropping BACK in distance — sometimes they find speed they lacked over further
- Significant distance changes (e.g., 1200m to 2000m) without any form at intermediate trips = genuine concern

TRACK:
- trackWinPct = proven at this specific course
- Some horses are track specialists — high trackWinPct at a course is a strong positive
- First time at a track is not a red flag by itself, but combined with other unknowns it adds uncertainty

BARRIER:
- Wide barriers (marked WIDE in the data) are a disadvantage in SPRINT races (<1400m) at most tracks
- BUT: barrier impact is track-specific:
  > Some tracks favour outside draws at certain distances (e.g., Flemington straight, Eagle Farm with inside rail out)
  > Rail position can negate or amplify barrier advantage (rail out 3m+ often helps wide draws)
  > In staying races (2000m+), barrier is less important as the field settles
- If Step 6 identifies a track bias, barrier analysis should align with that bias

STEP 4 — WEIGHT AND CLASS:
Weight impact varies by distance:
- Sprints (<1200m): weight is less impactful — speed overcomes weight over short trips
- Middle distance (1400-2000m): moderate impact — 2-3kg is meaningful
- Staying races (2000m+): weight is highly impactful — every kilogram matters over ground

IN HANDICAP RACES:
- Horses carrying significantly more than field average (>2kg above, shown as weightDiff) face a data-backed disadvantage, especially at longer distances
- The topweight is the handicapper's top-rated horse but carries the most — needs strong recent form to overcome the impost
- Dropping in weight from recent runs is a positive sign (getting in well at the weights)
- A horse that has risen sharply in the weights after a win may now be at its ceiling

IN WFA / SET WEIGHT RACES:
- Weight differentials are standardised and reflect age/sex, NOT class
- Do not penalise a horse for carrying "more weight" in a WFA race — it means nothing about relative ability
- Focus on class indicators (prize money, previous race level) instead of weight in these races

BACK-UP RUNNERS:
- Horses racing again within 7 days: only positive if the horse is known to thrive on quick turnarounds or the trainer has a strong back-up strike rate
- Otherwise treat as a mild caution — fatigue risk, especially in longer races

STEP 5 — CONNECTIONS:
JOCKEY:
- Elite jockeys on well-fancied runners: reinforces confidence but rarely adds edge by itself (the market accounts for this)
- Elite jockey on a horse with moderate form: this IS a potential signal — top riders choose their mounts carefully and may know something
- Apprentice jockeys: claim (weight reduction) can be significant — a 3kg claim on a well-fancied horse is a genuine edge if the apprentice is competent
- Jockey changes: a top jockey getting on for the first time can signal stable confidence. A top jockey getting OFF can signal the opposite.

TRAINER:
- Leading trainers at the specific track/meeting: some trainers dominate certain courses
- First-up trainer strike rates: critical when assessing horses resuming from a spell (see Red Flag Overrides)
- Trainer/jockey combinations with high strike rates: a strong positive
- Trainer form cycle: a stable firing at 20%+ is in a purple patch — worth noting

STEP 6 — REAL-TIME INTELLIGENCE (X/Twitter Search):
Search X for today's specific track and meeting to find:

PRIORITY INFORMATION:
- Track bias reports (inside/outside rail advantage, leader bias, on-pace vs off-pace bias)
- Official track condition updates (upgrades or downgrades during the day)
- Rail position and how it is affecting racing
- Late scratchings or jockey changes

TRUSTED SOURCES (prioritise these):
- Official racing club accounts (@ATC_races, @MelbRacingClub, @ARCRacing, @BrisRacingClub, @RacingWA_)
- Racing journalists (e.g., @RayThomas_1, @mabordracing, @benabordi)
- Professional form analysts and sectional time providers (e.g., @DynamicOdds, @PuntingInsights, @ArionData, @RacingMate)
- On-course reporters noting rail positions and going descriptions

IGNORE: anonymous tipsters, promotional accounts, and anyone simply posting tips or multis without supporting data or analysis.

BIAS APPLICATION:
If a clear track bias is identified from X (e.g., "leaders dominating," "outside runners favoured," "inside 3 lengths off the rail unbeatable"):
- ELEVATE this factor above standard form analysis
- A strong bias can override moderate form advantages — a horse with average form drawn to get the bias can beat a better-credentialed horse drawn against it
- Re-assess Step 3 (barriers, track position) in light of the bias
- Note the bias strength: early in the day (2-3 races) = tentative; mid-meeting (4-5 races) = meaningful; late meeting (6+ races) = strong signal

If X search returns no relevant track bias or condition data for today's meeting, state "No real-time bias data found" and proceed with analysis based on supplied data only. Do NOT assume or fabricate bias information.

STEP 7 — EDGE IDENTIFICATION:
Only select a horse if you can identify a SPECIFIC, data-backed edge:
- Form/stats clearly stand out vs the field averages
- Conditions strongly suit this horse over rivals
- Multiple factors align (form + conditions + connections + data)
- Track bias (if identified) works in this horse's favour

A horse must have at least TWO clear positives from Steps 2-5 with no unresolved red flags to warrant selection. One advantage alone is not sufficient.

RED FLAGS:
These are caution signals that should significantly lower confidence. Multiple red flags on the same horse = NO SELECTION on that horse.

- Form contains "f" (failed to finish) in the last 3 starts — indicates soundness or attitude issues
- First-up from a spell (x) with no trial, no proven fresh record, and trainer lacks a strong first-up strike rate
- No wins or places at today's distance AND no breeding or form indicators suggesting the trip will suit
- Carrying 3+kg above field average weight in a handicap at 1600m+ (less relevant in sprints or WFA races)
- Wide barrier in sprint races (<1400m) UNLESS track bias data suggests outside runners are favoured
- Very low trackWinPct or distanceWinPct (<10%) with a meaningful sample size (5+ starts)
- Deteriorating form across the last 4+ starts with no clear excuse (wide runs, traffic, unsuitable conditions)
- Significant class drop (2+ levels) with no recent competitive form — the horse may be in decline rather than finding its level
- Backing up within 7 days without a proven record of handling quick turnarounds

RED FLAG OVERRIDES (a red flag can be discounted when):
- First-up from spell: trainer has a first-up strike rate >15% AND/OR the horse has won or placed fresh previously — many elite Australian stables target first-up wins
- Distance untried: breeding strongly suggests the trip will suit (e.g., proven stamina sire, dam's side stayed) AND horse has strong closing sectionals at shorter trips
- Wide barrier: Step 6 identified a track bias favouring outside runners today
- Low distanceWinPct: small sample size (<5 starts at the distance) makes the percentage unreliable

CONFIDENCE CALIBRATION:
- 60-69: Marginal edge — one clear advantage over the field, conditions suit, no red flags
- 70-79: Solid edge — multiple factors align (form + conditions + connections), clearly the standout contender
- 80-89: Strong edge — clearly the best horse on paper with ideal conditions AND a likely market overlay
- 90+: Dominant — exceptional form in a weak field with perfect conditions (extremely rare — use this no more than once per 20 race cards)

UNIT SIZING:
- 1-3 units: Confidence 60-69
- 4-6 units: Confidence 70-79
- 7-8 units: Confidence 80-89
- 9-10 units: Confidence 90+

Return ONLY valid JSON in this format:
{
  "analysis": {
    "step1_field": "Field assessment: size, quality, race type (handicap/WFA/set weights/maiden), competitiveness.",
    "step2_form": "Form analysis of serious contenders. Read form RIGHT to LEFT (rightmost = most recent). Who is improving, who is declining, who is consistent? Note any gear changes.",
    "step3_conditions": "How do today's track condition, distance, and barriers suit or hinder each contender? Flag any dry-trackers on wet ground or vice versa.",
    "step4_weight": "Weight analysis — who benefits, who is burdened? Adjust assessment based on race type (handicap vs WFA) and distance.",
    "step5_connections": "Jockey/trainer assessment — any elite or in-form combinations? Jockey changes? Apprentice claims?",
    "step6_intelligence": "X search results: track bias (with source), condition updates, late scratchings. State 'No real-time bias data found' if nothing relevant.",
    "step7_edge": "Final verdict — is there a genuine edge? Does the horse have at least TWO clear positives? Are red flags resolved? If not selecting, explain why."
  },
  "selections": [
    {
      "horseName": "Exact Horse Name",
      "confidence": 72,
      "units": 5,
      "reason": "Concise summary referencing specific data: form figures, stat percentages, weight diff, conditions match.",
      "redFlagsChecked": "List any red flags considered and whether they were overridden (with reason) or confirmed as concerns. State 'None' if no flags apply.",
      "trackBias": "Bias identified from X and how it affects this selection, or 'None identified'."
    }
  ]
}

Rules:
- AT MOST ONE horse per race. Return empty selections array if no genuine edge.
- Only select if confidence is 60+.
- Horse must have at least TWO clear positives from Steps 2-5 to warrant selection.
- If multiple red flags apply to the only viable contender, return empty selections.
- The "reason" MUST reference specific data points from the race data.
- Do not fabricate X/real-time data. If no bias data exists, say so explicitly in step6_intelligence.
- Confidence 80+ requires identifying a likely market overlay, not just the best horse on paper.
- ALWAYS provide ALL 7 analysis steps regardless of whether you make a selection.`;

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
  const runners = race.runners || [];
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
  const avgWinPct = fieldSize > 0 ? runners.reduce((s, r) => s + (r.stats?.winPct || 0), 0) / fieldSize : 0;
  const avgFormScore = fieldSize > 0 ? runners.reduce((s, r) => s + (r.stats?.recentFormScore || 0), 0) / fieldSize : 0;
  // Enrich each runner
  const enrichedRunners = runners.map(r => {
    const formData = parseFormString(r.form);
    // Detect if horse is first-up from a spell (rightmost char before current run is 'x')
    const formChars = (r.form || '').split('');
    const isFirstUp = formChars.length >= 2 && formChars[formChars.length - 1] !== 'x' && formChars.includes('x') && formChars.lastIndexOf('x') === formChars.length - 2;
    // Detect if horse is resuming (last character is first run back, preceded by x)
    const isResuming = formChars.length >= 1 && formChars[formChars.length - 1] === 'x';
    return {
      ...r,
      formParsed: formData.summary,
      weightDiff: parseFloat(((r.weight || 0) - avgWeight).toFixed(1)),
      winPctDiff: parseFloat(((r.stats?.winPct || 0) - avgWinPct).toFixed(1)),
      recentFormDiff: parseFloat(((r.stats?.recentFormScore || 0) - avgFormScore).toFixed(1)),
      isWideBarrier: (r.barrier || 0) > fieldSize * 0.7,
      isFirstUp,
      isResuming,
      hasRecentFail: formChars.slice(-3).includes('f')
    };
  });
  return {
    ...race,
    runners: enrichedRunners,
    fieldSize,
    trackCondition: { rating: conditionRating, number: conditionNumber, isWet },
    distanceMeters,
    distanceCategory,
    fieldAvg: {
      weight: parseFloat(avgWeight.toFixed(1)),
      winPct: parseFloat(avgWinPct.toFixed(1)),
      recentFormScore: parseFloat(avgFormScore.toFixed(1))
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
  serverLog(`Fetching real data from FormFav for Sydney date: ${date} (${tracks.length} tracks)`);
  if (raceFilter) {
    const totalRaces = Object.values(raceFilter).reduce((sum, nums) => sum + nums.length, 0);
    serverLog(`Race filter active: ${totalRaces} future races across ${Object.keys(raceFilter).length} tracks`);
  }
  const allRaces = [];
  let skippedPast = 0;
  for (const track of tracks) {
    // Determine which race numbers to fetch for this track
    const allowedRaces = raceFilter ? (raceFilter[track] || []) : null;
    for (let raceNum = 1; raceNum <= 10; raceNum++) {
      // If we have a filter and this race isn't in it, skip
      if (allowedRaces && !allowedRaces.includes(raceNum)) {
        skippedPast++;
        continue;
      }
      const data = await fetchRace(date, track, raceNum);
      if (data && data.runners && data.runners.length > 0) {
        const race = {
          id: `${track}-R${raceNum}`,
          date: new Date(date),
          track: track.toUpperCase().replace('-', ' '),
          raceNumber: raceNum,
          distance: data.distance || "Unknown",
          condition: data.condition || "Good 4",
          weather: data.weather || "Fine",
          runners: data.runners.map(r => ({
            number: r.number,
            name: r.name,
            jockey: r.jockey || "",
            trainer: r.trainer || "",
            weight: r.weight || 0,
            barrier: r.barrier || 0,
            form: r.form || "",
            stats: r.stats || {}
          }))
        };
        allRaces.push(race);
        serverLog(`Loaded ${track} R${raceNum} (${race.runners.length} runners)`);
      }
    }
  }
  if (skippedPast > 0) {
    serverLog(`Skipped ${skippedPast} past/filtered races`);
  }
  serverLog(`FormFav loaded ${allRaces.length} upcoming races`);
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

      return `#${r.number} ${r.name}
  Jockey: ${r.jockey} | Trainer: ${r.trainer || 'Unknown'}
  Weight: ${r.weight}kg (${r.weightDiff > 0 ? '+' : ''}${r.weightDiff}kg vs field avg)
  Barrier: ${r.barrier}${r.isWideBarrier ? ' (WIDE)' : ''}
  Form: ${r.form || 'No form'} => ${fs.starts} starts, ${fs.wins}W/${fs.places}P, avg finish: ${fs.avgFinishPos}${fs.spells > 0 ? `, ${fs.spells} spells` : ''}${fs.fails > 0 ? `, ${fs.fails} DNF` : ''} | Last 3: ${fs.lastThree}
  Stats: Win ${(r.stats?.winPct || 0).toFixed(0)}% | Track ${(r.stats?.trackWinPct || 0).toFixed(0)}% | Distance ${(r.stats?.distanceWinPct || 0).toFixed(0)}% | Good Track ${(r.stats?.goodTrackWinPct || 0).toFixed(0)}%
  Form Score: ${(r.stats?.recentFormScore || 0).toFixed(1)} (${r.recentFormDiff > 0 ? '+' : ''}${r.recentFormDiff} vs avg)${flagStr}`;
    }).join('\n\n');

    const userMessage = `RACE: ${enriched.track} Race ${enriched.raceNumber}
DISTANCE: ${enriched.distance} (${enriched.distanceCategory})
CONDITION: ${enriched.condition} (${enriched.trackCondition.isWet ? 'WET TRACK' : 'DRY TRACK'})
WEATHER: ${enriched.weather}
FIELD SIZE: ${enriched.fieldSize} runners
FIELD AVERAGES:
- Weight: ${enriched.fieldAvg.weight}kg
- Win%: ${enriched.fieldAvg.winPct}%
- Recent Form Score: ${enriched.fieldAvg.recentFormScore}

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
              step2_form: 'Form Analysis',
              step3_conditions: 'Conditions Match',
              step4_weight: 'Weight & Class',
              step5_connections: 'Connections',
              step6_intelligence: 'Real-Time Intelligence',
              step7_edge: 'Edge Identification'
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
app.all('/scrape-now', async (req, res) => {
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

app.get('/logs', (req, res) => {
  res.json(serverLogs);
});

app.get('/today-races', (req, res) => {
  res.json(latestRaces);
});

app.get('/', (req, res) => {
  res.json({ status: "ok", message: "EquiEdge Scraper running", version: "2.0" });
});

module.exports = app;
