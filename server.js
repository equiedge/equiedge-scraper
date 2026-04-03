const express = require('express');
const axios = require('axios');
const cheerio = require('cheerio');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(express.json());

let todaysRacesCache = [];

// Strong mock runners so the app can suggest bets
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

async function loadMockRaces() {
  const todayStr = new Date().toISOString().split('T')[0];
  console.log(`🔄 Loading mock Australian races for ${todayStr}`);

  const tracks = ["Caulfield", "Randwick", "Flemington", "Moonee Valley", "Rosehill", "Gold Coast", "Doomben", "Ascot", "Eagle Farm", "Wyong"];

  const races = [];

  tracks.forEach((track, raceNum) => {
    races.push({
      id: `${track}-R${raceNum + 1}`,
      date: new Date(todayStr),
      track: track,
      raceNumber: raceNum + 1,
      distance: "1200m",
      condition: "Good 4",
      weather: "Fine",
      runners: createMockRunners()
    });
  });

  todaysRacesCache = races;
  console.log(`✅ Loaded ${races.length} mock races with runners`);
  return races;
}

// Routes
app.get('/today-races', (req, res) => res.json(todaysRacesCache));

app.get('/scrape-now', async (req, res) => {
  await loadMockRaces();
  res.json({ 
    status: 'ok', 
    races: todaysRacesCache.length,
    date: new Date().toISOString().split('T')[0],
    note: "Using stable mock data (Sky scraper was unreliable)"
  });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`🚀 EquiEdge backend running with stable mock data on port ${PORT}`));

module.exports = app;