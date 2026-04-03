const express = require('express');
const axios = require('axios');
const cheerio = require('cheerio');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(express.json());

let todaysRacesCache = [];

// Create realistic mock runners so AnalysisService can actually suggest horses
const createMockRunners = () => {
  const names = ["Thunder Strike", "Speed Demon", "Golden Arrow", "Silver Bullet", "Midnight Express", "Lucky Charm", "Storm Chaser", "Firefly", "Black Caviar II", "Winx Legacy"];
  return Array.from({ length: 12 }, (_, i) => ({
    number: i + 1,
    name: names[i % names.length],
    jockey: ["J. Kah", "M. Zahra", "C. Williams", "D. Oliver", "B. Melham"][i % 5],
    trainer: ["C. Waller", "G. Waterhouse", "J. Cummings", "T. Busuttin"][i % 4],
    weight: 54 + Math.random() * 9,
    barrier: Math.floor(Math.random() * 14) + 1,
    form: ["1x221", "312x4", "112x3", "21x14", "3x211"][i % 5],
    stats: {
      winPct: 22 + Math.random() * 28,
      trackWinPct: 28 + Math.random() * 22,
      distanceWinPct: 25 + Math.random() * 20,
      goodTrackWinPct: 30 + Math.random() * 25,
      recentFormScore: 0.55 + Math.random() * 0.35
    }
  }));
};

async function scrapeAustralianRaces() {
  const todayStr = new Date().toISOString().split('T')[0];
  console.log(`🔄 Scraping Sky Racing World for ${todayStr}`);

  try {
    const url = `https://www.skyracingworld.com/form-guide/thoroughbred/${todayStr}`;
    const { data } = await axios.get(url, {
      headers: { 'User-Agent': 'Mozilla/5.0 (compatible; EquiEdgeBot/1.0)' }
    });

    const $ = cheerio.load(data);
    const allRaces = [];

    const auRegex = /CAULFIELD|RANDWICK|FLEMINGTON|MOONEE VALLEY|ROSEHILL|GOLD COAST|DOOMBEN|ASCOT|BELMONT|EAGLE FARM|WYONG|WARWICK|OAKBANK|CANBERRA|CRANBOURNE|WARRNAMBOOL/i;

    // Find every race link on the page (they point to tomorrow in many cases)
    $('a').each((_, el) => {
      const href = $(el).attr('href');
      if (!href || !/\/australia\/.*\/R\d+/.test(href)) return;

      const raceNumMatch = href.match(/R(\d+)/);
      if (!raceNumMatch) return;
      const raceNumber = parseInt(raceNumMatch[1]);

      // Get track name from nearest h2
      const trackEl = $(el).closest('div, section').prevAll('h2').first();
      let track = trackEl.text().trim().split('|')[0] || "Unknown";
      if (!auRegex.test(track)) return;

      const linkText = $(el).text().trim();
      const distanceMatch = linkText.match(/(\d+)\s*m/);
      const distance = distanceMatch ? distanceMatch[1] + "m" : "1400m";

      // Add race with mock runners
      allRaces.push({
        id: `${track}-R${raceNumber}`,
        date: new Date(todayStr),
        track: track,
        raceNumber: raceNumber,
        distance: distance,
        condition: "Good 4",
        weather: "Fine",
        runners: createMockRunners()
      });
    });

    // Remove duplicates
    const uniqueRaces = allRaces.filter((race, index, self) =>
      index === self.findIndex(r => r.track === race.track && r.raceNumber === race.raceNumber)
    );

    todaysRacesCache = uniqueRaces;
    console.log(`✅ SUCCESS — Found ${uniqueRaces.length} Australian races with runners`);
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