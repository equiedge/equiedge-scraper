const express = require('express');
const axios = require('axios');
const cheerio = require('cheerio');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(express.json());

let todaysRacesCache = [];

// Realistic mock runners so the app can suggest horses
const createMockRunners = () => {
  const names = ["Thunder Strike", "Speed Demon", "Golden Arrow", "Silver Bullet", "Midnight Express", "Lucky Charm", "Storm Chaser", "Firefly", "Black Caviar II", "Winx Legacy", "Nature Strip Jr"];
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

async function scrapeRaceList() {
  // Force correct Australian date (AEDT = UTC + 11 hours)
  const now = new Date();
  const aedtDate = new Date(now.getTime() + 11 * 60 * 60 * 1000);
  const todayStr = aedtDate.toISOString().split('T')[0];
  
  console.log(`🔄 Scraping race list for Australian date: ${todayStr}`);

  try {
    const url = `https://www.skyracingworld.com/form-guide/thoroughbred/${todayStr}`;
    const { data } = await axios.get(url, {
      headers: { 'User-Agent': 'Mozilla/5.0 (compatible; EquiEdgeBot/1.0)' }
    });

    const $ = cheerio.load(data);
    const allRaces = [];

    const auRegex = /CAULFIELD|RANDWICK|FLEMINGTON|MOONEE VALLEY|ROSEHILL|GOLD COAST|DOOMBEN|ASCOT|BELMONT|EAGLE FARM|WYONG|WARWICK|OAKBANK|CANBERRA|CRANBOURNE|WARRNAMBOOL|PENOLA|STAWELL|SUNSHINE COAST|MUDGEE|MORNINGTON|NOWRA|ALBANY/i;

    $('a').each((_, el) => {
      const href = $(el).attr('href');
      if (!href || !/R\d+/.test(href)) return;

      const raceNumMatch = href.match(/R(\d+)/);
      if (!raceNumMatch) return;
      const raceNumber = parseInt(raceNumMatch[1]);

      const linkText = $(el).text().trim();
      const trackMatch = linkText.match(/([A-Z][A-Z\s|]+?)\s+R\d+/i);
      let track = trackMatch ? trackMatch[1].trim() : "Unknown";

      if (!auRegex.test(track)) return;

      const distanceMatch = linkText.match(/(\d+)\s*m/);
      const distance = distanceMatch ? distanceMatch[1] + "m" : "1400m";

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
    console.log(`✅ SUCCESS — Found ${uniqueRaces.length} races with mock runners (date: ${todayStr})`);
    return uniqueRaces;

  } catch (err) {
    console.error('Scrape failed:', err.message);
    return [];
  }
}

// Routes
app.get('/today-races', (req, res) => res.json(todaysRacesCache));

app.get('/scrape-now', async (req, res) => {
  await scrapeRaceList();
  res.json({ 
    status: 'ok', 
    races: todaysRacesCache.length,
    date: new Date().toISOString().split('T')[0]
  });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`🚀 EquiEdge scraper (working version with mock runners) running`));

module.exports = app;