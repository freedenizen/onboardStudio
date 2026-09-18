import Foundation
import TelemetryKit

/// Turns the GPMF payloads of a GoPro recording into a `RawTable`: GPS (GPS9 on HERO11 and
/// later, GPS5 + GPSU before), accelerometer and gyroscope. The time axis is seconds from the
/// start of the recording, so the data lines up with the video without any sync; the GPS clock
/// gives the recording's absolute start time for syncing other loggers.
public enum GoProTelemetry {
    public static let sourceFormat = "GoPro GPMF"
    /// GPS rows with a worse dilution of precision than this are treated as having no fix.
    public static let maximumDOP = 10.0

    /// A stream extracted from one payload.
    struct Stream {
        let key: String
        let name: String
        let scale: [Double]
        let typeString: String?
        let orientation: String?
        /// Microseconds since the start of the recording for the first sample, from `STMP`.
        let startMicros: Double?
        let rows: [[Double]]
    }

    /// One decoded metadata sample with the streams it carries.
    struct Payload {
        let time: Double
        let duration: Double
        let streams: [Stream]
    }

    public struct Summary: Sendable {
        public let deviceName: String?
        public let gpsSamples: Int
        public let hasAccelerometer: Bool
        /// Seconds since 1970 at recording time 0, from the first GPS fix.
        public let recordingStartEpoch: Double?
    }

    /// Reads the file and builds the telemetry table.
    public static func importFile(at url: URL) throws -> RawTable {
        let track = try MP4Boxes.trackSamples("gpmd", in: url)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var payloads: [Payload] = []
        payloads.reserveCapacity(track.count)
        var deviceName: String?
        for index in 0..<track.count {
            let data = try MP4Boxes.sampleData(track, index: index, in: handle)
            let (streams, name) = extract(GPMFParser.parse(data))
            if deviceName == nil { deviceName = name }
            payloads.append(Payload(time: track.times[index], duration: track.durations[index], streams: streams))
        }
        return try table(from: payloads, deviceName: deviceName)
    }

    /// Reads only as much of the file as needed to find the first GPS fix.
    public static func recordingStartEpoch(of url: URL) -> Double? {
        guard let track = try? MP4Boxes.trackSamples("gpmd", in: url), let handle = try? FileHandle(forReadingFrom: url)
        else { return nil }
        defer { try? handle.close() }
        for index in 0..<min(track.count, 600) {
            guard let data = try? MP4Boxes.sampleData(track, index: index, in: handle) else { return nil }
            let (streams, _) = extract(GPMFParser.parse(data))
            let payload = Payload(time: track.times[index], duration: track.durations[index], streams: streams)
            if let epoch = firstFixEpoch(in: payload, nextStart: nil) { return epoch }
        }
        return nil
    }

    // MARK: - Payload decoding

    /// Pulls every STRM out of a parsed payload.
    static func extract(_ items: [GPMFItem]) -> (streams: [Stream], device: String?) {
        var streams: [Stream] = []
        var device: String?
        for devc in items where devc.key == "DEVC" {
            if device == nil { device = devc["DVNM"]?.string }
            for strm in devc.all("STRM") {
                guard let dataItem = strm.children.last(where: { isDataKey($0.key) }) else { continue }
                let scale = strm["SCAL"]?.numbers ?? []
                let typeString = strm["TYPE"]?.string
                let rows: [[Double]]
                if dataItem.type == UInt8(ascii: "?"), let typeString {
                    rows = dataItem.rows(typeString: typeString)
                } else {
                    let numbers = dataItem.numbers
                    let width = max(1, GPMFParser.width(of: dataItem.type).map { dataItem.sampleSize / $0 } ?? 1)
                    rows = stride(from: 0, to: numbers.count, by: width).map {
                        Array(numbers[$0..<min($0 + width, numbers.count)])
                    }
                }
                let startMicros = strm["STMP"]?.numbers.first
                let name = strm["STNM"]?.string ?? dataItem.key
                streams.append(
                    Stream(
                        key: dataItem.key, name: name, scale: scale, typeString: typeString,
                        orientation: strm["ORIN"]?.string, startMicros: startMicros, rows: rows))
            }
        }
        return (streams, device)
    }

    static func isDataKey(_ key: String) -> Bool {
        ["GPS9", "GPS5", "GPSU", "ACCL", "GYRO", "GRAV", "CORI", "IORI", "MAGN"].contains(key)
    }

    /// Applies SCAL: each column divided by its scale (a single scale applies to every column).
    static func scaled(_ row: [Double], by scale: [Double]) -> [Double] {
        guard !scale.isEmpty else { return row }
        return row.enumerated().map { index, value in
            let divisor = scale.count == 1 ? scale[0] : (index < scale.count ? scale[index] : 1)
            return divisor == 0 ? value : value / divisor
        }
    }

    /// Seconds since 1970 for a GPS9 row (days since 2000-01-01, seconds since midnight).
    static func epoch(gps9 row: [Double]) -> Double? {
        guard row.count >= 7 else { return nil }
        return 946_684_800 + row[5] * 86400 + row[6]
    }

    /// Recording start in epoch seconds from the first payload with a GPS fix.
    static func firstFixEpoch(in payload: Payload, nextStart: Double?) -> Double? {
        for stream in payload.streams where stream.key == "GPS9" {
            for (index, raw) in stream.rows.enumerated() {
                let row = scaled(raw, by: stream.scale)
                guard row.count >= 9, row[8] >= 2, row[7] <= maximumDOP, let epoch = epoch(gps9: row) else { continue }
                let time = sampleTime(payload: payload, stream: stream, index: index, nextStart: nextStart)
                return epoch - time
            }
        }
        return nil
    }

    /// Recording time of a sample: STMP-based when present, otherwise spread across the payload.
    static func sampleTime(payload: Payload, stream: Stream, index: Int, nextStart: Double?) -> Double {
        let count = max(stream.rows.count, 1)
        if let startMicros = stream.startMicros {
            let start = startMicros / 1_000_000
            let span = nextStart.map { $0 - start } ?? payload.duration
            return start + Double(index) * max(span, 0) / Double(count)
        }
        return payload.time + Double(index) * payload.duration / Double(count)
    }

    // MARK: - Table

    /// Samples gathered across payloads for one sensor.
    struct Series {
        var times: [Double] = []
        var rows: [[Double]] = []
        var orientation: String?
        var epochs: [Double?] = []
        var isEmpty: Bool { times.isEmpty }
    }

    struct Gathered {
        var gps = Series()  // lat, lon, alt, speed2d, speed3d, dop, fix
        var accel = Series()
        var gyro = Series()
    }

    /// Walks every payload and collects GPS, accelerometer and gyro samples with their times.
    static func gather(_ payloads: [Payload]) -> Gathered {
        var result = Gathered()
        for (payloadIndex, payload) in payloads.enumerated() {
            for stream in payload.streams {
                let nextStart =
                    payloadIndex + 1 < payloads.count
                    ? payloads[payloadIndex + 1].streams.first { $0.key == stream.key }?.startMicros.map {
                        $0 / 1_000_000
                    }
                    : nil
                func time(_ index: Int) -> Double {
                    sampleTime(payload: payload, stream: stream, index: index, nextStart: nextStart)
                }
                switch stream.key {
                case "GPS9":
                    for (index, raw) in stream.rows.enumerated() {
                        let row = scaled(raw, by: stream.scale)
                        guard row.count >= 9 else { continue }
                        result.gps.times.append(time(index))
                        result.gps.rows.append([row[0], row[1], row[2], row[3], row[4], row[7], row[8]])
                        result.gps.epochs.append(row[8] >= 2 ? epoch(gps9: row) : nil)
                    }
                case "GPS5":
                    for (index, raw) in stream.rows.enumerated() {
                        let row = scaled(raw, by: stream.scale)
                        guard row.count >= 5 else { continue }
                        result.gps.times.append(time(index))
                        result.gps.rows.append([row[0], row[1], row[2], row[3], row[4], 0, 3])
                        result.gps.epochs.append(nil)
                    }
                case "ACCL":
                    result.accel.orientation = result.accel.orientation ?? stream.orientation
                    for (index, raw) in stream.rows.enumerated() {
                        result.accel.times.append(time(index))
                        result.accel.rows.append(scaled(raw, by: stream.scale))
                    }
                case "GYRO":
                    result.gyro.orientation = result.gyro.orientation ?? stream.orientation
                    for (index, raw) in stream.rows.enumerated() {
                        result.gyro.times.append(time(index))
                        result.gyro.rows.append(scaled(raw, by: stream.scale))
                    }
                default:
                    continue
                }
            }
        }
        return result
    }

    static func table(from payloads: [Payload], deviceName: String?) throws -> RawTable {
        let gathered = gather(payloads)
        guard !gathered.gps.isEmpty || !gathered.accel.isEmpty else { throw GoProImportError.noTelemetry }

        // Merge the time axes.
        var allTimes = Set(gathered.gps.times)
        allTimes.formUnion(gathered.accel.times)
        allTimes.formUnion(gathered.gyro.times)
        let times = allTimes.sorted()
        let indexOf = Dictionary(uniqueKeysWithValues: times.enumerated().map { ($1, $0) })
        var columns: [RawColumn] = []
        if !gathered.gps.isEmpty { columns += gpsColumns(gathered.gps, indexOf: indexOf, count: times.count) }
        if !gathered.accel.isEmpty {
            columns += axisColumns(
                Axes(label: "Accel", unit: .gForce, roleBase: "accel", divisor: 9.80665), series: gathered.accel,
                indexOf: indexOf, count: times.count)
        }
        if !gathered.gyro.isEmpty {
            columns += axisColumns(
                Axes(label: "Gyro", unit: .custom("rad/s"), roleBase: "gyro", divisor: 1), series: gathered.gyro,
                indexOf: indexOf, count: times.count)
        }

        var info = SessionInfo(sourceFormat: sourceFormat)
        info.title = deviceName
        if let start = zip(gathered.gps.times, gathered.gps.epochs).first(where: { $0.1 != nil }), let epoch = start.1 {
            info.createdAt = Date(timeIntervalSince1970: epoch - start.0)
        }
        return RawTable(info: info, times: times, columns: columns)
    }

}

// MARK: - Columns

extension GoProTelemetry {
    static func gpsColumns(_ gps: Series, indexOf: [Double: Int], count: Int) -> [RawColumn] {
        func column(_ name: String, _ unit: TelemetryUnit, role: ChannelRole?, step: Bool = false) -> RawColumn {
            RawColumn(
                name: name, unit: unit, source: "gpmf", suggestedRole: role, interpolation: step ? .step : .linear,
                values: Array(repeating: nil, count: count))
        }
        var lat = column("Latitude", .degrees, role: .latitude)
        var lon = column("Longitude", .degrees, role: .longitude)
        var alt = column("Altitude", .meters, role: .altitude)
        var speed = column("Speed (2D)", .metersPerSecond, role: .speed)
        var speed3d = column("Speed (3D)", .metersPerSecond, role: .aux("speed_3d"))
        var dop = column("GPS DOP", .none, role: .aux("gps_dop"))
        var fix = column("GPS fix", .count, role: .aux("gps_fix"), step: true)
        for (k, time) in gps.times.enumerated() {
            guard let row = indexOf[time] else { continue }
            let g = gps.rows[k]
            // Rows without a fix, or with a hopeless dilution of precision, keep the time axis but
            // carry no position (HERO13 reports DOP 99.99 while it is still searching).
            if g[6] >= 2, g[5] <= maximumDOP {
                lat.values[row] = g[0]
                lon.values[row] = g[1]
                alt.values[row] = g[2]
                speed.values[row] = g[3]
                speed3d.values[row] = g[4]
            }
            dop.values[row] = g[5]
            fix.values[row] = g[6]
        }
        return [lat, lon, alt, speed, speed3d, dop, fix]
    }

    struct Axes {
        let label: String
        let unit: TelemetryUnit
        let roleBase: String
        let divisor: Double
    }

    /// X/Y/Z columns for a 3-axis sensor, reordered by the ORIN string (e.g. "ZXY").
    static func axisColumns(_ axesSpec: Axes, series: Series, indexOf: [Double: Int], count: Int) -> [RawColumn] {
        let fallback: [Character] = ["X", "Y", "Z"]
        let axes = Array((series.orientation ?? "XYZ").uppercased().prefix(3))
        var columns: [Character: RawColumn] = [:]
        for axis in ["X", "Y", "Z"] {
            columns[Character(axis)] = RawColumn(
                name: "\(axesSpec.label) \(axis)", unit: axesSpec.unit, source: "gpmf",
                suggestedRole: .aux("\(axesSpec.roleBase)_\(axis.lowercased())"),
                values: Array(repeating: nil, count: count))
        }
        for (k, time) in series.times.enumerated() {
            guard let row = indexOf[time] else { continue }
            for (position, value) in series.rows[k].prefix(3).enumerated() {
                let axis = position < axes.count ? axes[position] : fallback[position]
                columns[axis]?.values[row] = value / axesSpec.divisor
            }
        }
        return ["X", "Y", "Z"].compactMap { columns[Character($0)] }
    }

}

public enum GoProImportError: Error, CustomStringConvertible {
    case noTelemetry

    public var description: String {
        switch self {
        case .noTelemetry: "The GoPro metadata track has no GPS or motion data."
        }
    }
}
