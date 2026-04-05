const express = require('express');
const fetch = require('node-fetch');

const app = express();
app.use(express.json());

const FORMAV_API_KEY = process.env.FORMAV_API_KEY || 'fk_1f2a77e0d885d4b83c6fe972d7a6a3dd2180ad887622b88d6c0fa0bca09dfc85';
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
- reason: detailed expert explanation (form quality, class of previous races, track/condition match, barrier, weight, trainer/jockey, distance, etc.)

Return ONLY this JSON:
{
  "selections": [
    {
      "horseName": "Exact horse name",
      "confidence": 47,
      "units": 5,
      "reason": "Strong recent win in higher class. Excellent barrier today, trainer in form."
    }
  ]
}`;

// FormFav scrape
async function scrapeFormFav() {
  try {
    const res = await fetch('https://api.formfav.com/races/today', {
      headers: { 'Authorization': `Bearer ${FORMAV_API_KEY}` }
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    return Array.isArray(data) ? data : (data.races || []);
  } catch (e) {
    console.error('FormFav error:', e.message);
    return [];
  }
}

// Grok AI
async function analyzeRaceWithGrok(race) {
  if (!XAI_API_KEY) return [];
  try {
    const res = await fetch('https://api.x.ai/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${XAI_API_KEY}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        model: "grok-beta",
        messages: [
          { role: "system", content: SYSTEM_PROMPT },
          { role: "user", content: `Analyze this race:\n${JSON.stringify(race, null, 2)}` }
        ],
        temperature: 0.3,
        max_tokens: 700
      })
    });

    const data = await res.json();
    const text = data.choices[0].message.content.trim();
    const result = JSON.parse(text);
    return result.selections || [];
  } catch (e) {
    console.error('Grok AI error:', e.message);
    return [];
  }
}

// Routes - accept both GET and POST for easy testing
app.all('/scrape-now', async (req, res) => {
  try {
    console.log('🔄 Scrape-now called (method:', req.method, 'ai=', req.query.ai, ')');

    let races = await scrapeFormFav();

    if (req.query.ai === 'true' && XAI_API_KEY) {
      console.log('🚀 Running Grok AI expert analysis (max 1 horse per race)...');
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
    console.error('Scrape error:', err);
    res.status(500).json({ status: "error", message: err.message });
  }
});

app.get('/today-races', (req, res) => {
  res.json(latestRaces);
});

app.get('/', (req, res) => {
  res.json({ status: "ok", message: "EquiEdge scraper running" });
});

// Required for Vercel
module.exports = app;