const express = require('express');
const axios = require('axios');
const cheerio = require('cheerio');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(express.json());

let todaysRacesCache = [];

// lbs to kg helper
const lbsToKg = (lbs) => Math.round((parseFloat(lbs) || 57) * 0.453592 * 10) / 10;

async function scrapeAllAustralianRaces() {
  const todayStr = new Date().toISOString().split('T')[0];   // e.g. 2026-04-03
  console.log(`🔄 Starting scrape for ${todayStr}`);

  try {
    const indexUrl = `https://www.skyracingworld.com/form-guide/thoroughbred/${todayStr}`;
    const { data } = await axios.get(indexUrl, {
      headers: { 
        'User-Agent': 'Mozilla/5.0 (compatible; EquiEdgeBot/1.0)' 
      }
    });

    const $ = cheerio.load(data);
    const allRaces = [];

    // Find Australian meetings (h2 headings)
    $('h2').each((_, el) => {
      const heading = $(el).text().trim();
      
      // Only Australian tracks
      if (!/CAULFIELD|RANDWICK|FLEMINGTON|MOONEE VALLEY|ROSEHILL|GOLD COAST|DOOMBEN|ASCOT|BELMONT|EAGLE FARM|WYONG|WARWICK|OAKBANK|CANBERRA|CRANBOURNE|WARRNAMBOOL/i.test(heading)) {
        return;
      }

      const trackName = heading.split('|')[0]?.trim() || heading.split('–')[0]?.trim() || 'Unknown Track';

      // Get condition & weather from following text
      let condition = 'Good 4';
      let weather = 'Fine';
      const nextText = $(el).next().text();
      const condMatch = nextText.match(/GOOD|SOFT|HEAVY \d?/i);
      if (condMatch) condition = condMatch[0].trim();
      const weatherMatch = nextText.match(/Fine|Clouds|Rain|Overcast/i);
      if (weatherMatch) weather = weatherMatch[0];

      // Find race links (they are in <a> tags inside lists)
      $(el).nextAll('ul').first().find('a').each((_, linkEl) => {
        const href = $(linkEl).attr('href');
        if (!href || !/\/R\d+/.test(href)) return;

        const raceNumMatch = href.match(/R(\d+)/);
        if (!raceNumMatch) return;

        const raceNumber = parseInt(raceNumMatch[1]);
        const linkText = $(linkEl).text().trim();

        // Extract distance if possible
        const distanceMatch = linkText.match(/(\d+)\s*m/);
        const distance = distanceMatch ? distanceMatch[1] + "m" : "Unknown";

        allRaces.push({
          id: `${trackName}-R${raceNumber}`,
          date: new Date(todayStr),
          track: trackName,
          raceNumber: raceNumber,
          distance: distance,
          condition: condition,
          weather: weather,
          runners: []   // Runners empty for now (we'll add later)
        });
      });
    });

    todaysRacesCache = allRaces;
    console.log(`✅ Successfully scraped ${allRaces.length} Australian races for ${todayStr}`);
    return allRaces;

  } catch (err) {
    console.error('❌ Scrape failed:', err.message);
    return [];
  }
}

// API Endpoints
app.get('/today-races', (req, res) => {
  res.json(todaysRacesCache);
});

app.get('/scrape-now', async (req, res) => {
  await scrapeAllAustralianRaces();
  res.json({ 
    status: 'ok', 
    races: todaysRacesCache.length,
    date: new Date().toISOString().split('T')[0]
  });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`🚀 EquiEdge Scraper running on port ${PORT}`);
});

module.exports = app;