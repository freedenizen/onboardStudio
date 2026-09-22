import Foundation
import TelemetryKit

/// Reads a RaceChrono `.rcz` session archive (#68).
///
/// A plain zip holding `session.json` (track, laps and their validity, the optimal lap),
/// `sessionfragment.json` (which device produced what) and one binary stream per channel. The CSV
/// export is the usual way in, and it loses the per-lap `isInvalid` flag and the optimal lap time;
/// the archive keeps both, and is one file instead of two.
///
/// ## The layout, as decoded against a session exported both ways
///
/// Members are named `channel_<deviceType>_<deviceId>_<canId>_<channelId>_<kind>`.
///
/// - **GPS, accelerometer and gyro** devices write one file per channel, all with the same record
///   count. Channel 1 is the device's own time axis, `int64` milliseconds. Channel 2 is distance
///   travelled in millimetres. Channel 3 is position: an `int32` pair, latitude then longitude,
///   over **6,000,000** — degrees × 60 × 10⁵, minutes rather than the usual 1e7. Everything else
///   is a scalar `int32` with a fixed scale.
/// - **CAN** channels are logged at their own rates, so each gets three files: `…_1_1` its
///   timestamps, `…_2_1` the distance at each, and `channel2_…_3` the values, as `float64`.
///
/// Channel ids are the logger's own: the archive carries no names for them, so a CAN channel
/// imports as `canbus:<id>` and the user says what it is in the attribute table (#111). That is
/// the same bargain the CSV export offers, which names them only because the phone knew.
public struct RCZImporter: TelemetryImporter {
    public static let id = "racechrono-rcz"
    public static let displayName = "RaceChrono archive"
    public static let fileExtensions = ["rcz"]

    public init() {}

    public static func confidence(for sniff: FileSniff) -> ImportConfidence {
        // A zip starts `PK\u{03}\u{04}`, and the extension is what tells an .rcz from any other zip.
        guard sniff.head.hasPrefix("PK") else { return .no }
        return fileExtensions.contains(sniff.fileExtension) ? .certain : .no
    }

    public func importFile(at url: URL) throws -> RawTable {
        let archive = try ZipArchive(contentsOf: url)
        guard let sessionData = try archive.contents(of: "session.json") else {
            throw ImportError.missingHeader("session.json")
        }
        let session = try JSONDecoder().decode(RCZSessionJSON.self, from: sessionData)
        let devices = try deviceTypes(in: archive)
        let streams = Self.streams(in: archive, devices: devices)
        guard !streams.isEmpty else { throw ImportError.noData }

        // One axis for the whole table, because every device samples on its own clock and a
        // channel must keep the times it was actually recorded at. Values land on their own
        // timestamps and are nil everywhere else; `SessionBuilder` drops the gaps.
        var axis: Set<Int64> = []
        for stream in streams { axis.formUnion(stream.timestamps) }
        let times = axis.sorted()
        guard !times.isEmpty else { throw ImportError.noData }
        var index: [Int64: Int] = [:]
        index.reserveCapacity(times.count)
        for (position, time) in times.enumerated() { index[time] = position }

        var columns: [RawColumn] = []
        for stream in streams {
            for column in stream.columns(rowCount: times.count, index: index) { columns.append(column) }
        }

        var info = SessionInfo(sourceFormat: Self.displayName, sourceFileName: url.lastPathComponent)
        info.title = session.trackName
        info.trackName = session.trackName
        info.createdAt = session.firstTimestamp.map { Date(timeIntervalSince1970: Double($0) / 1000) }
        let origin = Double(times[0]) / 1000
        return RawTable(
            info: info, times: times.map { Double($0) / 1000 - origin }, columns: columns,
            lapMarkers: session.lapMarkers(origin: times[0]))
    }

    /// Device id → the kind of device it is (1 GPS, 2 accelerometer, 3 gyro, 12 CAN bus).
    private func deviceTypes(in archive: ZipArchive) throws -> [Int: Int] {
        guard let data = try archive.contents(of: "sessionfragment.json"),
            let fragment = try? JSONDecoder().decode(RCZFragmentJSON.self, from: data)
        else { return [:] }
        return (fragment.devices?.items ?? []).reduce(into: [:]) { types, device in
            if let id = device.id, let type = device.type { types[id] = type }
        }
    }
}

/// `session.json`: what the logger recorded about the session as a whole.
private struct RCZSessionJSON: Decodable {
    var trackName: String?
    var firstTimestamp: Int64?
    var bestLaptime: Int?
    var optimalLaptime: Int?
    var laps: [RCZLapJSON]?

    /// Lap boundaries as the logger recorded them, rather than as `SessionBuilder` would infer
    /// them from the trace.
    func lapMarkers(origin: Int64) -> [RawLapMarker] {
        (laps ?? []).compactMap { lap -> RawLapMarker? in
            guard let finish = lap.finishTimestamp, let number = lap.number else { return nil }
            return RawLapMarker(number: number, time: Double(finish - origin) / 1000)
        }
    }
}

private struct RCZLapJSON: Decodable {
    var number: Int?
    var startTimestamp: Int64?
    var finishTimestamp: Int64?
}

/// `sessionfragment.json`: which device produced which streams.
private struct RCZFragmentJSON: Decodable {
    var devices: RCZDevicesJSON?
}

private struct RCZDevicesJSON: Decodable {
    var items: [RCZDeviceJSON]?
}

private struct RCZDeviceJSON: Decodable {
    var id: Int?
    var type: Int?
}
