const express = require('express');
const axios = require('axios');
const cheerio = require('cheerio');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(express.json());

let todaysRacesCache = [];

// Realistic mock runners (so AnalysisService can suggest bets)
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

async function scrapeBothDays() {
  const dates = [];
  const now = new Date();
  // Force Australian dates (AEDT) - today and tomorrow
  dates.push(new Date(now.getTime() + 11 * 60 * 60 * 1000).toISOString().split('T')[0]); // today AEDT
  dates.push(new Date(now.getTime() + 35 * 60 * 60 * 1000).toISOString().split('T')[0]); // tomorrow AEDT

  console.log(`🔄 Scraping both ${dates[0]} and ${dates[1]} (taking longer for accuracy)`);

  const allRaces = [];

  for (const dateStr of dates) {
    try {
      const url = `https://www.skyracingworld.com/form-guide/thoroughbred/${dateStr}`;
      const { data } = await axios.get(url, {
        headers: { 'User-Agent': 'Mozilla/5.0 (compatible; EquiEdgeBot/1.0)' }
      });

      const $ = cheerio.load(data);

      const auRegex = /CAULFIELD|RANDWICK|FLEMINGTON|MOONEE VALLEY|ROSEHILL|GOLD COAST|DOOMBEN|ASCOT|BELMONT|EAGLE FARM|WYONG|WARWICK|OAKBANK|CANBERRA|CRANBOURNE|WARRNAMBOOL|PENOLA|STAWELL|SUNSHINE COAST|MUDGEE|MORNINGTON/i;

      $('a').each((_, el) => {
        const href = $(el).attr('href');
        if (!href || !/R\d+/.test(href)) return;

        const raceNumMatch = href.match(/R(\d+)/);
        if (!raceNumMatch) return;
        const raceNumber = parseInt(raceNumMatch[1]);

        const linkText = $(el).text().trim();
        const trackMatch = linkText.match(/([A-Z][A-Z\s|]+?)\s+R\d+/i);
        let track = trackMatch ? trackMatch[1].trim() : "Unknown Track";

        if (!auRegex.test(track)) return;

        const distanceMatch = linkText.match(/(\d+)\s*m/);
        const distance = distanceMatch ? distanceMatch[1] + "m" : "1400m";

        allRaces.push({
          id: `${track}-R${raceNumber}`,
          date: new Date(dateStr),
          track: track,
          raceNumber: raceNumber,
          distance: distance,
          condition: "Good 4",
          weather: "Fine",
          runners: createMockRunners()
        });
      });

      await new Promise(r => setTimeout(r, 1200)); // longer delay between pages

    } catch (e) {
      console.log(`⚠️ Failed to scrape ${dateStr}`);
    }
  }

  // Remove duplicates
  const uniqueRaces = allRaces.filter((race, index, self) =>
    index === self.findIndex(r => r.track === race.track && r.raceNumber === race.raceNumber)
  );

  todaysRacesCache = uniqueRaces;
  console.log(`✅ FINAL RESULT: ${uniqueRaces.length} races loaded with mock runners`);
  return uniqueRaces;
}

// Routes
app.get('/today-races', (req, res) => res.json(todaysRacesCache));

app.get('/scrape-now', async (req, res) => {
  await scrapeBothDays();
  res.json({ 
    status: 'ok', 
    races: todaysRacesCache.length,
    date: new Date().toISOString().split('T')[0]
  });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`🚀 EquiEdge scraper (with runners) running on port ${PORT}`));

module.exports = app;