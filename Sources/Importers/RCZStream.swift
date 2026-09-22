import Foundation
import TelemetryKit

extension RCZImporter {
    /// One device's channels, already read out of the archive and sharing that device's clock.
    struct Stream {
        let deviceID: Int
        let deviceType: Int
        /// The CAN channel id, for a CAN stream. `nil` for the GPS and IMU devices, whose channels
        /// all share one axis.
        let canID: Int?
        var timestamps: [Int64]
        /// Channel id → the raw values read for it, already scaled.
        var values: [Int: [Double]] = [:]
        /// Positions, when the device logged them: latitude and longitude in degrees.
        var positions: [RCZImporter.Position] = []

        /// The columns this stream contributes, each aligned to the table's shared axis.
        func columns(rowCount: Int, index: [Int64: Int]) -> [RawColumn] {
            var columns: [RawColumn] = []
            if !positions.isEmpty {
                let latitude = RCZImporter.Meaning(name: "latitude", role: .latitude, unit: .degrees)
                let longitude = RCZImporter.Meaning(name: "longitude", role: .longitude, unit: .degrees)
                columns.append(column(latitude, positions.map(\.latitude), rowCount, index))
                columns.append(column(longitude, positions.map(\.longitude), rowCount, index))
            }
            for (channel, samples) in values.sorted(by: { $0.key < $1.key }) {
                let meaning = RCZImporter.meaning(deviceType: deviceType, channel: canID ?? channel)
                columns.append(column(meaning, samples, rowCount, index))
            }
            return columns
        }

        private func column(
            _ meaning: RCZImporter.Meaning, _ samples: [Double], _ rowCount: Int, _ index: [Int64: Int]
        ) -> RawColumn {
            var values = [Double?](repeating: nil, count: rowCount)
            for (position, time) in timestamps.enumerated() where position < samples.count {
                if let row = index[time] { values[row] = samples[position] }
            }
            return RawColumn(
                name: meaning.name, unit: meaning.unit, suggestedRole: meaning.role, values: values)
        }
    }

    /// What a channel id means, per device kind.
    ///
    /// Decoded by importing a session both ways and matching ranges: the archive's channel 4 on a
    /// GPS device runs 0…54548 where the CSV's speed runs 0…54.548 m/s, and so on for every one of
    /// them. The scales are exact, not fitted.
    struct Meaning {
        var name: String
        var role: ChannelRole?
        var unit: TelemetryUnit
    }

    static func meaning(deviceType: Int, channel: Int) -> Meaning {
        switch (deviceType, channel) {
        case (1, 2): Meaning(name: "distance", role: .distance, unit: .meters)
        case (1, 4): Meaning(name: "speed", role: .speed, unit: .metersPerSecond)
        case (1, 5): Meaning(name: "altitude", role: .altitude, unit: .meters)
        case (1, 6): Meaning(name: "bearing", role: .heading, unit: .degrees)
        case (1, 46): Meaning(name: "device_battery_level", role: .aux("device_battery_level"), unit: .percent)
        case (1, 30002): Meaning(name: "satellites", role: .aux("satellites"), unit: .count)
        case (1, 30003): Meaning(name: "fix_type", role: .aux("fix_type"), unit: .count)
        case (1, 30007): Meaning(name: "accuracy", role: .accuracy, unit: .meters)
        case (2, 2), (3, 2): Meaning(name: "distance", role: nil, unit: .meters)
        case (2, 9): Meaning(name: "x_acc", role: .aux("x_acc"), unit: .gForce)
        case (2, 10): Meaning(name: "y_acc", role: .aux("y_acc"), unit: .gForce)
        case (2, 11): Meaning(name: "z_acc", role: .aux("z_acc"), unit: .gForce)
        case (3, 12): Meaning(name: "x_rate_of_rotation", role: .aux("x_rate_of_rotation"), unit: .degreesPerSecond)
        case (3, 13): Meaning(name: "y_rate_of_rotation", role: .aux("y_rate_of_rotation"), unit: .degreesPerSecond)
        case (3, 14): Meaning(name: "z_rate_of_rotation", role: .aux("z_rate_of_rotation"), unit: .degreesPerSecond)
        // A CAN channel id is the logger's own and the archive carries no name for it, so it keeps
        // the id and the user says what it is in the attribute table (#111).
        case (12, let id): Meaning(name: "canbus_\(id)", role: .canbus("\(id)"), unit: .none)
        default: Meaning(name: "channel_\(channel)", role: .aux("channel_\(channel)"), unit: .none)
        }
    }

    /// The scale taking a stored integer to the unit above. Every one is a power of ten chosen by
    /// the logger; `nil` means the channel is stored as `float64` and needs none.
    static func scale(deviceType: Int, channel: Int) -> Double? {
        switch (deviceType, channel) {
        case (1, 2): 0.001  // millimetres
        case (1, 4), (1, 5), (1, 6), (1, 46), (1, 30007): 0.001
        case (1, 30002), (1, 30003): 1
        case (2, 2), (3, 2): 0.001
        case (2, _): 0.0001  // accelerometer, G × 10⁴
        case (3, _): 0.001  // gyro, deg/s × 10³
        default: nil
        }
    }

    /// Reads every channel stream the archive holds, grouped by the device that wrote it.
    static func streams(in archive: ZipArchive, devices: [Int: Int]) -> [Stream] {
        var byDevice: [String: Stream] = [:]
        var order: [String] = []
        var canValues: [String: [Double]] = [:]

        for entry in archive.entries {
            guard let parsed = Name(entry.name) else { continue }
            let deviceType = devices[parsed.deviceID] ?? parsed.deviceType
            let key = parsed.canID.map { "\(parsed.deviceID)/\($0)" } ?? "\(parsed.deviceID)"
            guard let data = try? archive.contents(of: entry) else { continue }

            // `channel2_…` holds a CAN channel's values, as float64.
            if parsed.isValues {
                canValues[key] = Self.doubles(data)
                continue
            }
            if byDevice[key] == nil {
                byDevice[key] = Stream(
                    deviceID: parsed.deviceID, deviceType: deviceType, canID: parsed.canID, timestamps: [])
                order.append(key)
            }
            switch parsed.channel {
            case 1:
                byDevice[key]?.timestamps = Self.int64s(data)
            case 2 where parsed.canID == nil:
                // Distance travelled, as int64 millimetres rather than one of the int32 scalars.
                // A CAN stream has one too, but it only repeats the GPS device's, sampled on the
                // CAN channel's clock — keeping it would give every CAN channel a twin.
                byDevice[key]?.values[2] = Self.int64s(data).map { Double($0) / 1000 }
            case 3 where deviceType == 1:
                byDevice[key]?.positions = Self.positions(data)
            default:
                guard let factor = Self.scale(deviceType: deviceType, channel: parsed.channel) else { continue }
                byDevice[key]?.values[parsed.channel] = Self.int32s(data).map { Double($0) * factor }
            }
        }

        // A CAN stream's timestamps come from its `…_1_1` member and its values from `channel2_…`.
        for (key, values) in canValues {
            guard var stream = byDevice[key], let id = stream.canID else { continue }
            stream.values[id] = values
            byDevice[key] = stream
        }
        return order.compactMap { byDevice[$0] }.filter { !$0.timestamps.isEmpty }
    }

    /// `channel_<deviceType>_<deviceId>_<canId>_<channelId>_<kind>`, and `channel2_…` for the
    /// values of a CAN channel.
    struct Name {
        var deviceType: Int
        var deviceID: Int
        var canID: Int?
        var channel: Int
        var isValues: Bool

        init?(_ name: String) {
            let isValues = name.hasPrefix("channel2_")
            guard isValues || name.hasPrefix("channel_") else { return nil }
            let parts = name.split(separator: "_").dropFirst().map(String.init)
            guard parts.count == 5, let type = Int(parts[0]), let device = Int(parts[1]),
                let third = Int(parts[2]), let channel = Int(parts[3])
            else { return nil }
            self.deviceType = type
            self.deviceID = device
            // The third field is the CAN channel id and is zero for the GPS and IMU devices, whose
            // channels all share one axis.
            self.canID = third == 0 ? nil : third
            self.channel = channel
            self.isValues = isValues
        }
    }

    // MARK: - Fixed-width readers

    static func int64s(_ data: Data) -> [Int64] {
        data.withUnsafeBytes { raw in
            let count = raw.count / 8
            return (0..<count).map { Int64(littleEndian: raw.loadUnaligned(fromByteOffset: $0 * 8, as: Int64.self)) }
        }
    }

    static func int32s(_ data: Data) -> [Int32] {
        data.withUnsafeBytes { raw in
            let count = raw.count / 4
            return (0..<count).map { Int32(littleEndian: raw.loadUnaligned(fromByteOffset: $0 * 4, as: Int32.self)) }
        }
    }

    static func doubles(_ data: Data) -> [Double] {
        data.withUnsafeBytes { raw in
            let count = raw.count / 8
            return (0..<count).map {
                Double(bitPattern: UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: $0 * 8, as: UInt64.self)))
            }
        }
    }

    /// Latitude and longitude as an `int32` pair over 6,000,000 — degrees × 60 × 10⁵, which is
    /// minutes rather than the 1e7 most formats use. Cross-checked against `firstPositionLatitude`
    /// in `session.json` and against the CSV export of the same session.
    static func positions(_ data: Data) -> [Position] {
        let pairs = int32s(data)
        return stride(from: 0, to: pairs.count - 1, by: 2).map {
            Position(latitude: Double(pairs[$0]) / 6_000_000, longitude: Double(pairs[$0 + 1]) / 6_000_000)
        }
    }

    struct Position {
        var latitude: Double
        var longitude: Double
    }
}
