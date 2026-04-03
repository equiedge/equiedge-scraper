const express = require('express');
const axios = require('axios');
const cheerio = require('cheerio');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(express.json());

let todaysRacesCache = [];

const lbsToKg = (lbs) => Math.round((parseFloat(lbs) || 57) * 0.453592 * 10) / 10;

async function scrapeAllAustralianRaces() {
  const todayStr = new Date().toISOString().split('T')[0];
  console.log(`🔄 Scraping Sky Racing World for ${todayStr}`);

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

      const track = heading.split('|')[0]?.trim() || heading;

      let condition = 'Good 4';
      let weather = 'Fine';
      const info = $(el).next().text() || $(el).nextAll('p').first().text();
      if (/GOOD|SOFT|HEAVY/i.test(info)) condition = info.match(/GOOD|SOFT|HEAVY \d?/i)?.[0] || condition;
      if (/Fine|Cloud|Rain/i.test(info)) weather = info.match(/Fine|Cloud|Rain/i)?.[0] || weather;

      // Find race links
      $(el).nextAll('ul').first().find('a').each(async (_, linkEl) => {
        const href = $(linkEl).attr('href');
        if (!href || !/\/R\d+/.test(href)) return;

        const raceNumMatch = href.match(/R(\d+)/);
        if (!raceNumMatch) return;
        const raceNumber = parseInt(raceNumMatch[1]);

        const linkText = $(linkEl).text().trim();
        const distanceMatch = linkText.match(/(\d+)\s*m/);
        const distance = distanceMatch ? distanceMatch[1] + "m" : "Unknown";

        // Fetch individual race page
        try {
          await new Promise(r => setTimeout(r, 600)); // polite delay
          const raceUrl = `https://www.skyracingworld.com${href}`;
          const { data: raceData } = await axios.get(raceUrl, {
            headers: { 'User-Agent': 'Mozilla/5.0 (compatible; EquiEdgeBot/1.0)' }
          });

          const $$ = cheerio.load(raceData);
          const runners = [];

          // Parse runners - this targets common patterns on race pages
          $$('tr, .runner, li').each((_, row) => {
            const rowText = $$(row).text().trim();
            if (!rowText || rowText.length < 10) return;

            const numberMatch = rowText.match(/^(\d+)/);
            const nameMatch = rowText.match(/([A-Z][A-Za-z\s']{3,30})/);
            const barrierMatch = rowText.match(/Barrier\s*(\d+)/i) || rowText.match(/\b(\d{1,2})\b/);
            const weightMatch = rowText.match(/(\d+\.?\d*)\s*kg/i);
            const jockeyMatch = rowText.match(/J:\s*([A-Z][A-Za-z\s]+)/i);
            const trainerMatch = rowText.match(/T:\s*([A-Z][A-Za-z\s]+)/i);
            const formMatch = rowText.match(/(\d+x?\d*){3,}/);

            if (numberMatch && nameMatch) {
              runners.push({
                number: parseInt(numberMatch[1]),
                name: nameMatch[1].trim(),
                jockey: jockeyMatch ? jockeyMatch[1].trim() : "Unknown",
                trainer: trainerMatch ? trainerMatch[1].trim() : "Unknown",
                weight: weightMatch ? parseFloat(weightMatch[1]) : 57.0,
                barrier: barrierMatch ? parseInt(barrierMatch[1]) : 0,
                form: formMatch ? formMatch[0] : "-----",
                stats: {
                  winPct: 25,
                  trackWinPct: 30,
                  distanceWinPct: 28,
                  goodTrackWinPct: 32,
                  recentFormScore: 0.6
                }
              });
            }
          });

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

          console.log(`✅ Parsed ${runners.length} runners for ${track} R${raceNumber}`);

        } catch (e) {
          console.log(`⚠️ Could not parse runners for R${raceNumber}`);
        }
      });
    });

    todaysRacesCache = allRaces;
    console.log(`✅ Total races scraped: ${allRaces.length}`);
    return allRaces;

  } catch (err) {
    console.error('Scrape error:', err.message);
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
app.listen(PORT, () => console.log(`🚀 EquiEdge scraper running on port ${PORT}`));

module.exports = app;