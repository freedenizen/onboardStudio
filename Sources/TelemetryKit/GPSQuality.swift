import Foundation

/// How far a session's positions can be trusted (#555).
///
/// A phone logging once a second and a 25 Hz logger look the same in a list of laps, yet one puts
/// a brake point within a metre and the other within twenty-five. This is what the session itself
/// says about that: how often a position arrived, where none did, where one landed somewhere the
/// car could not have got to, what the logger said about its own accuracy, and whether a lap is so
/// long that the start/finish line was probably missed.
///
/// Every threshold is an `Options` value with a default, never a property of one logger.
public struct GPSQuality: Hashable, Sendable, Codable {
    /// How much a driver can lean on the session's distances.
    public enum Rating: Int, Hashable, Sendable, Codable, Comparable, CaseIterable {
        /// Fine for corner-level advice.
        case good
        /// Usable, with something worth knowing.
        case fair
        /// Too coarse or patchy for distances to the metre.
        case poor

        public static func < (lhs: Rating, rhs: Rating) -> Bool { lhs.rawValue < rhs.rawValue }

        public var title: String {
            switch self {
            case .good: "Good"
            case .fair: "Fair"
            case .poor: "Poor"
            }
        }
    }

    /// What counts against the session.
    public enum Issue: Hashable, Sendable, Codable {
        /// Fewer positions a second than corner-level advice needs.
        case rate(hertz: Double, wanted: Double)
        /// Stretches with no position while the car was moving.
        case dropouts(count: Int, longestSeconds: Double)
        /// Positions further from the last than the car could have travelled.
        case jumps(count: Int)
        /// The logger's own median estimate of its error.
        case accuracy(meters: Double)
        /// Median horizontal dilution of precision: how poorly the satellites were spread.
        case hdop(Double)
        /// Median satellites in use.
        case satellites(Double)
        /// Laps about twice as long as the rest: a crossing of the line was missed.
        case longLaps([Int])
    }

    /// Something that counts against the session, with how much.
    public struct Finding: Hashable, Sendable, Codable {
        public var issue: Issue
        public var rating: Rating

        public init(_ issue: Issue, _ rating: Rating) {
            self.issue = issue
            self.rating = rating
        }
    }

    /// A stretch with no position while the car was moving.
    public struct Gap: Hashable, Sendable, Codable {
        public var start: Double
        public var end: Double

        public init(start: Double, end: Double) {
            self.start = start
            self.end = end
        }

        public var seconds: Double { end - start }
    }

    /// The thresholds, each with a default a driver can change.
    public struct Options: Hashable, Sendable, Codable {
        /// Positions a second at and above which the rate is no concern.
        public var goodRateHertz = 10.0
        /// Below this the rate alone makes the data poor.
        public var poorRateHertz = 5.0
        /// A gap counts as a dropout when it is this many usual intervals long…
        public var dropoutIntervals = 3.0
        /// …and at least this many seconds.
        public var dropoutMinimumSeconds = 0.5
        /// A dropout this long makes the data poor: a corner can pass inside it.
        public var poorDropoutSeconds = 3.0
        /// The change of speed between two fixes beyond which a position is a jump (m/s², ≈ 3 g).
        public var jumpAcceleration = 30.0
        /// This many jumps make the data poor.
        public var poorJumpCount = 5.0
        /// Assumed error of a position when the file does not say (m).
        public var assumedNoiseMeters = 0.5
        /// Median logged accuracy at and below which it is no concern (m).
        public var goodAccuracyMeters = 2.0
        /// Median logged accuracy beyond which the data is poor (m).
        public var poorAccuracyMeters = 5.0
        public var goodHDOP = 1.5
        public var poorHDOP = 3.0
        /// Median satellites in use at and above which they are no concern.
        public var goodSatellites = 8.0
        /// Below this many satellites the data is poor.
        public var poorSatellites = 5.0
        /// A complete lap this many times the usual length has a missed crossing in it.
        public var longLapFactor = 1.6
        /// Below this speed (m/s) the car is parked or crawling, and gaps and rate do not count.
        public var movingSpeed = 3.0

        public init() {}
    }

    /// Median positions a second while moving.
    public var rateHertz: Double
    public var dropouts: [Gap]
    /// Session times of the positions that jumped.
    public var jumps: [Double]
    public var accuracyMeters: Double?
    public var hdop: Double?
    public var satellites: Double?
    /// Lap numbers that look like two laps run together.
    public var longLaps: [Int]
    /// About how far a distance read from this data can be off (m): the position's own error and
    /// how far the car travels at speed between two positions.
    public var precisionMeters: Double
    /// Everything that counts against the session, worst first. Empty when it is good.
    public var findings: [Finding]

    public init(
        rateHertz: Double, dropouts: [Gap] = [], jumps: [Double] = [], accuracyMeters: Double? = nil,
        hdop: Double? = nil, satellites: Double? = nil, longLaps: [Int] = [], precisionMeters: Double,
        findings: [Finding] = []
    ) {
        self.rateHertz = rateHertz
        self.dropouts = dropouts
        self.jumps = jumps
        self.accuracyMeters = accuracyMeters
        self.hdop = hdop
        self.satellites = satellites
        self.longLaps = longLaps
        self.precisionMeters = precisionMeters
        self.findings = findings
    }

    /// The worst of the findings; good when there are none.
    public var rating: Rating { findings.map(\.rating).max() ?? .good }

    /// The step a distance read from this data is rounded to, in `unit`: 1 m on good data,
    /// coarser as the data allows less. A round number a driver can say, never "17 m".
    public func distanceStep(in unit: TelemetryUnit = .meters) -> Double {
        let precision = TelemetryUnit.meters.convert(precisionMeters, to: unit) ?? precisionMeters
        return Self.steps.first { $0 >= precision } ?? Self.steps[Self.steps.count - 1]
    }

    static let steps: [Double] = [1, 2, 5, 10, 15, 20, 25, 50, 75, 100, 150, 200, 300]

    /// The same measurements judged against other thresholds: a driver's own, from Settings.
    public func rated(with options: Options) -> GPSQuality {
        var rated = self
        rated.findings = Self.findings(of: self, options: options)
        return rated
    }

    /// Whether a position is missing anywhere between `start` and `end`, so a distance measured
    /// across them is a guess.
    public func hasDropout(between start: Double, and end: Double) -> Bool {
        dropouts.contains { $0.start < end && $0.end > start }
    }
}
