import Foundation
import SwiftData

@Model
public final class BetRecord: Identifiable {
    public var id: UUID = UUID()
    public var raceDate: Date
    public var track: String
    public var raceNumber: Int
    public var horseName: String
    public var predictedProb: Double
    public var unitsBet: Int
    public var unitSize: Double
    public var result: String?
    public var actualOdds: Double?
    public var profit: Double?
    
    public init(raceDate: Date, track: String, raceNumber: Int, horseName: String, predictedProb: Double, unitsBet: Int, unitSize: Double) {
        self.raceDate = raceDate
        self.track = track
        self.raceNumber = raceNumber
        self.horseName = horseName
        self.predictedProb = predictedProb
        self.unitsBet = unitsBet
        self.unitSize = unitSize
    }
}

public struct Race: Identifiable, Codable {
    public let id = UUID()                    // This is fine for local use
    public let date: Date
    public let track: String
    public let raceNumber: Int
    public let distance: String
    public let condition: String
    public let weather: String
    public let runners: [Horse]
}

public struct Horse: Identifiable, Codable {
    public let id = UUID()
    public let number: Int
    public let name: String
    public let jockey: String
    public let trainer: String
    public let weight: Double
    public let barrier: Int
    public let form: String
    public let stats: HorseStats
}

public struct HorseStats: Codable {
    public let winPct: Double
    public let trackWinPct: Double
    public let distanceWinPct: Double
    public let goodTrackWinPct: Double
    public let recentFormScore: Double
}
