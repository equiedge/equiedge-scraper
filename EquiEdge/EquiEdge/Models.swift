import SwiftUI
import SwiftData

@Model
final class BetRecord {
    var id: UUID
    var date: Date
    var raceInfo: String
    var horseName: String
    var units: Int
    var amount: Double
    var confidence: Int?
    var reason: String?
    var result: String?
    var profit: Double
    
    init(raceInfo: String, horseName: String, units: Int, amount: Double, confidence: Int? = nil, reason: String? = nil, result: String? = nil) {
        self.id = UUID()
        self.date = Date()
        self.raceInfo = raceInfo
        self.horseName = horseName
        self.units = units
        self.amount = amount
        self.confidence = confidence
        self.reason = reason
        self.result = result
        self.profit = 0.0
    }
}

@Model
final class Race: Identifiable, Hashable, Codable {
    @Attribute(.unique) var id: String
    var date: Date
    var track: String
    var raceNumber: Int
    var distance: String
    var condition: String
    var weather: String
    var runners: [Horse] = []
    var suggestions: [BetSuggestion] = []
    
    enum CodingKeys: String, CodingKey {
        case id, date, track, raceNumber, distance, condition, weather, runners
    }
    
    init(id: String, date: Date, track: String, raceNumber: Int, distance: String, condition: String, weather: String) {
        self.id = id
        self.date = date
        self.track = track
        self.raceNumber = raceNumber
        self.distance = distance
        self.condition = condition
        self.weather = weather
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.date = try container.decode(Date.self, forKey: .date)
        self.track = try container.decode(String.self, forKey: .track)
        self.raceNumber = try container.decode(Int.self, forKey: .raceNumber)
        self.distance = try container.decode(String.self, forKey: .distance)
        self.condition = try container.decode(String.self, forKey: .condition)
        self.weather = try container.decode(String.self, forKey: .weather)
        self.runners = try container.decode([Horse].self, forKey: .runners)
        self.suggestions = []
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(date, forKey: .date)
        try container.encode(track, forKey: .track)
        try container.encode(raceNumber, forKey: .raceNumber)
        try container.encode(distance, forKey: .distance)
        try container.encode(condition, forKey: .condition)
        try container.encode(weather, forKey: .weather)
        try container.encode(runners, forKey: .runners)
    }
    
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Race, rhs: Race) -> Bool { lhs.id == rhs.id }
}

@Model
final class Horse: Identifiable, Hashable, Codable {
    var id = UUID()
    var number: Int
    var name: String
    var jockey: String
    var trainer: String?
    var weight: Double
    var barrier: Int
    var form: String
    var stats: HorseStats
    
    init(number: Int, name: String, jockey: String, trainer: String?, weight: Double, barrier: Int, form: String, stats: HorseStats) {
        self.number = number
        self.name = name
        self.jockey = jockey
        self.trainer = trainer
        self.weight = weight
        self.barrier = barrier
        self.form = form
        self.stats = stats
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.number = try container.decode(Int.self, forKey: .number)
        self.name = try container.decode(String.self, forKey: .name)
        self.jockey = try container.decode(String.self, forKey: .jockey)
        self.trainer = try container.decodeIfPresent(String.self, forKey: .trainer)
        self.weight = try container.decode(Double.self, forKey: .weight)
        self.barrier = try container.decode(Int.self, forKey: .barrier)
        self.form = try container.decode(String.self, forKey: .form)
        self.stats = try container.decode(HorseStats.self, forKey: .stats)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(number, forKey: .number)
        try container.encode(name, forKey: .name)
        try container.encode(jockey, forKey: .jockey)
        try container.encodeIfPresent(trainer, forKey: .trainer)
        try container.encode(weight, forKey: .weight)
        try container.encode(barrier, forKey: .barrier)
        try container.encode(form, forKey: .form)
        try container.encode(stats, forKey: .stats)
    }
    
    enum CodingKeys: String, CodingKey {
        case number, name, jockey, trainer, weight, barrier, form, stats
    }
    
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Horse, rhs: Horse) -> Bool { lhs.id == rhs.id }
}

@Model
final class HorseStats: Codable {
    var winPct: Double
    var trackWinPct: Double
    var distanceWinPct: Double
    var goodTrackWinPct: Double
    var recentFormScore: Double
    
    init(winPct: Double, trackWinPct: Double, distanceWinPct: Double, goodTrackWinPct: Double, recentFormScore: Double) {
        self.winPct = winPct
        self.trackWinPct = trackWinPct
        self.distanceWinPct = distanceWinPct
        self.goodTrackWinPct = goodTrackWinPct
        self.recentFormScore = recentFormScore
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.winPct = try container.decode(Double.self, forKey: .winPct)
        self.trackWinPct = try container.decode(Double.self, forKey: .trackWinPct)
        self.distanceWinPct = try container.decode(Double.self, forKey: .distanceWinPct)
        self.goodTrackWinPct = try container.decode(Double.self, forKey: .goodTrackWinPct)
        self.recentFormScore = try container.decode(Double.self, forKey: .recentFormScore)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(winPct, forKey: .winPct)
        try container.encode(trackWinPct, forKey: .trackWinPct)
        try container.encode(distanceWinPct, forKey: .distanceWinPct)
        try container.encode(goodTrackWinPct, forKey: .goodTrackWinPct)
        try container.encode(recentFormScore, forKey: .recentFormScore)
    }
    
    enum CodingKeys: String, CodingKey {
        case winPct, trackWinPct, distanceWinPct, goodTrackWinPct, recentFormScore
    }
}

@Model
final class BetSuggestion: Identifiable {
    var id = UUID()
    var horseName: String
    var confidence: Int
    var units: Int
    var reason: String
    var raceInfo: String
    
    init(horseName: String, confidence: Int, units: Int, reason: String, raceInfo: String) {
        self.horseName = horseName
        self.confidence = confidence
        self.units = units
        self.reason = reason
        self.raceInfo = raceInfo
    }
}
