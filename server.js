const express = require('express');
const fetch = require('node-fetch');

const app = express();
app.use(express.json());

// Keys come from Vercel Environment Variables
const FORMAV_API_KEY = process.env.FORMAV_API_KEY;
const XAI_API_KEY = process.env.XAI_API_KEY;

let latestRaces = [];

// Major Australian tracks (your last working version)
const MAJOR_TRACKS = [
  "caulfield", "randwick", "flemington", "moonee-valley", "rosehill",
  "gold-coast", "doomben", "ascot", "eagle-farm", "hamilton", "grafton",
  "warrnambool"
];
// Strict Grok AI Prompt (max 1 horse per race, only if real edge)
const SYSTEM_PROMPT = `You are an elite Australian horse racing analyst with 20+ years experience.
Be extremely strict and conservative.

Rules:
- Return AT MOST ONE horse per race.
- Only return a horse if you are GENUINELY confident it has a clear betting edge.
- If no horse meets your standards, return an empty "selections" array.

For the selected horse include:
- confidence: integer 0-100
- units: integer 1-10 (bet size based on confidence)
- reason: detailed expert explanation (form quality, class of previous races, sectional times, track/condition match, barrier, weight, trainer/jockey, distance, etc.)
Return ONLY this JSON:
{
  "selections": [
    {
      "horseName": "Exact horse name",
      "confidence": 47,
      "units": 5,
      "reason": "Strong recent win in higher class on similar ground. Excellent barrier today, trainer in form, perfectly suited to trip."
    }
  ]
}`;

// Working FormFav scrape
async function fetchRace(date, track, raceNumber) {
  try {
    const url = `https://api.formfav.com/v1/form?date=${date}&track=${track}&race=${raceNumber}&race_code=gallops&country=au`;
    const response = await fetch(url, {
      headers: { 'X-API-Key': FORMAV_API_KEY }
    });
    if (!response.ok) return null;
    return await response.json();
  } catch (err) {
    return null;
  }
}

async function scrapeFormFav() {
  const date = new Date().toISOString().split('T')[0];
  console.log(`🔄 Fetching real data from FormFav for ${date}`);

  const allRaces = [];

  for (const track of MAJOR_TRACKS) {
    for (let raceNum = 1; raceNum <= 10; raceNum++) {
      const data = await fetchRace(date, track, raceNum);
      if (data && data.runners && data.runners.length > 0) {
        const race = {
          id: `${track}-R${raceNum}`,
          date: new Date(date),
          track: track.toUpperCase().replace('-', ' '),
          raceNumber: raceNum,
          distance: data.distance || `${1400 + raceNum * 100}m`,
          condition: data.condition || "Good 4",
          weather: data.weather || "Fine",
          runners: data.runners.map(r => ({
            number: r.number || 0,
            name: r.name || "Unknown",
            jockey: r.jockey || "Unknown",
            trainer: r.trainer || "Unknown",
            weight: parseFloat(r.weight) || 57.0,
            barrier: parseInt(r.barrier) || 0,
            form: r.form || "-----",
            stats: {
              winPct: r.winPct || 25,
              trackWinPct: r.trackWinPct || 30,
              distanceWinPct: r.distanceWinPct || 28,
              goodTrackWinPct: r.goodTrackWinPct || 32,
              recentFormScore: 0.65
            }
          }))
        };
        allRaces.push(race);
        console.log(`✅ Loaded ${track} R${raceNum} (${race.runners.length} runners)`);
      }
    }
  }

  console.log(`✅ FormFav loaded ${allRaces.length} real races`);
  return allRaces;
}

// FIXED Grok AI with robust parsing
async function analyzeRaceWithGrok(race) {
  if (!XAI_API_KEY) return [];
  try {
    const aiResponse = await fetch('https://api.x.ai/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${XAI_API_KEY}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        model: "grok-beta",
        messages: [
          { role: "system", content: SYSTEM_PROMPT },
          { role: "user", content: `Analyze this race and return at most one elite selection only if there is a genuine edge:\n${JSON.stringify(race, null, 2)}` }
        ],
        temperature: 0.3,
        max_tokens: 800
      })
    });

    const data = await aiResponse.json();

    // Robust check
    if (!data || !data.choices || !data.choices[0] || !data.choices[0].message || !data.choices[0].message.content) {
      console.error('Grok AI returned invalid response structure');
      return [];
    }

    let aiText = data.choices[0].message.content.trim();

    // Clean up if Grok adds extra text
    if (aiText.includes('```json')) {
      aiText = aiText.split('```json')[1].split('```')[0].trim();
    } else if (aiText.includes('```')) {
      aiText = aiText.split('```')[1].trim();
    }

    const aiResult = JSON.parse(aiText);
    return aiResult.selections || [];
  } catch (err) {
    console.error('Grok AI failed:', err.message);
    return [];
  }
}

// Endpoints
app.all('/scrape-now', async (req, res) => {
  try {
    const races = await scrapeFormFav();

    if (req.query.ai === 'true' && XAI_API_KEY) {
      console.log('🚀 Running Grok AI (max 1 horse per race)...');
      for (let race of races) {
        race.suggestions = await analyzeRaceWithGrok(race);
      }
    } else {
      races.forEach(r => { r.suggestions = []; });
    }

    latestRaces = races;

    res.json({
      status: "ok",
      races: races.length,
      source: req.query.ai === 'true' ? "Grok AI + FormFav" : "FormFav"
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ status: "error", message: err.message });
  }
});

app.get('/today-races', (req, res) => res.json(latestRaces));
app.get('/', (req, res) => res.json({ status: "ok" }));

module.exports = app;