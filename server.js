const express = require('express');
const axios = require('axios');
const cheerio = require('cheerio');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(express.json());

let todaysRacesCache = [];

// Helper: lbs to kg
const lbsToKg = (lbs) => Math.round(parseFloat(lbs || 57) * 0.453592 * 10) / 10;

// Main scrape function with delays
async function scrapeAllAustralianRaces(dateStr) {
  try {
    console.log(`🔄 Starting scrape for ${dateStr}`);
    
    const indexUrl = `https://www.skyracingworld.com/form-guide/thoroughbred/${dateStr}`;
    const { data: indexHtml } = await axios.get(indexUrl, {
      headers: { 'User-Agent': 'Mozilla/5.0 (compatible; EquiEdgeBot/1.0)' }
    });

    const $ = cheerio.load(indexHtml);
    const allRaces = [];

    // Look for Australian tracks
    const australianTracks = /CAULFIELD|RANDWICK|FLEMINGTON|MOONEE VALLEY|ROSEHILL|GOLD COAST|DOOMBEN|ASCOT|BELMONT|EAGLE FARM|WYONG|WARWICK|OAKBANK/i;

    $('h2, h3').each((_, el) => {
      const headerText = $(el).text().trim();
      if (!australianTracks.test(headerText)) return;

      const track = headerText.split('|')[0]?.trim() || headerText.split('–')[0]?.trim() || 'Unknown Track';

      let condition = 'Good 4';
      let weather = 'Fine';
      const nextText = $(el).next().text();
      if (nextText.match(/Good|Soft|Heavy/i)) condition = nextText.match(/Good|Soft|Heavy \d?/i)[0];
      if (nextText.match(/Fine|Cloud|Rain|Overcast/i)) weather = nextText.match(/Fine|Cloud|Rain|Overcast/i)[0];

      // Find race links
      $(el).nextAll('ul, ol, table').first().find('a[href*="/R"]').each(async (_, link) => {
        const href = $(link).attr('href');
        if (!href) return;

        const raceNumMatch = href.match(/R(\d+)/);
        if (!raceNumMatch) return;
        const raceNumber = parseInt(raceNumMatch[1]);

        // Add small delay between race fetches
        await new Promise(resolve => setTimeout(resolve, 800));

        try {
          const raceUrl = `https://www.skyracingworld.com${href}`;
          const { data: raceHtml } = await axios.get(raceUrl, {
            headers: { 'User-Agent': 'Mozilla/5.0 (compatible; EquiEdgeBot/1.0)' }
          });
          const $$ = cheerio.load(raceHtml);

          // Basic parsing (you can improve this later)
          const runners = []; // ← Your current runner parsing logic goes here
          // ... (keep your existing runner parsing code)

          allRaces.push({
            id: `${track}-R${raceNumber}`,
            date: new Date(dateStr),
            track: track,
            raceNumber: raceNumber,
            distance: "1400m", // improve parsing later
            condition: condition,
            weather: weather,
            runners: runners.length > 0 ? runners : [] // fallback
          });
        } catch (e) {
          console.log(`⚠️ Failed to fetch race ${raceNumber}`);
        }
      });
    });

    todaysRacesCache = allRaces;
    console.log(`✅ Scraped ${allRaces.length} races`);
    return allRaces;
  } catch (err) {
    console.error('Scrape error:', err.message);
    return [];
  }
}

// API Routes
app.get('/today-races', (req, res) => {
  res.json(todaysRacesCache);
});

app.get('/scrape-now', async (req, res) => {
  const dateStr = new Date().toISOString().split('T')[0];
  await scrapeAllAustralianRaces(dateStr);
  res.json({ status: 'ok', races: todaysRacesCache.length });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`🚀 Server running on port ${PORT}`);
});

module.exports = app;   // Important for Vercel