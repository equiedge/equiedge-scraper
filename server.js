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
      "reason": "Strong recent win in higher class on similar ground. Excellent barrier today, trainer in form, perfectly suited to trip."
    }
  ]
}`;

// ==================== PURE FORMFAV SCRAPE (last working state) ====================
async function scrapeFormFav() {
  try {
    console.log('📡 [FormFav] Calling /races/today (no date parameter)...');

    const response = await fetch('https://api.formfav.com/races/today', {
      headers: {
        'Authorization': `Bearer ${FORMAV_API_KEY}`,
        'Accept': 'application/json'
      }
    });

    console.log('FormFav HTTP status:', response.status);

    if (!response.ok) {
      console.error('❌ FormFav HTTP error:', response.status);
      return [];
    }

    const data = await response.json();
    const races = Array.isArray(data) ? data : (data.races || []);
    
    console.log('✅ FormFav successfully returned', races.length, 'races');
    return races;
  } catch (err) {
    console.error('❌ FormFav scrape crashed:', err.message);
    return [];
  }
}

// Grok AI (only on manual refresh)
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
    const aiText = data.choices[0].message.content.trim();
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
    console.log('🔄 Scrape-now called (ai=' + (req.query.ai || 'false') + ')');

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

app.get('/today-races', (req, res) => {
  res.json(latestRaces);
});

app.get('/', (req, res) => {
  res.json({ status: "ok", message: "EquiEdge scraper running" });
});

module.exports = app;