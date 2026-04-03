const express = require('express');
const axios = require('axios');
const cheerio = require('cheerio');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(express.json());

let todaysRacesCache = [];

// lbs to kg
const lbsToKg = (lbs) => Math.round((parseFloat(lbs) || 57) * 0.453592 * 10) / 10;

async function scrapeAllAustralianRaces() {
  const todayStr = new Date().toISOString().split('T')[0];
  console.log(`🔄 Starting full scrape (with runners) for ${todayStr}`);

  try {
    const indexUrl = `https://www.skyracingworld.com/form-guide/thoroughbred/${todayStr}`;
    const { data } = await axios.get(indexUrl, {
      headers: { 'User-Agent': 'Mozilla/5.0 (compatible; EquiEdgeBot/1.0)' }
    });

    const $ = cheerio.load(data);
    const allRaces = [];

    const auTracks = /CAULFIELD|RANDWICK|FLEMINGTON|MOONEE VALLEY|ROSEHILL|GOLD COAST|DOOMBEN|ASCOT|BELMONT|EAGLE FARM|WYONG|WARWICK|OAKBANK|CANBERRA|CRANBOURNE|WARRNAMBOOL/i;

    $('h2').each((_, el) => {
      const heading = $(el).text().trim();
      if (!auTracks.test(heading)) return;

      const track = heading.split('|')[0]?.trim() || heading.split('–')[0]?.trim() || heading;

      let condition = 'Good 4';
      let weather = 'Fine';
      const infoText = $(el).next().text() || $(el).nextAll('p').first().text() || '';
      if (/GOOD|SOFT|HEAVY/i.test(infoText)) condition = infoText.match(/GOOD|SOFT|HEAVY \d?/i)?.[0] || condition;
      if (/Fine|Cloud|Rain|Overcast/i.test(infoText)) weather = infoText.match(/Fine|Cloud|Rain|Overcast/i)?.[0] || weather;

      // Find race links
      $('a[href*="/R"]').each(async (_, linkEl) => {
        const href = $(linkEl).attr('href');
        if (!href || !/\/R\d+/.test(href)) return;

        const raceNumMatch = href.match(/R(\d+)/);
        if (!raceNumMatch) return;
        const raceNumber = parseInt(raceNumMatch[1]);

        const linkText = $(linkEl).text().trim();
        const distanceMatch = linkText.match(/(\d+)\s*m/);
        const distance = distanceMatch ? distanceMatch[1] + "m" : "Unknown";

        // Fetch individual race page for runners
        let runners = [];
        try {
          await new Promise(r => setTimeout(r, 700)); // polite delay
          const raceUrl = `https://www.skyracingworld.com${href}`;
          const { data: raceData } = await axios.get(raceUrl, {
            headers: { 'User-Agent': 'Mozilla/5.0 (compatible; EquiEdgeBot/1.0)' }
          });

          const $$ = cheerio.load(raceData);

          // Improved runner parsing - look for rows or blocks containing horse data
          $$('tr, div.runner, li, p').each((_, row) => {
            const text = $$(row).text().trim();
            if (text.length < 15) return;

            const numberMatch = text.match(/^(\d{1,2})/);
            const nameMatch = text.match(/([A-Z][A-Za-z\s']{4,35})/);
            if (!numberMatch || !nameMatch) return;

            const barrierMatch = text.match(/Barrier\s*(\d+)/i) || text.match(/\b(\d{1,2})\b/);
            const weightMatch = text.match(/(\d+\.?\d*)\s*kg/i);
            const jockeyMatch = text.match(/J:\s*([A-Z][A-Za-z\s]+)/i);
            const formMatch = text.match(/(\d+x?\d*){3,}/);

            runners.push({
              number: parseInt(numberMatch[1]),
              name: nameMatch[1].trim(),
              jockey: jockeyMatch ? jockeyMatch[1].trim() : "Unknown",
              trainer: "Unknown", // trainer parsing is harder on this site
              weight: weightMatch ? parseFloat(weightMatch[1]) : 57.0,
              barrier: barrierMatch ? parseInt(barrierMatch[1]) : 0,
              form: formMatch ? formMatch[0] : "-----",
              stats: {
                winPct: 25,
                trackWinPct: 30,
                distanceWinPct: 28,
                goodTrackWinPct: 32,
                recentFormScore: 0.65
              }
            });
          });
        } catch (e) {
          console.log(`⚠️ Runner parsing failed for ${track} R${raceNumber}`);
        }

        allRaces.push({
          id: `${track}-R${raceNumber}`,
          date: new Date(todayStr),
          track: track,
          raceNumber: raceNumber,
          distance: distance,
          condition: condition,
          weather: weather,
          runners: runners
        });
      });
    });

    todaysRacesCache = allRaces;
    console.log(`✅ Final scrape: ${allRaces.length} races with runners`);
    return allRaces;

  } catch (err) {
    console.error('Full scrape error:', err.message);
    return [];
  }
}

// Routes
app.get('/today-races', (req, res) => res.json(todaysRacesCache));

app.get('/scrape-now', async (req, res) => {
  await scrapeAllAustralianRaces();
  res.json({ 
    status: 'ok', 
    races: todaysRacesCache.length,
    date: new Date().toISOString().split('T')[0]
  });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`🚀 EquiEdge scraper with runners running on port ${PORT}`));

module.exports = app;