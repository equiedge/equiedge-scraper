const express = require('express');
const axios = require('axios');
const cheerio = require('cheerio');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(express.json());

let todaysRacesCache = [];

// Realistic mock runners (we can improve this later to parse real ones from Racenet)
const createMockRunners = () => {
  const names = ["Thunder Strike", "Speed Demon", "Golden Arrow", "Silver Bullet", "Midnight Express", "Lucky Charm", "Storm Chaser", "Firefly", "Black Caviar II", "Winx Legacy", "Nature Strip Jr", "Zac Purton Special"];
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
  console.log(`🔄 Scraping Racenet for today's Australian races`);

  try {
    const url = "https://www.racenet.com.au/form-guide/horse-racing";
    const { data } = await axios.get(url, {
      headers: { 'User-Agent': 'Mozilla/5.0 (compatible; EquiEdgeBot/1.0)' }
    });

    const $ = cheerio.load(data);
    const allRaces = [];

    // Racenet lists meetings on the main form guide page
    $('a[href*="/form-guide/horse-racing/"]').each((_, el) => {
      const href = $(el).attr('href');
      if (!href || !/\/form-guide\/horse-racing\/[a-z]+-\d+/.test(href)) return;

      const linkText = $(el).text().trim();
      const trackMatch = linkText.match(/([A-Z][A-Za-z\s]+)/);
      if (!trackMatch) return;

      const track = trackMatch[1].trim();
      const raceNumMatch = href.match(/R?(\d+)/i);
      const raceNumber = raceNumMatch ? parseInt(raceNumMatch[1]) : 1;

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
        runners: createMockRunners()   // Real runners can be added later
      });
    });

    // Remove duplicates
    const uniqueRaces = allRaces.filter((race, index, self) =>
      index === self.findIndex(r => r.track === race.track && r.raceNumber === race.raceNumber)
    );

    todaysRacesCache = uniqueRaces;
    console.log(`✅ Racenet scraper success: ${uniqueRaces.length} races loaded`);
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
app.listen(PORT, () => console.log(`🚀 EquiEdge Racenet scraper running on port ${PORT}`));

module.exports = app;