// server.js - EquiEdge Scraper (FormFav + Grok AI)
const express = require('express');
const axios = require('axios');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(express.json());

const FORMAV_API_KEY = process.env.FORMAV_API_KEY;
const XAI_API_KEY = process.env.XAI_API_KEY;

let latestRaces = [];


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
Return ONLY valid JSON in this format:
{
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
  "gold-coast", "doomben", "ascot", "eagle-farm", "wyong", "belmont",
  "canberra", "cranbourne", "warrnambool", "grafton", "hamilton"
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

async function scrapeFormFav() {
  const date = new Intl.DateTimeFormat('en-CA', { timeZone: 'Australia/Sydney' })
    .format(new Date())
    .split('T')[0];   // YYYY-MM-DD in Sydney time

  console.log(`🔄 Fetching real data from FormFav for Sydney date: ${date}`);

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
        console.log(`✅ Loaded ${track} R${raceNum} (${race.runners.length} runners)`);
      }
    }
  }

  console.log(`✅ FormFav loaded ${allRaces.length} real races`);
  return allRaces;
}

async function analyzeRaceWithGrok(race) {
  if (!XAI_API_KEY) {
    console.error('❌ No XAI_API_KEY configured');
    return [];
  }

  try {
    console.log(`🚀 Analyzing ${race.track} R${race.raceNumber} with Grok AI...`);

    const aiResponse = await axios.post('https://api.x.ai/v1/chat/completions', {
      model: "grok-beta",
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: `Analyze this race and return at most one elite selection only if there is a genuine edge:\n${JSON.stringify(race, null, 2)}` }
      ],
      temperature: 0.3,
      max_tokens: 800
    }, {
      headers: {
        'Authorization': `Bearer ${XAI_API_KEY}`,
        'Content-Type': 'application/json'
      }
    });

    console.log(`Grok API status for ${race.track} R${race.raceNumber}: ${aiResponse.status}`);

    let aiText = aiResponse.data.choices[0].message.content.trim();

    // Aggressive cleaning for common LLM formatting
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
    console.log(`✅ Grok AI success for ${race.track} R${race.raceNumber}`);
    return aiResult.selections || [];
  } catch (err) {
    console.error(`❌ Grok AI failed for ${race.track} R${race.raceNumber}:`, err.message);
    if (err.response) {
      console.error('Grok error response:', err.response.data);
    }
    return [];
  }
}

// Endpoints
app.all('/scrape-now', async (req, res) => {
  try {
    console.log(`🔄 Scrape-now called (ai=${req.query.ai})`);

    let races = await scrapeFormFav();

    // Run Grok AI only if requested and key exists
    if (req.query.ai === 'true' && XAI_API_KEY) {
      console.log(`🚀 Running Grok AI (max 1 horse per race)...`);
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
      date: new Date().toISOString().split('T')[0],
      source: req.query.ai === 'true' ? "Grok AI + FormFav" : "FormFav"
    });
  } catch (err) {
    console.error('❌ Scrape error:', err.message);
    res.status(500).json({ status: "error", message: err.message });
  }
});

app.get('/today-races', (req, res) => {
  res.json(latestRaces);
});

app.get('/', (req, res) => {
  res.json({ status: "ok", message: "EquiEdge Scraper is running" });
});

module.exports = app;