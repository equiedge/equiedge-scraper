const express = require('express');
const axios = require('axios');
const cheerio = require('cheerio');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(express.json());

let todaysRacesCache = [];

// Mock runners so the app can analyse and suggest bets
const createMockRunners = (count = 12) => {
  const names = ["Thunder Strike", "Speed Demon", "Golden Arrow", "Silver Bullet", "Midnight Express", "Lucky Charm", "Storm Chaser", "Firefly", "Black Caviar II", "Winx Legacy", "Nature Strip Jr", "Zac Purton Special"];
  return Array.from({ length: count }, (_, i) => ({
    number: i + 1,
    name: names[i % names.length] + (i > 5 ? " " + (i + 1) : ""),
    jockey: ["J. Kah", "M. Zahra", "C. Williams", "D. Oliver", "B. Melham"][i % 5],
    trainer: ["C. Waller", "G. Waterhouse", "J. Cummings", "T. Busuttin"][i % 4],
    weight: 55 + Math.random() * 8,
    barrier: Math.floor(Math.random() * 14) + 1,
    form: ["1x221", "312x4", "112x3", "21x14", "3x211"][i % 5],
    stats: {
      winPct: 22 + Math.random() * 25,
      trackWinPct: 28 + Math.random() * 20,
      distanceWinPct: 25 + Math.random() * 20,
      goodTrackWinPct: 30 + Math.random() * 20,
      recentFormScore: 0.55 + Math.random() * 0.35
    }
  }));
};

async function scrapeAustralianRaces() {
  const todayStr = new Date().toISOString().split('T')[0];
  console.log(`🔄 Scraping race list for ${todayStr}`);

  try {
    const url = `https://www.skyracingworld.com/form-guide/thoroughbred/${todayStr}`;
    const { data } = await axios.get(url, {
      headers: { 'User-Agent': 'Mozilla/5.0 (compatible; EquiEdgeBot/1.0)' }
    });

    const $ = cheerio.load(data);
    const allRaces = [];

    const auRegex = /CAULFIELD|RANDWICK|FLEMINGTON|MOONEE VALLEY|ROSEHILL|GOLD COAST|DOOMBEN|ASCOT|BELMONT|EAGLE FARM|WYONG|WARWICK|OAKBANK|CANBERRA|CRANBOURNE|WARRNAMBOOL/i;

    // Find every race link on the page
    $('a').each((_, el) => {
      const href = $(el).attr('href');
      if (!href || !/\/R\d+/.test(href)) return;

      const raceNumMatch = href.match(/R(\d+)/);
      if (!raceNumMatch) return;
      const raceNumber = parseInt(raceNumMatch[1]);

      const linkText = $(el).text().trim();
      const trackMatch = linkText.match(/([A-Z\s]+?)\s+R\d+/i) || $(el).closest('h2, h3').text().match(/([A-Z\s|]+)/);
      const track = trackMatch ? trackMatch[1].trim() : "Unknown";

      if (!auRegex.test(track)) return;

      const distanceMatch = linkText.match(/(\d+)\s*m/);
      const distance = distanceMatch ? distanceMatch[1] + "m" : "1400m";

      // Add race with realistic mock runners
      allRaces.push({
        id: `${track}-R${raceNumber}`,
        date: new Date(todayStr),
        track: track,
        raceNumber: raceNumber,
        distance: distance,
        condition: "Good 4",
        weather: "Fine",
        runners: createMockRunners(12)
      });
    });

    // Remove duplicates
    const uniqueRaces = allRaces.filter((race, index, self) =>
      index === self.findIndex(r => r.track === race.track && r.raceNumber === race.raceNumber)
    );

    todaysRacesCache = uniqueRaces;
    console.log(`✅ SUCCESS: Found ${uniqueRaces.length} real Australian races with mock runners`);
    return uniqueRaces;

  } catch (err) {
    console.error('Scrape failed:', err.message);
    return [];
  }
}

// Routes
app.get('/today-races', (req, res) => res.json(todaysRacesCache));

app.get('/scrape-now', async (req, res) => {
  await scrapeAustralianRaces();
  res.json({ 
    status: 'ok', 
    races: todaysRacesCache.length,
    date: new Date().toISOString().split('T')[0]
  });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`🚀 EquiEdge scraper running on port ${PORT}`));

module.exports = app;