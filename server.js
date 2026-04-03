const express = require('express');
const axios = require('axios');
const cheerio = require('cheerio');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(express.json());

let todaysRacesCache = [];

// Simple lbs to kg
const lbsToKg = (lbs) => Math.round((parseFloat(lbs) || 57) * 0.453592 * 10) / 10;

async function scrapeAllAustralianRaces() {
  const todayStr = new Date().toISOString().split('T')[0];
  console.log(`🔄 Scraping for ${todayStr}`);

  try {
    const indexUrl = `https://www.skyracingworld.com/form-guide/thoroughbred/${todayStr}`;
    const { data } = await axios.get(indexUrl, {
      headers: { 'User-Agent': 'Mozilla/5.0 (compatible; EquiEdgeBot/1.0)' }
    });

    const $ = cheerio.load(data);
    const allRaces = [];

    // Look for h2 headings that contain Australian tracks
    const australianRegex = /CAULFIELD|RANDWICK|FLEMINGTON|MOONEE VALLEY|ROSEHILL|GOLD COAST|DOOMBEN|ASCOT|BELMONT|EAGLE FARM|WYONG|WARWICK|OAKBANK|CANBERRA|CRANBOURNE|WARRNAMBOOL/i;

    $('h2').each((_, el) => {
      const heading = $(el).text().trim();
      if (!australianRegex.test(heading)) return;

      const track = heading.split('|')[0]?.trim() || heading.split('–')[0]?.trim() || heading;

      // Get condition and weather
      let condition = 'Good 4';
      let weather = 'Fine';
      const infoText = $(el).nextAll('p').first().text() || $(el).next().text();
      if (/GOOD|SOFT|HEAVY/i.test(infoText)) condition = infoText.match(/GOOD|SOFT|HEAVY \d?/i)?.[0] || condition;
      if (/Fine|Cloud|Rain|Overcast/i.test(infoText)) weather = infoText.match(/Fine|Cloud|Rain|Overcast/i)?.[0] || weather;

      // Find race links (they are in <a> tags)
      $(el).nextAll('ul').first().find('a').each((_, linkEl) => {
        const href = $(linkEl).attr('href');
        if (!href || !/\/R\d+/.test(href)) return;

        const raceNumMatch = href.match(/R(\d+)/);
        if (!raceNumMatch) return;

        const raceNumber = parseInt(raceNumMatch[1]);
        const linkText = $(linkEl).text().trim();

        const distanceMatch = linkText.match(/(\d+)\s*m/);
        const distance = distanceMatch ? distanceMatch[1] + "m" : "Unknown";

        allRaces.push({
          id: `${track}-R${raceNumber}`,
          date: new Date(todayStr),
          track: track,
          raceNumber: raceNumber,
          distance: distance,
          condition: condition,
          weather: weather,
          runners: []   // Empty for now
        });
      });
    });

    todaysRacesCache = allRaces;
    console.log(`✅ Scraped ${allRaces.length} races on ${todayStr}`);
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
app.listen(PORT, () => console.log(`🚀 Server running on port ${PORT}`));

module.exports = app;