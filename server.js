// server.js - EquiEdge Scraper (FormFav + Grok AI) - Grok 4.1 Fast + Live Logs
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
// Structured Grok AI Prompt with handicapping methodology
const SYSTEM_PROMPT = `You are an expert Australian horse racing handicapper. Analyze each race using the structured methodology below.
Your goal: identify AT MOST ONE horse per race that has a genuine edge — the data suggests a higher win probability than the field average.
FORM STRING KEY (most recent run is LEFTMOST):
- 1-9: finishing position (1=won, 2=second, etc.)
- 0: finished 10th or worse
- x: fell, unseated, or brought down
- f: failed to finish (pulled up)
- d: disqualified
- -: scratched/did not start
Example: "12x31" = last 5 starts: 1st, 2nd, fell, 3rd, 1st (reading left to right, most recent first)
ANALYSIS STEPS (work through each before making a selection):
STEP 1 — FIELD ASSESSMENT:
How many runners? Small fields (<8) are more predictable. Look at the field averages provided to gauge overall quality.
STEP 2 — FORM ANALYSIS:
For each serious contender, read form left-to-right (most recent first). Look for:
- Improving form (finishing positions getting better over recent starts)
- Consistency (mostly top-3 finishes)
- Recent wins at similar class/distance
- Red flags: falls (x), failures to finish (f), deteriorating form, big gaps suggesting injury/spell
STEP 3 — CONDITIONS MATCH:
- Track condition: Compare goodTrackWinPct vs overall winPct. If today is WET and a horse has high goodTrackWinPct but low overall winPct, it's a dry-tracker — negative. High trackWinPct = proven at this course.
- Distance: distanceWinPct shows proven ability at this trip. First time at a distance is a risk factor.
- Barrier: Wide barriers (marked WIDE in the data) hurt in sprint races (<1400m). Inside barriers can be traps in staying races at some tracks.
STEP 4 — WEIGHT AND CLASS:
- Horses carrying significantly more than field average (>2kg above, shown as weightDiff) are disadvantaged.
- The topweight in a handicap is rated highest but carries the most — needs strong form to overcome.
- Dropping in weight from recent runs is a positive sign.
STEP 5 — CONNECTIONS:
Consider jockey and trainer. Elite jockey/trainer combinations on a horse with good form is a strong positive. Well-known Australian Group 1 jockeys and leading trainers are significant.
STEP 6 — REAL-TIME INTELLIGENCE:
Use any knowledge you have about today's racing: track biases (inside/outside rail advantages), late scratchings, weather changes, jockey switches, stable confidence, and professional tipster consensus. Factor these in where relevant.
STEP 7 — EDGE IDENTIFICATION:
Only select a horse if you can identify a SPECIFIC, data-backed edge:
- Form/stats clearly stand out vs the field averages
- Conditions strongly suit this horse over rivals
- Multiple factors align (form + conditions + connections + data)
RED FLAGS (avoid selecting if any apply):
- Form contains "x" or "f" in the last 3 starts
- No wins or places at today's distance (distanceWinPct near 0%)
- Carrying 3+kg above field average weight
- Wide barrier in sprint races (<1400m)
- Very low trackWinPct or distanceWinPct (<10%)
CONFIDENCE CALIBRATION:
- 60-69: Marginal edge — one clear advantage over the field
- 70-79: Solid edge — multiple factors align (form + conditions + connections)
- 80-89: Strong edge — clearly the best horse on paper with ideal conditions
- 90+: Dominant — exceptional form in a weak field with perfect conditions (extremely rare)
UNIT SIZING:
- 1-3 units: Confidence 60-69
- 4-6 units: Confidence 70-79
- 7-8 units: Confidence 80-89
- 9-10 units: Confidence 90+
Return ONLY valid JSON in this format:
{
  "analysis": "Your step-by-step reasoning through the analysis steps. Which horses you considered seriously, why you eliminated them, what patterns you observed in the field.",
  "selections": [
    {
      "horseName": "Exact Horse Name",
      "confidence": 72,
      "units": 5,
      "reason": "Concise summary referencing specific data: form figures, stat percentages, weight diff, conditions match."
    }
  ]
}
Rules:
- AT MOST ONE horse per race. Return empty selections array if no genuine edge.
- Only select if confidence is 60+.
- The "reason" MUST reference specific data points from the race data.
- ALWAYS provide "analysis" regardless of whether you make a selection.`;
// Parse form string into structured results (most recent run is leftmost)
function parseFormString(formStr) {
  if (!formStr) return { parsed: [], summary: { starts: 0, wins: 0, places: 0, falls: 0, winRate: 0, placeRate: 0, avgFinishPos: 0 } };
  const parsed = [];
  for (const ch of formStr) {
    if (ch >= '1' && ch <= '9') {
      const pos = parseInt(ch);
      parsed.push({ pos, isWin: pos === 1, isPlace: pos <= 3, isFall: false });
    } else if (ch === '0') {
      parsed.push({ pos: 10, isWin: false, isPlace: false, isFall: false });
    } else if (ch === 'x') {
      parsed.push({ pos: null, isWin: false, isPlace: false, isFall: true });
    } else if (ch === 'f') {
      parsed.push({ pos: null, isWin: false, isPlace: false, isFall: true });
    } else if (ch === 'd') {
      parsed.push({ pos: null, isWin: false, isPlace: false, isFall: false });
    }
  }
  const finishers = parsed.filter(p => p.pos !== null);
  const wins = parsed.filter(p => p.isWin).length;
  const places = parsed.filter(p => p.isPlace).length;
  const falls = parsed.filter(p => p.isFall).length;
  const starts = parsed.length;
  return {
    parsed,
    summary: {
      starts,
      wins,
      places,
      falls,
      winRate: starts > 0 ? Math.round((wins / starts) * 100) : 0,
      placeRate: starts > 0 ? Math.round((places / starts) * 100) : 0,
      avgFinishPos: finishers.length > 0 ? parseFloat((finishers.reduce((s, p) => s + p.pos, 0) / finishers.length).toFixed(1)) : 0
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
    return {
      ...r,
      formParsed: formData.summary,
      weightDiff: parseFloat(((r.weight || 0) - avgWeight).toFixed(1)),
      winPctDiff: parseFloat(((r.stats?.winPct || 0) - avgWinPct).toFixed(1)),
      recentFormDiff: parseFloat(((r.stats?.recentFormScore || 0) - avgFormScore).toFixed(1)),
      isWideBarrier: (r.barrier || 0) > fieldSize * 0.7
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
  serverLog(`🔄 Fetching real data from FormFav for Sydney date: ${date} (${tracks.length} tracks)`);
  if (raceFilter) {
    const totalRaces = Object.values(raceFilter).reduce((sum, nums) => sum + nums.length, 0);
    serverLog(`🎯 Race filter active: ${totalRaces} future races across ${Object.keys(raceFilter).length} tracks`);
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
        serverLog(`✅ Loaded ${track} R${raceNum} (${race.runners.length} runners)`);
      }
    }
  }
  if (skippedPast > 0) {
    serverLog(`⏭️ Skipped ${skippedPast} past/filtered races`);
  }
  serverLog(`✅ FormFav loaded ${allRaces.length} upcoming races`);
  return allRaces;
}
async function analyzeRaceWithGrok(race) {
  if (!XAI_API_KEY) {
    serverLog('❌ No XAI_API_KEY configured');
    return { selections: [], analysis: "" };
  }
  try {
    serverLog(`🚀 Analyzing ${race.track} R${race.raceNumber} with Grok AI...`);
    const enriched = enrichRaceData(race);
    const runnersText = enriched.runners.map(r => {
      const fs = r.formParsed;
      return `#${r.number} ${r.name}
  Jockey: ${r.jockey} | Trainer: ${r.trainer || 'Unknown'}
  Weight: ${r.weight}kg (${r.weightDiff > 0 ? '+' : ''}${r.weightDiff}kg vs field avg)
  Barrier: ${r.barrier}${r.isWideBarrier ? ' (WIDE)' : ''}
  Form: ${r.form || 'No form'} => ${fs.starts} starts, ${fs.wins}W/${fs.places}P, avg finish: ${fs.avgFinishPos}${fs.falls > 0 ? `, ${fs.falls} falls` : ''}
  Stats: Win ${(r.stats?.winPct || 0).toFixed(0)}% | Track ${(r.stats?.trackWinPct || 0).toFixed(0)}% | Distance ${(r.stats?.distanceWinPct || 0).toFixed(0)}% | Good Track ${(r.stats?.goodTrackWinPct || 0).toFixed(0)}%
  Form Score: ${(r.stats?.recentFormScore || 0).toFixed(1)} (${r.recentFormDiff > 0 ? '+' : ''}${r.recentFormDiff} vs avg)`;
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
Analyze this race step by step using the methodology and return at most one selection if there is a genuine edge.`;
    const aiResponse = await axios.post('https://api.x.ai/v1/chat/completions', {
      model: "grok-4-1-fast-reasoning",
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: userMessage }
      ],
      temperature: 0.3,
      max_tokens: 2000,
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
    const aiResult = JSON.parse(aiText);
    const picks = aiResult.selections || [];
    if (picks.length > 0) {
      serverLog(`✅ Grok AI pick for ${race.track} R${race.raceNumber}: ${picks[0].horseName} (${picks[0].confidence}%)`);
    } else {
      serverLog(`⏭️ Grok AI: no confident pick for ${race.track} R${race.raceNumber}`);
    }
    return {
      selections: picks,
      analysis: aiResult.analysis || ""
    };
  } catch (err) {
    serverLog(`❌ Grok AI failed for ${race.track} R${race.raceNumber}: ${err.message}`);
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
      serverLog('❌ No racetracks have been selected to analyse');
      return res.status(400).json({ error: "No racetracks have been selected to analyse" });
    }
    const tracks = tracksParam.split(',').map(t => t.trim()).filter(Boolean);
    const raceFilter = parseRaceFilter(req.query.raceFilter);
    serverLog(`🔄 Scrape-now called (ai=${req.query.ai || 'false'}, tracks: ${tracks.join(', ')}${raceFilter ? ', filtered' : ''})`);
    const races = await scrapeFormFav(tracks, raceFilter);
    if (req.query.ai === 'true' && XAI_API_KEY) {
      serverLog(`🚀 Running Grok AI analysis on ${races.length} races...`);
      for (let race of races) {
        const result = await analyzeRaceWithGrok(race);
        race.suggestions = result.selections;
        race.aiAnalysis = result.analysis;
      }
      const picksCount = races.filter(r => r.suggestions.length > 0).length;
      serverLog(`✅ Grok AI complete — ${picksCount} picks from ${races.length} races`);
    } else {
      races.forEach(r => { r.suggestions = []; r.aiAnalysis = ""; });
    }
    latestRaces = races;
    res.json({
      status: "ok",
      races: races.length,
      date: new Date().toISOString().split('T')[0],
      source: req.query.ai === 'true' ? "Grok AI + FormFav" : "FormFav"
    });
  } catch (err) {
    serverLog(`❌ Scrape error: ${err.message}`);
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
  res.json({ status: "ok", message: "EquiEdge Scraper running" });
});
module.exports = app;
