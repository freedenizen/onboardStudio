import Foundation

/// A session described for a person or a bug report: what `onboard probe --json` prints, and what
/// a diagnostics bundle carries for each data file (#152). Values only — never the samples.
public struct SessionReport: Encodable, Sendable {
    public struct ChannelSummary: Encodable, Sendable {
        let role: String
        let name: String
        let unit: String
        let samples: Int
        let min: Double?
        let max: Double?
        let sampleRate: Double?
        let interpolation: String
    }

    public struct LapSummary: Encodable, Sendable {
        let number: Int
        let start: Double
        let end: Double?
        let duration: Double?
        let isComplete: Bool
    }

    public struct CircuitSummary: Encodable, Sendable {
        let id: String
        let name: String
        let country: String
        let distanceKm: Double
        let runnerUpKm: Double?
        let nameAgrees: Bool
        let isConfident: Bool
    }

    public struct SectorSummary: Encodable, Sendable {
        let boundaryDistances: [Double]
        let lapLengthMeters: Double
        let referenceLap: Int
        let bestTimes: [Double?]
        let theoreticalLapTime: Double?
        let laps: [LapSectorSummary]
    }

    public struct LapSectorSummary: Encodable, Sendable {
        let number: Int
        let times: [Double?]
    }

    let importer: String
    /// How sure the importer was that the file is its format; `nil` when it was not asked.
    let confidence: Int?
    let info: SessionInfo
    let start: Double?
    let end: Double?
    let duration: Double
    let channels: [ChannelSummary]
    let laps: [LapSummary]
    let sectors: SectorSummary?
    let circuit: CircuitSummary?

    public init(session: TelemetrySession, importer: String, confidence: Int? = nil) {
        self.importer = importer
        self.confidence = confidence
        info = session.info
        start = session.timeRange?.lowerBound
        end = session.timeRange?.upperBound
        duration = session.duration
        channels = session.orderedChannels.map {
            ChannelSummary(
                role: $0.role.identifier, name: $0.name, unit: $0.unit.symbol, samples: $0.count, min: $0.minValue,
                max: $0.maxValue, sampleRate: $0.sampleRate, interpolation: $0.interpolation.rawValue)
        }
        laps = session.laps.map {
            LapSummary(
                number: $0.number, start: $0.start, end: $0.end, duration: $0.duration, isComplete: $0.isComplete)
        }
        sectors = session.sectors.map { analysis in
            SectorSummary(
                boundaryDistances: analysis.layout.boundaryDistances,
                lapLengthMeters: analysis.layout.lapLengthMeters,
                referenceLap: analysis.layout.referenceLapNumber,
                bestTimes: analysis.best.map { $0?.time },
                theoreticalLapTime: analysis.theoreticalLapTime,
                laps: analysis.laps.map { LapSectorSummary(number: $0.lapNumber, times: $0.times) })
        }
        circuit = CircuitCatalog.identify(session).map {
            CircuitSummary(
                id: $0.circuit.id, name: $0.circuit.name, country: $0.circuit.country,
                distanceKm: $0.distanceKm, runnerUpKm: $0.runnerUpKm, nameAgrees: $0.nameAgrees,
                isConfident: $0.isConfident)
        }
    }

    /// Pretty-printed, keys sorted, dates in ISO 8601.
    public func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}
