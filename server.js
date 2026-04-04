const express = require('express');
const axios = require('axios');
const cheerio = require('cheerio');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(express.json());

let todaysRacesCache = [];

// Realistic mock runners (we'll try to parse real ones later)
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

async function scrapeRacenet() {
  console.log(`🔄 Scraping Racenet for today's races`);

  try {
    const url = "https://www.racenet.com.au/form-guide/horse-racing";
    const { data } = await axios.get(url, {
      headers: { 'User-Agent': 'Mozilla/5.0 (compatible; EquiEdgeBot/1.0)' }
    });

    const $ = cheerio.load(data);
    const allRaces = [];

    // Target the actual Racenet race links
    $('a[href*="/form-guide/horse-racing/"]').each((_, el) => {
      const href = $(el).attr('href');
      if (!href) return;

      // Extract race number from URL
      const raceNumMatch = href.match(/R?(\d+)/i);
      if (!raceNumMatch) return;
      const raceNumber = parseInt(raceNumMatch[1]);

      // Extract track name from URL slug (e.g. "ascot-20260404" → "Ascot")
      const slugMatch = href.match(/\/form-guide\/horse-racing\/([a-z]+)-/i);
      let track = slugMatch ? slugMatch[1].charAt(0).toUpperCase() + slugMatch[1].slice(1) : "Unknown";

      const linkText = $(el).text().trim();
      const distanceMatch = linkText.match(/(\d+)\s*m/);
      const distance = distanceMatch ? distanceMatch[1] + "m" : "1400m";

      allRaces.push({
        id: `${track}-R${raceNumber}`,
        date: new Date(),
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
    console.log(`✅ Racenet scraper: Found ${uniqueRaces.length} races`);
    return uniqueRaces;

  } catch (err) {
    console.error('Racenet scrape failed:', err.message);
    return [];
  }
}

// Routes
app.get('/today-races', (req, res) => res.json(todaysRacesCache));

app.get('/scrape-now', async (req, res) => {
  await scrapeRacenet();
  res.json({ 
    status: 'ok', 
    races: todaysRacesCache.length,
    date: new Date().toISOString().split('T')[0],
    source: "Racenet.com.au"
  });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`🚀 EquiEdge Racenet scraper running`));

module.exports = app;