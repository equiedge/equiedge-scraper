const express = require('express');
const fetch = require('node-fetch');

const app = express();
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
- reason: detailed expert explanation (form quality, class of previous races, track/condition match, barrier, weight, trainer/jockey, distance, etc.)

Return ONLY this JSON:
{
  "selections": [
    {
      "horseName": "Exact horse name",
      "confidence": 47,
      "units": 5,
      "reason": "Detailed expert explanation"
    }
  ]
}`;

// FormFav - exact from your docs
async function scrapeFormFav() {
  const today = new Date().toISOString().split('T')[0];
  console.log('📅 Date:', today);

  try {
    console.log('📡 Calling FormFav /v1/form/meetings with X-API-Key');
    const res = await fetch(`https://api.formfav.com/v1/form/meetings?date=${today}&race_code=gallops`, {
      headers: {
        'X-API-Key': FORMAV_API_KEY,
        'Accept': 'application/json'
      }
    });

    console.log('Meetings status:', res.status);

    if (!res.ok) {
      const text = await res.text();
      console.error('Raw error:', text);
      return [];
    }

    const data = await res.json();
    const meetings = data.meetings || [];

    console.log('Found', meetings.length, 'meetings');

    const races = [];

    for (const meeting of meetings) {
      if (meeting.abandoned) continue;

      const slug = meeting.slug;
      const formRes = await fetch(`https://api.formfav.com/v1/form?track=${slug}&date=${today}`, {
        headers: {
          'X-API-Key': FORMAV_API_KEY,
          'Accept': 'application/json'
        }
      });

      if (formRes.ok) {
        const formData = await formRes.json();
        if (formData.races) races.push(...formData.races);
      }
    }

    console.log('✅ Final races returned:', races.length);
    return races;
  } catch (err) {
    console.error('FormFav error:', err.message);
    return [];
  }
}

// Endpoints
app.all('/scrape-now', async (req, res) => {
  try {
    const races = await scrapeFormFav();

    if (req.query.ai === 'true' && XAI_API_KEY) {
      console.log('🚀 Running Grok AI...');
      for (let race of races) {
        race.suggestions = await analyzeRaceWithGrok(race);
      }
    } else {
      races.forEach(r => r.suggestions = []);
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

async function analyzeRaceWithGrok(race) {
  // ... (same as before)
  // (I omitted the full function for brevity - keep the same one you had)
  return [];
}

app.get('/today-races', (req, res) => res.json(latestRaces));
app.get('/', (req, res) => res.json({ status: "ok" }));

module.exports = app;