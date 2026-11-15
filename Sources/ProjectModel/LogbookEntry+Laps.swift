import CryptoKit
import Foundation
import TelemetryKit

/// How a logbook entry's laps are read from its file: which reading they are from, whether this
/// build should read them again, and each lap's sector times and speeds (#557).
extension LogbookEntry {
    /// The reading the laps of an entry are from. 2 (#477): a RaceChrono file's first lap begins
    /// at the first crossing of the line and is a whole lap — read from an `.rcz` archive it had
    /// swallowed the out-lap, and from a CSV it was called partial.
    public static let lapMeasurement = 2

    /// Whether the Logbook should offer to read this entry's file again (#498): it was read
    /// before the first lap was corrected, and it is one the correction can change — an archive,
    /// or a file whose first lap was called partial. A file it cannot change is not offered:
    /// reading it again would cost the time and move nothing. Laps that begin at lap 0 are not
    /// the file's own count but the app's, from a start/finish line; the correction is not about
    /// them, and read again without that line they would be lost.
    public var needsLapReading: Bool {
        guard lapMeasurement < Self.lapMeasurement, let first = laps.first, first.number != 0 else { return false }
        return file.importerID == "racechrono-rcz" || !first.isComplete
    }

    // MARK: - Sectors and speeds (#557)

    /// The reading the laps' sector times and speeds are from. 1 (#557): the first.
    public static let splitsMeasurement = 1

    /// Whether its laps are still to be given their sector times and speeds: it was entered
    /// before they were read. The Logbook reads them from the file when it next shows the session.
    public var needsSplitReading: Bool { splitsMeasurement < Self.splitsMeasurement && !laps.isEmpty }

    /// Puts each lap's sector times and its top and minimum speed on `laps`, from `session`,
    /// matched by lap number. Nothing else on a lap or on the entry changes: not its times, not
    /// its best or optimal lap, not anything the driver wrote.
    ///
    /// A lap the recording began during — the out-lap from the pits — has no sector times: they
    /// are counted from where its lap began, which was not the line, so its first sector would be
    /// any length and could pass for the best.
    public mutating func readSplits(of session: TelemetrySession) {
        let sectors = session.sectors
        let listed = session.laps.listed
        let speeds = SessionStats.speedRanges(of: listed, in: session)
        let unseenStarts = Set(
            listed.filter { lap in
                !lap.isComplete && session.timeRange.map { lap.start <= $0.lowerBound + 0.5 } ?? false
            }
            .map(\.number))
        for index in laps.indices {
            let number = laps[index].number
            laps[index].sectors =
                sectors.map {
                    unseenStarts.contains(number) ? Array(repeating: nil, count: $0.count) : $0.times(ofLap: number)
                }
                ?? []
            laps[index].topSpeed = speeds[number]?.upperBound
            laps[index].minSpeed = speeds[number]?.lowerBound
        }
        splitsMeasurement = Self.splitsMeasurement
    }

    /// How many sectors its laps are timed in; 0 when it has none.
    public var sectorCount: Int { laps.map(\.sectors.count).max() ?? 0 }

    /// The quickest time in each sector by any of its laps, `nil` for a sector none of them
    /// timed: the times its optimal lap is made of.
    public var bestSectors: [Double?] {
        (0..<sectorCount).map { index in
            laps.compactMap { $0.sectors.indices.contains(index) ? $0.sectors[index] : nil }.min()
        }
    }

    /// How far `lap` was off the session's best lap, in seconds; zero on the best lap itself,
    /// `nil` for a lap that did not finish.
    public func gapToBest(_ lap: LapRecord) -> Double? {
        guard lap.isComplete, let seconds = lap.seconds, let bestLap else { return nil }
        return seconds - bestLap
    }

    /// The highest top speed and the highest minimum speed of its complete laps, m/s: the ones
    /// that stand out in their columns. A higher minimum is the better one, the slowest corner
    /// taken quicker; an out-lap's crawl from the pits is no record.
    public var bestTopSpeed: Double? { laps.filter(\.isComplete).compactMap(\.topSpeed).max() }
    public var bestMinSpeed: Double? { laps.filter(\.isComplete).compactMap(\.minSpeed).max() }

    // MARK: - The file

    /// SHA-256 of the file, streamed, and its length.
    public static func hash(of url: URL) throws -> (hex: String, byteCount: Int) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        var total = 0
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
            total += chunk.count
        }
        let digest = hasher.finalize()
        return (digest.map { String(format: "%02x", $0) }.joined(), total)
    }
}
