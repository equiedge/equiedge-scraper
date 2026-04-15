import Foundation
import SwiftData

// MARK: - BetSuggestion (AI output)
@Model
final class BetSuggestion: Identifiable, Codable {
    var id = UUID()
    var horseName: String
    var confidence: Int
    var units: Int
    var reason: String
    var fixedWinOdds: Double?
    var result: String?  // "Won" or "Lost" — persisted in race cache for history
    var redFlagsChecked: String?
    var trackBias: String?
    // Pro fields
    var paceAssessment: String?
    var classAssessment: String?
    var mlModelRank: Int?
    var mlWinProb: Double?
    @Transient var keyBadges: [String]? = nil

    init(horseName: String, confidence: Int, units: Int, reason: String, fixedWinOdds: Double? = nil, result: String? = nil, redFlagsChecked: String? = nil, trackBias: String? = nil, paceAssessment: String? = nil, classAssessment: String? = nil, mlModelRank: Int? = nil, mlWinProb: Double? = nil, keyBadges: [String]? = nil) {
        self.horseName = horseName
        self.confidence = confidence
        self.units = units
        self.reason = reason
        self.fixedWinOdds = fixedWinOdds
        self.result = result
        self.redFlagsChecked = redFlagsChecked
        self.trackBias = trackBias
        self.paceAssessment = paceAssessment
        self.classAssessment = classAssessment
        self.mlModelRank = mlModelRank
        self.mlWinProb = mlWinProb
        self.keyBadges = keyBadges
    }

    // Codable support
    enum CodingKeys: String, CodingKey {
        case horseName, confidence, units, reason, fixedWinOdds, result, redFlagsChecked, trackBias
        case paceAssessment, classAssessment, mlModelRank, mlWinProb, keyBadges
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.horseName = try container.decode(String.self, forKey: .horseName)
        self.confidence = try container.decode(Int.self, forKey: .confidence)
        self.units = try container.decode(Int.self, forKey: .units)
        self.reason = try container.decode(String.self, forKey: .reason)
        self.fixedWinOdds = try container.decodeIfPresent(Double.self, forKey: .fixedWinOdds)
        self.result = try container.decodeIfPresent(String.self, forKey: .result)
        self.redFlagsChecked = try container.decodeIfPresent(String.self, forKey: .redFlagsChecked)
        self.trackBias = try container.decodeIfPresent(String.self, forKey: .trackBias)
        self.paceAssessment = try container.decodeIfPresent(String.self, forKey: .paceAssessment)
        self.classAssessment = try container.decodeIfPresent(String.self, forKey: .classAssessment)
        self.mlModelRank = try container.decodeIfPresent(Int.self, forKey: .mlModelRank)
        self.mlWinProb = try container.decodeIfPresent(Double.self, forKey: .mlWinProb)
        self.keyBadges = try container.decodeIfPresent([String].self, forKey: .keyBadges)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(horseName, forKey: .horseName)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(units, forKey: .units)
        try container.encode(reason, forKey: .reason)
        try container.encodeIfPresent(fixedWinOdds, forKey: .fixedWinOdds)
        try container.encodeIfPresent(result, forKey: .result)
        try container.encodeIfPresent(redFlagsChecked, forKey: .redFlagsChecked)
        try container.encodeIfPresent(trackBias, forKey: .trackBias)
        try container.encodeIfPresent(paceAssessment, forKey: .paceAssessment)
        try container.encodeIfPresent(classAssessment, forKey: .classAssessment)
        try container.encodeIfPresent(mlModelRank, forKey: .mlModelRank)
        try container.encodeIfPresent(mlWinProb, forKey: .mlWinProb)
        try container.encodeIfPresent(keyBadges, forKey: .keyBadges)
    }
}

// MARK: - RunnerStatCategory (matches API stats structure)
struct RunnerStatCategory: Codable {
    var starts: Int
    var wins: Int
    var places: Int
    var seconds: Int
    var thirds: Int
    var winPercent: Double
    var placePercent: Double
}

struct RunnerStats: Codable {
    var overall: RunnerStatCategory?
    var track: RunnerStatCategory?
    var distance: RunnerStatCategory?
    var trackDistance: RunnerStatCategory?
    var condition: RunnerStatCategory?
    var firstUp: RunnerStatCategory?
    var secondUp: RunnerStatCategory?
}

// MARK: - FormFav Pro Data Structs

struct FormBadge: Codable, Identifiable {
    var id: String { type }
    var type: String
    var label: String
    var shortLabel: String
    var category: String
    var sentiment: String    // "+", "/", "-"
    var description: String
    var detail: String

    var sentimentColor: String {
        switch sentiment {
        case "+": return "green"
        case "-": return "red"
        default: return "gray"
        }
    }
}

struct SpeedMap: Codable {
    var runningStyle: String       // L/P/M/B/X
    var earlySpeedIndex: Double
    var settlingPosition: Double

    var runningStyleLabel: String {
        switch runningStyle {
        case "L": return "Leader"
        case "P": return "Presser"
        case "M": return "Midfield"
        case "B": return "Back"
        default: return "Unknown"
        }
    }
}

struct ClassProfile: Codable {
    var currentRating: Int
    var peakRating: Int
    var highestClassWon: Int
    var optimalRangeMin: Int
    var optimalRangeMax: Int
    var trend: String
}

struct RaceClassFit: Codable {
    var raceClassRating: Int
    var classDifference: Int
    var withinOptimalRange: Bool
    var assessment: String

    var assessmentLabel: String {
        switch assessment {
        case "comfort_zone": return "Comfort Zone"
        case "slight_rise": return "Slight Rise"
        case "big_rise": return "Big Rise"
        case "slight_drop": return "Slight Drop"
        case "big_drop": return "Big Drop"
        default: return assessment.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

struct RacePrediction: Codable {
    var winProb: Double
    var placeProb: Double
    var modelRank: Int
}

// MARK: - Runner
@Model
final class Runner: Identifiable, Codable {
    var id = UUID()
    var number: Int
    var name: String
    var jockey: String
    var trainer: String
    var weight: Double
    var barrier: Int
    var form: String
    @Transient var stats: RunnerStats? = nil
    // Pro fields
    var age: Int?
    var claim: Double?
    var scratched: Bool = false
    @Transient var decorators: [FormBadge]? = nil
    @Transient var speedMap: SpeedMap? = nil
    @Transient var classProfile: ClassProfile? = nil
    @Transient var raceClassFit: RaceClassFit? = nil
    @Transient var prediction: RacePrediction? = nil

    var effectiveWeight: Double {
        weight - (claim ?? 0)
    }

    init(number: Int, name: String, jockey: String, trainer: String, weight: Double, barrier: Int, form: String, stats: RunnerStats? = nil, age: Int? = nil, claim: Double? = nil, scratched: Bool = false) {
        self.number = number
        self.name = name
        self.jockey = jockey
        self.trainer = trainer
        self.weight = weight
        self.barrier = barrier
        self.form = form
        self.stats = stats
        self.age = age
        self.claim = claim
        self.scratched = scratched
    }

    enum CodingKeys: String, CodingKey {
        case number, name, jockey, trainer, weight, barrier, form, stats
        case age, claim, scratched, decorators, speedMap, classProfile, raceClassFit, prediction
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.number = try container.decode(Int.self, forKey: .number)
        self.name = try container.decode(String.self, forKey: .name)
        self.jockey = try container.decode(String.self, forKey: .jockey)
        self.trainer = try container.decode(String.self, forKey: .trainer)
        self.weight = try container.decode(Double.self, forKey: .weight)
        self.barrier = try container.decode(Int.self, forKey: .barrier)
        self.form = try container.decode(String.self, forKey: .form)
        self.stats = try? container.decodeIfPresent(RunnerStats.self, forKey: .stats)
        self.age = try? container.decodeIfPresent(Int.self, forKey: .age)
        self.claim = try? container.decodeIfPresent(Double.self, forKey: .claim)
        self.scratched = (try? container.decodeIfPresent(Bool.self, forKey: .scratched)) ?? false
        self.decorators = try? container.decodeIfPresent([FormBadge].self, forKey: .decorators)
        self.speedMap = try? container.decodeIfPresent(SpeedMap.self, forKey: .speedMap)
        self.classProfile = try? container.decodeIfPresent(ClassProfile.self, forKey: .classProfile)
        self.raceClassFit = try? container.decodeIfPresent(RaceClassFit.self, forKey: .raceClassFit)
        self.prediction = try? container.decodeIfPresent(RacePrediction.self, forKey: .prediction)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(number, forKey: .number)
        try container.encode(name, forKey: .name)
        try container.encode(jockey, forKey: .jockey)
        try container.encode(trainer, forKey: .trainer)
        try container.encode(weight, forKey: .weight)
        try container.encode(barrier, forKey: .barrier)
        try container.encode(form, forKey: .form)
        try container.encodeIfPresent(stats, forKey: .stats)
        try container.encodeIfPresent(age, forKey: .age)
        try container.encodeIfPresent(claim, forKey: .claim)
        try container.encode(scratched, forKey: .scratched)
        try container.encodeIfPresent(decorators, forKey: .decorators)
        try container.encodeIfPresent(speedMap, forKey: .speedMap)
        try container.encodeIfPresent(classProfile, forKey: .classProfile)
        try container.encodeIfPresent(raceClassFit, forKey: .raceClassFit)
        try container.encodeIfPresent(prediction, forKey: .prediction)
    }
}

// MARK: - Race
@Model
final class Race: Identifiable, Codable {
    var id: String
    var date: Date
    var track: String
    var raceNumber: Int
    var distance: String
    var condition: String
    var weather: String
    var runners: [Runner] = []
    var suggestions: [BetSuggestion] = []
    var aiAnalysis: String = ""
    var raceStartTime: Date?
    // Pro fields
    var paceScenario: String?
    var raceClass: String?
    var raceName: String?

    init(id: String, date: Date, track: String, raceNumber: Int, distance: String, condition: String, weather: String, runners: [Runner], suggestions: [BetSuggestion] = [], aiAnalysis: String = "", raceStartTime: Date? = nil, paceScenario: String? = nil, raceClass: String? = nil, raceName: String? = nil) {
        self.id = id
        self.date = date
        self.track = track
        self.raceNumber = raceNumber
        self.distance = distance
        self.condition = condition
        self.weather = weather
        self.runners = runners
        self.suggestions = suggestions
        self.aiAnalysis = aiAnalysis
        self.raceStartTime = raceStartTime
        self.paceScenario = paceScenario
        self.raceClass = raceClass
        self.raceName = raceName
    }

    enum CodingKeys: String, CodingKey {
        case id, date, track, raceNumber, distance, condition, weather, runners, suggestions, aiAnalysis, raceStartTime
        case paceScenario, raceClass, raceName
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
        self.runners = try container.decode([Runner].self, forKey: .runners)
        self.suggestions = try container.decodeIfPresent([BetSuggestion].self, forKey: .suggestions) ?? []
        self.aiAnalysis = try container.decodeIfPresent(String.self, forKey: .aiAnalysis) ?? ""
        self.raceStartTime = try container.decodeIfPresent(Date.self, forKey: .raceStartTime)
        self.paceScenario = try container.decodeIfPresent(String.self, forKey: .paceScenario)
        self.raceClass = try container.decodeIfPresent(String.self, forKey: .raceClass)
        self.raceName = try container.decodeIfPresent(String.self, forKey: .raceName)
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
        try container.encode(suggestions, forKey: .suggestions)
        try container.encode(aiAnalysis, forKey: .aiAnalysis)
        try container.encodeIfPresent(raceStartTime, forKey: .raceStartTime)
        try container.encodeIfPresent(paceScenario, forKey: .paceScenario)
        try container.encodeIfPresent(raceClass, forKey: .raceClass)
        try container.encodeIfPresent(raceName, forKey: .raceName)
    }
}

// MARK: - BetRecord (for My Bets & Performance)
@Model
final class BetRecord: Identifiable, Codable {
    var id = UUID()
    var raceInfo: String
    var horseName: String
    var runnerNumber: Int
    var barrier: Int
    var weight: Double
    var units: Int
    var amount: Double
    var confidence: Int
    var reason: String
    var result: String?          // "Won" or "Lost"
    var odds: Double?
    var profit: Double?
    var date: Date
    
    var displayName: String {
        "#\(runnerNumber) \(horseName) (B: \(barrier), W: \(String(format: "%.1f", weight))kg)"
    }

    var isPendingWin: Bool {
        result == "Pending Win"
    }
    
    init(raceInfo: String, horseName: String, runnerNumber: Int = 0, barrier: Int = 0, weight: Double = 0, units: Int, amount: Double, confidence: Int, reason: String, result: String? = nil, odds: Double? = nil, profit: Double? = nil, date: Date) {
        self.raceInfo = raceInfo
        self.horseName = horseName
        self.runnerNumber = runnerNumber
        self.barrier = barrier
        self.weight = weight
        self.units = units
        self.amount = amount
        self.confidence = confidence
        self.reason = reason
        self.result = result
        self.odds = odds
        self.profit = profit
        self.date = date
    }
    
    enum CodingKeys: String, CodingKey {
        case id, raceInfo, horseName, runnerNumber, barrier, weight, units, amount, confidence, reason, result, odds, profit, date
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.raceInfo = try container.decode(String.self, forKey: .raceInfo)
        self.horseName = try container.decode(String.self, forKey: .horseName)
        self.runnerNumber = (try? container.decodeIfPresent(Int.self, forKey: .runnerNumber)) ?? 0
        self.barrier = (try? container.decodeIfPresent(Int.self, forKey: .barrier)) ?? 0
        self.weight = (try? container.decodeIfPresent(Double.self, forKey: .weight)) ?? 0
        self.units = try container.decode(Int.self, forKey: .units)
        self.amount = try container.decode(Double.self, forKey: .amount)
        self.confidence = try container.decode(Int.self, forKey: .confidence)
        self.reason = try container.decode(String.self, forKey: .reason)
        self.result = try container.decodeIfPresent(String.self, forKey: .result)
        self.odds = try container.decodeIfPresent(Double.self, forKey: .odds)
        self.profit = try container.decodeIfPresent(Double.self, forKey: .profit)
        self.date = try container.decode(Date.self, forKey: .date)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(raceInfo, forKey: .raceInfo)
        try container.encode(horseName, forKey: .horseName)
        try container.encode(runnerNumber, forKey: .runnerNumber)
        try container.encode(barrier, forKey: .barrier)
        try container.encode(weight, forKey: .weight)
        try container.encode(units, forKey: .units)
        try container.encode(amount, forKey: .amount)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(reason, forKey: .reason)
        try container.encodeIfPresent(result, forKey: .result)
        try container.encodeIfPresent(odds, forKey: .odds)
        try container.encodeIfPresent(profit, forKey: .profit)
        try container.encode(date, forKey: .date)
    }
}
