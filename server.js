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

// Strict Grok AI Prompt (max 1 horse per race, always return analysis)
const SYSTEM_PROMPT = `You are an elite Australian horse racing analyst with 20+ years experience.
Be extremely strict and conservative.

Rules:
- Return AT MOST ONE horse per race.
- Only return a horse if you are GENUINELY confident it will WIN and has a clear betting edge.
- If no horse meets your standards, return an empty "selections" array.
- ALWAYS provide an "analysis" field with your full reasoning about the race, regardless of whether you make a selection.

For the selected horse include:
- confidence: integer 0-100
- units: integer 1-10 (bet size based on confidence)
- reason: detailed expert explanation (form quality, class of previous races, sectional times, track/condition match, barrier, weight, trainer/jockey, distance etc.)

Return ONLY valid JSON in this format:
{
  "analysis": "Your full thoughts on the race - key observations about the field, track conditions, why you did or did not find value, any horses that came close but didn't meet your threshold.",
  "selections": [
    {
      "horseName": "Exact Horse Name",
      "confidence": 68,
      "units": 4,
      "reason": "Strong recent win in a higher class race on similar track conditions. Excellent barrier draw today, trainer in peak form, perfectly suited to the distance."
    }
  ]
}`;

// Major Australian tracks
const MAJOR_TRACKS = [
  "caulfield", "randwick", "flemington", "moonee-valley", "rosehill",
  "gold-coast", "doomben", "ascot", "eagle-farm"
];

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

async function scrapeFormFav(tracks) {
  const date = new Intl.DateTimeFormat('en-CA', { timeZone: 'Australia/Sydney' })
    .format(new Date())
    .split('T')[0];

  serverLog(`🔄 Fetching real data from FormFav for Sydney date: ${date} (${tracks.length} tracks)`);

  const allRaces = [];

  for (const track of tracks) {
    for (let raceNum = 1; raceNum <= 10; raceNum++) {
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

  serverLog(`✅ FormFav loaded ${allRaces.length} real races`);
  return allRaces;
}

async function analyzeRaceWithGrok(race) {
  if (!XAI_API_KEY) {
    serverLog('❌ No XAI_API_KEY configured');
    return { selections: [], analysis: "" };
  }

  try {
    serverLog(`🚀 Analyzing ${race.track} R${race.raceNumber} with Grok AI...`);

    const aiResponse = await axios.post('https://api.x.ai/v1/chat/completions', {
      model: "grok-4-1-fast-reasoning",
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: `Analyze this race and return at most one elite selection only if there is a genuine edge:\n${JSON.stringify(race, null, 2)}` }
      ],
      temperature: 0.3,
      max_tokens: 1000
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

// TAB Odds Fetching
async function fetchTABMeetings(date) {
  // Try multiple TAB API endpoints
  const urls = [
    `https://api.beta.tab.com.au/v1/tab-info-service/racing/dates/${date}/meetings?jurisdiction=NSW`,
    `https://api.beta.tab.com.au/v1/tab-info-service/racing/dates/${date}/meetings`,
    `https://api.beta.tab.com.au/v1/historical-results-service/NSW/racing/${date}`,
  ];

  for (const url of urls) {
    try {
      serverLog(`💰 Trying TAB: ${url}`);
      const { data } = await axios.get(url, {
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Referer': 'https://www.tab.com.au/',
          'Origin': 'https://www.tab.com.au'
        },
        timeout: 15000
      });

      // Debug: log what we actually got back
      const topKeys = typeof data === 'object' ? Object.keys(data).join(', ') : typeof data;
      serverLog(`💰 TAB response keys: ${topKeys}`);

      // Try different response shapes
      const meetings = data.meetings || data.races || data.results || [];
      if (Array.isArray(meetings) && meetings.length > 0) {
        serverLog(`💰 TAB returned ${meetings.length} meetings from ${url}`);
        return meetings;
      }
      // If data itself is an array of meetings
      if (Array.isArray(data) && data.length > 0) {
        serverLog(`💰 TAB returned ${data.length} meetings (array) from ${url}`);
        return data;
      }
    } catch (err) {
      serverLog(`⚠️ TAB endpoint failed: ${err.message}`);
    }
  }

  serverLog('⚠️ All TAB endpoints failed — skipping odds lookup');
  return [];
}

async function fetchTABRaceOdds(raceUrl) {
  try {
    const { data } = await axios.get(raceUrl, {
      headers: { 'Accept': 'application/json' },
      timeout: 10000
    });
    return data;
  } catch (err) {
    return null;
  }
}

function slugToName(slug) {
  return slug.replace(/-/g, ' ').toLowerCase();
}

async function lookupFixedWinOdds(tabMeetings, trackSlug, raceNumber, horseName) {
  const trackName = slugToName(trackSlug);

  // Find matching meeting by venue name
  const meeting = tabMeetings.find(m => {
    const venue = (m.meetingName || m.venueMnemonic || '').toLowerCase();
    return venue.includes(trackName) || trackName.includes(venue);
  });

  if (!meeting) return null;

  // Find the race by number
  const races = meeting.races || [];
  const race = races.find(r => r.raceNumber === raceNumber);
  if (!race) return null;

  // If race has a link for full details (with odds), fetch it
  let runners = race.runners || race.entries || [];
  if (runners.length === 0 && race._links && race._links.self) {
    const raceDetail = await fetchTABRaceOdds(race._links.self);
    if (raceDetail) {
      runners = raceDetail.runners || raceDetail.entries || [];
    }
  }

  // Find the runner by horse name (case-insensitive)
  const target = horseName.toLowerCase().trim();
  const runner = runners.find(r => {
    const name = (r.runnerName || r.name || '').toLowerCase().trim();
    return name === target;
  });

  if (!runner) return null;

  // Extract fixed win odds
  const fixedOdds = runner.fixedOdds || runner.fixedWin || {};
  const odds = fixedOdds.returnWin || fixedOdds.win || fixedOdds.winOdds || null;

  if (odds && odds > 0) {
    return odds;
  }
  return null;
}

async function attachTABOdds(races, date) {
  const tabMeetings = await fetchTABMeetings(date);
  if (tabMeetings.length === 0) {
    serverLog('⚠️ No TAB meetings available — skipping odds lookup');
    return;
  }

  let oddsFound = 0;
  for (const race of races) {
    if (!race.suggestions || race.suggestions.length === 0) continue;

    // Extract the original track slug from the race id (e.g. "caulfield-R1" → "caulfield")
    const trackSlug = race.id.replace(/-R\d+$/, '');

    for (const suggestion of race.suggestions) {
      const odds = await lookupFixedWinOdds(tabMeetings, trackSlug, race.raceNumber, suggestion.horseName);
      suggestion.fixedWinOdds = odds;
      if (odds) {
        serverLog(`💰 TAB odds for ${suggestion.horseName} (${race.track} R${race.raceNumber}): $${odds.toFixed(2)}`);
        oddsFound++;
      }
    }
  }
  serverLog(`💰 TAB odds found for ${oddsFound} selections`);
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
    serverLog(`🔄 Scrape-now called (ai=${req.query.ai || 'false'}, tracks: ${tracks.join(', ')})`);

    const races = await scrapeFormFav(tracks);

    if (req.query.ai === 'true' && XAI_API_KEY) {
      serverLog(`🚀 Running Grok AI analysis on ${races.length} races...`);
      for (let race of races) {
        const result = await analyzeRaceWithGrok(race);
        race.suggestions = result.selections;
        race.aiAnalysis = result.analysis;
      }
      const picksCount = races.filter(r => r.suggestions.length > 0).length;
      serverLog(`✅ Grok AI complete — ${picksCount} picks from ${races.length} races`);

      // Fetch TAB fixed win odds for all selections
      const date = new Intl.DateTimeFormat('en-CA', { timeZone: 'Australia/Sydney' })
        .format(new Date()).split('T')[0];
      await attachTABOdds(races, date);
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