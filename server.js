const express = require('express');
const axios = require('axios');
const cheerio = require('cheerio');
const cors = require('cors');
const cron = require('cron');

const app = express();
app.use(cors());
app.use(express.json());

let todaysRacesCache = []; // { track, raceNumber, date, distance, condition, weather, runners: [...] }

// Helper: convert lbs to kg
const lbsToKg = (lbs) => Math.round(parseFloat(lbs) * 0.453592 * 10) / 10;

// Daily cron – 6:00 AM AEDT (Melbourne time)
new cron.CronJob('0 20 * * *', async () => { // 06:00 AEDT = 20:00 UTC previous day
  console.log('🔄 Scraping Sky Racing World for today...');
  const dateStr = new Date().toISOString().split('T')[0]; // YYYY-MM-DD
  await scrapeAllAustralianRaces(dateStr);
}, null, true, 'Australia/Melbourne');

// Main scrape function
async function scrapeAllAustralianRaces(dateStr) {
  try {
    const indexUrl = `https://www.skyracingworld.com/form-guide/thoroughbred/${dateStr}`;
    const { data: indexHtml } = await axios.get(indexUrl, {
      headers: { 'User-Agent': 'Mozilla/5.0 (compatible; EquiEdgeBot/1.0)' }
    });

    const $ = cheerio.load(indexHtml);
    const allRaces = [];

    // Parse every Australian meeting (skip SAF, TUR, UAE etc.)
    $('h2, h3, ##').each((_, el) => {  // headings contain track names
      const headerText = $(el).text().trim();
      if (!/CAULFIELD|RANDWICK|OAKBANK|EAGLE FARM|WYONG|GOLD COAST|ASCOT|WARWICK|DOOMBEN|FLEMINGTON|MOONEE VALLEY|ROSEHILL/.test(headerText)) return;

      const trackMatch = headerText.match(/([A-Z\s]+)\s*\|\s*([A-Z]+)/);
      if (!trackMatch) return;
      const track = trackMatch[1].trim();

      // Extract condition & weather from following text
      let condition = 'Good 4';
      let weather = 'Fine';
      const nextText = $(el).next().text();
      const condMatch = nextText.match(/Track:\s*([A-Z0-9\s]+?)(?:,|\s)/i);
      if (condMatch) condition = condMatch[1].trim();
      const weatherMatch = nextText.match(/Clouds|Rain|Fine/i);
      if (weatherMatch) weather = weatherMatch[0];

      // Find race links in the list
      $(el).nextAll('ul, ol').first().find('a').each(async (_, linkEl) => {
        const href = $(linkEl).attr('href');
        if (!href || !/\/R\d+$/.test(href)) return;

        const raceUrl = `https://www.skyracingworld.com${href}`;
        const raceNumMatch = href.match(/\/R(\d+)$/);
        const raceNumber = parseInt(raceNumMatch[1]);

        // Fetch individual race page
        const { data: raceHtml } = await axios.get(raceUrl, { headers: { 'User-Agent': 'Mozilla/5.0 (compatible; EquiEdgeBot/1.0)' } });
        const $$ = cheerio.load(raceHtml);

        // Race metadata
        const distanceMatch = $$('h1').text().match(/(\d+\s*[½¼⅓]?\s*f)/i) || $$('body').text().match(/(\d+\s*[½¼⅓]?\s*f)/i);
        const distance = distanceMatch ? distanceMatch[1] : 'Unknown';

        // Runners
        const runners = [];
        // Pattern: [1. HORSE NAME] ... Wgt: XXlbs BP: XX [JOCKEY] [TRAINER]
        const runnerTextBlocks = $$('body').text().split(/\[\d+\./);
        for (let i = 1; i < runnerTextBlocks.length; i++) {
          const block = runnerTextBlocks[i];
          if (block.includes('Scratched')) continue;

          const numberMatch = block.match(/^(\d+)/);
          const nameMatch = block.match(/([A-Z\s()]+?)(?:\s+Wgt:|\s*BP:)/);
          const wgtMatch = block.match(/Wgt:\s*(\d+)/);
          const bpMatch = block.match(/BP:\s*(\d+)/);
          const jockeyMatch = block.match(/\]\s*([A-Z\s]+?)\s*(?:\(a\d+kg\))?/);
          const trainerMatch = block.match(/\[([A-Z\s]+?)\]/g); // last one is trainer
          const formMatch = block.match(/(\d+x?\d*){4,}/); // recent form string

          if (numberMatch && nameMatch) {
            runners.push({
              number: parseInt(numberMatch[1]),
              name: nameMatch[1].trim(),
              jockey: jockeyMatch ? jockeyMatch[1].trim() : 'Unknown',
              trainer: trainerMatch && trainerMatch.length > 0 ? trainerMatch[trainerMatch.length-1].replace(/[\[\]]/g, '').trim() : 'Unknown',
              weight: wgtMatch ? lbsToKg(wgtMatch[1]) : 57.0, // default kg
              barrier: bpMatch ? parseInt(bpMatch[1]) : 0,
              form: formMatch ? formMatch[0] : '-----',
              stats: { winPct: 25, trackWinPct: 30, distanceWinPct: 28, goodTrackWinPct: 32, recentFormScore: 0.65 } // placeholder – enhance with form table parsing if needed
            });
          }
        }

        allRaces.push({
          id: `${track}-R${raceNumber}`,
          date: new Date(dateStr),
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
    console.log(`✅ Scraped ${allRaces.length} Australian races for ${dateStr}`);
  } catch (err) {
    console.error('Scrape failed:', err.message);
  }
}

// API endpoint for iOS app
app.get('/today-races', (req, res) => {
  res.json(todaysRacesCache);
});

app.get('/scrape-now', async (req, res) => {
  const dateStr = new Date().toISOString().split('T')[0];
  await scrapeAllAustralianRaces(dateStr);
  res.json({ status: 'ok', races: todaysRacesCache.length });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`🚀 EquiEdge Sky Scraper running on ${PORT}`));
