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
  const dateStr = new Date().toISOString().split('T')[0];
  console.log(`🔄 Scraping Sky Racing World for ${dateStr}`);

  try {
    const indexUrl = `https://www.skyracingworld.com/form-guide/thoroughbred/${dateStr}`;
    const { data } = await axios.get(indexUrl, {
      headers: { 'User-Agent': 'Mozilla/5.0 (compatible; EquiEdgeBot/1.0)' }
    });

    const $ = cheerio.load(data);
    const allRaces = [];

    // Find all Australian meeting headers
    $('h2, h3').each((i, el) => {
      const text = $(el).text().trim();
      if (!/CAULFIELD|RANDWICK|FLEMINGTON|MOONEE VALLEY|ROSEHILL|GOLD COAST|DOOMBEN|ASCOT|BELMONT|EAGLE FARM|WYONG|WARWICK|OAKBANK|CANBERRA|CRANBOURNE/i.test(text)) {
        return;
      }

      const track = text.split('|')[0]?.trim() || text.split('–')[0]?.trim() || 'Unknown';

      let condition = 'Good 4';
      let weather = 'Fine';
      const infoText = $(el).next().text();
      if (/Good|Soft|Heavy/i.test(infoText)) condition = infoText.match(/Good|Soft|Heavy \d?/i)[0];
      if (/Fine|Cloud|Rain|Overcast/i.test(infoText)) weather = infoText.match(/Fine|Cloud|Rain|Overcast/i)[0];

      // Find race links
      $(el).nextAll('ul, ol').first().find('a').each((_, linkEl) => {
        const href = $(linkEl).attr('href');
        if (!href || !/\/R\d+/.test(href)) return;

        const raceNumMatch = href.match(/R(\d+)/);
        if (!raceNumMatch) return;
        const raceNumber = parseInt(raceNumMatch[1]);

        const raceLinkText = $(linkEl).text();
        const distanceMatch = raceLinkText.match(/(\d+)\s*m/);
        const distance = distanceMatch ? distanceMatch[1] + "m" : "Unknown";

        allRaces.push({
          id: `${track}-R${raceNumber}`,
          date: new Date(dateStr),
          track: track,
          raceNumber: raceNumber,
          distance: distance,
          condition: condition,
          weather: weather,
          runners: []   // Runners will be empty for now — we can add later
        });
      });
    });

    todaysRacesCache = allRaces;
    console.log(`✅ Scraped ${allRaces.length} races for ${dateStr}`);
    return allRaces;

  } catch (err) {
    console.error('Scrape failed:', err.message);
    return [];
  }
}

// Routes
app.get('/today-races', (req, res) => res.json(todaysRacesCache));

app.get('/scrape-now', async (req, res) => {
  await scrapeAllAustralianRaces();
  res.json({ status: 'ok', races: todaysRacesCache.length });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`🚀 EquiEdge scraper running on port ${PORT}`));

module.exports = app;