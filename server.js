const express = require('express');
const fetch = require('node-fetch');

const app = express();
app.use(express.json());

// Hardcoded keys as requested
const FORMAV_API_KEY = 'fk_ebfe108fd32e41f946ad9c583b1cfbc9a0e94829bf7644b7c4a9c5bfd65090bb';
const XAI_API_KEY = 'xai-DwCbbUpLBogXH0IiiBkAncPUepeL0R6gWhyYsM6zTyEiG0VlF1O8iKibayjcam7QSVJNrCNaYRU89BJL';

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

// Two-step FormFav API (exactly as per your docs)
async function scrapeFormFav() {
  const today = new Date().toISOString().split('T')[0];
  console.log('📅 Date sent to FormFav:', today);

  try {
    // Step 1: Get meetings
    console.log('📡 Step 1: Calling /v1/form/meetings');
    const meetingsRes = await fetch(`https://api.formfav.com/v1/form/meetings?date=${today}&race_code=gallops`, {
      headers: {
        'X-API-Key': FORMAV_API_KEY,
        'Accept': 'application/json'
      }
    });

    console.log('Meetings status:', meetingsRes.status);

    if (!meetingsRes.ok) {
      const text = await meetingsRes.text();
      console.error('Raw error:', text);
      return [];
    }

    const meetingsData = await meetingsRes.json();
    const meetings = meetingsData.meetings || [];

    console.log('✅ Found', meetings.length, 'meetings');

    // Step 2: Get races for each meeting
    const races = [];

    for (const meeting of meetings) {
      if (meeting.abandoned === true) continue;

      const slug = meeting.slug;
      console.log(`📡 Step 2: Calling /v1/form for track: ${slug}`);

      const formRes = await fetch(`https://api.formfav.com/v1/form?track=${slug}&date=${today}`, {
        headers: {
          'X-API-Key': FORMAV_API_KEY,
          'Accept': 'application/json'
        }
      });

      if (formRes.ok) {
        const formData = await formRes.json();
        if (formData.races && Array.isArray(formData.races)) {
          races.push(...formData.races);
        }
      }
    }

    console.log('✅ Final FormFav returned', races.length, 'races');
    return races;
  } catch (err) {
    console.error('❌ FormFav scrape crashed:', err.message);
    return [];
  }
}

// Grok AI
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