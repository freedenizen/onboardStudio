import Foundation
import TelemetryKit

/// Garmin FIT activity files. Reads `record` messages (position, altitude, speed, distance,
/// heart rate, cadence, power, temperature) and `lap` messages; developer fields and everything
/// else are skipped. Times are seconds from the first record; `createdAt` holds the absolute start.
public struct FITImporter: TelemetryImporter {
    public static let id = "fit"
    public static let displayName = "Garmin FIT"
    public static let fileExtensions = ["fit"]

    public init() {}

    public static func confidence(for sniff: FileSniff) -> ImportConfidence {
        // Bytes 8–11 of the header spell ".FIT".
        if sniff.head.count >= 12, sniff.head.dropFirst(8).hasPrefix(".FIT") { return .certain }
        return fileExtensions.contains(sniff.fileExtension) ? .possible : .no
    }

    public func importFile(at url: URL) throws -> RawTable {
        let data = try Data(contentsOf: url)
        let decoded = try FITDecoder.decode(data)
        guard !decoded.records.isEmpty else { throw ImportError.noData }
        let origin = decoded.records[0].timestamp
        var times: [Double] = []
        var kept: [FITDecoder.Record] = []
        for record in decoded.records {
            let t = record.timestamp - origin
            if let last = times.last, t <= last { continue }
            times.append(t)
            kept.append(record)
        }
        func column(
            _ name: String, _ unit: TelemetryUnit, role: ChannelRole?, _ value: (FITDecoder.Record) -> Double?
        ) -> RawColumn? {
            let values = kept.map(value)
            guard values.contains(where: { $0 != nil }) else { return nil }
            return RawColumn(name: name, unit: unit, source: "fit", suggestedRole: role, values: values)
        }
        let columns: [RawColumn] = [
            column("Latitude", .degrees, role: .latitude) { $0.latitude },
            column("Longitude", .degrees, role: .longitude) { $0.longitude },
            column("Altitude", .meters, role: .altitude) { $0.altitude },
            column("Speed", .metersPerSecond, role: .speed) { $0.speed },
            column("Distance", .meters, role: .distance) { $0.distance },
            column("Heart rate", .custom("bpm"), role: .aux("heart_rate")) { $0.heartRate },
            column("Cadence", .rpm, role: .aux("cadence")) { $0.cadence },
            column("Power", .custom("W"), role: .aux("power")) { $0.power },
            column("Temperature", .celsius, role: .aux("temperature")) { $0.temperature },
        ].compactMap { $0 }
        var info = SessionInfo(sourceFormat: Self.displayName)
        info.createdAt = Date(timeIntervalSince1970: FITDecoder.epoch(origin))
        let markers = decoded.lapStarts.enumerated().compactMap { index, start -> RawLapMarker? in
            let t = start - origin
            guard t > 0, t < (times.last ?? 0) else { return nil }
            return RawLapMarker(number: index + 1, time: t)
        }
        return RawTable(info: info, times: times, columns: columns, lapMarkers: markers)
    }
}

/// A small decoder for the FIT binary container: definition and data messages, normal and
/// compressed-timestamp headers, both byte orders, developer fields skipped.
enum FITDecoder {
    struct Record {
        var timestamp: Double  // FIT seconds (since 1989-12-31)
        var latitude: Double?
        var longitude: Double?
        var altitude: Double?
        var speed: Double?
        var distance: Double?
        var heartRate: Double?
        var cadence: Double?
        var power: Double?
        var temperature: Double?
    }

    struct Decoded {
        var records: [Record] = []
        /// Lap start times in FIT seconds.
        var lapStarts: [Double] = []
    }

    struct FieldDefinition {
        let number: Int
        let size: Int
        let baseType: UInt8
    }

    struct MessageDefinition {
        let globalNumber: Int
        let littleEndian: Bool
        let fields: [FieldDefinition]
        let developerBytes: Int
        var size: Int { fields.reduce(0) { $0 + $1.size } + developerBytes }
    }

    static let fitEpoch = 631_065_600.0  // 1989-12-31T00:00:00Z

    static func epoch(_ fitSeconds: Double) -> Double { fitEpoch + fitSeconds }

    static func decode(_ data: Data) throws -> Decoded {
        guard data.count >= 14 else { throw ImportError.malformed("file too short for a FIT header") }
        let bytes = [UInt8](data)
        let headerSize = Int(bytes[0])
        guard headerSize >= 12, String(bytes: bytes[8..<12], encoding: .ascii) == ".FIT" else {
            throw ImportError.malformed("missing .FIT signature")
        }
        let dataSize = Int(le32(bytes, 4))
        let end = min(headerSize + dataSize, bytes.count)
        var definitions: [Int: MessageDefinition] = [:]
        var decoded = Decoded()
        var lastTimestamp = 0.0
        var offset = headerSize
        while offset < end {
            let header = bytes[offset]
            offset += 1
            if header & 0x80 != 0 {
                // Compressed timestamp header: local type in bits 5–6, 5-bit time offset.
                let local = Int((header >> 5) & 0x3)
                let timeOffset = Double(header & 0x1F)
                guard let definition = definitions[local] else { throw ImportError.malformed("data before definition") }
                var timestamp = (lastTimestamp - lastTimestamp.truncatingRemainder(dividingBy: 32)) + timeOffset
                if timestamp < lastTimestamp { timestamp += 32 }
                lastTimestamp = timestamp
                offset = try readData(bytes, at: offset, definition: definition, into: &decoded, last: &lastTimestamp)
                continue
            }
            let local = Int(header & 0x0F)
            if header & 0x40 != 0 {
                let (definition, next) = try readDefinition(bytes, at: offset, end: end, header: header)
                definitions[local] = definition
                offset = next
            } else {
                guard let definition = definitions[local] else { throw ImportError.malformed("data before definition") }
                offset = try readData(bytes, at: offset, definition: definition, into: &decoded, last: &lastTimestamp)
            }
        }
        return decoded
    }

    /// Parses a definition message; returns it with the offset of the next message.
    private static func readDefinition(_ bytes: [UInt8], at start: Int, end: Int, header: UInt8) throws
        -> (MessageDefinition, Int)
    {
        var offset = start
        guard offset + 5 <= end else { throw ImportError.malformed("truncated definition") }
        let littleEndian = bytes[offset + 1] == 0
        let global =
            littleEndian
            ? Int(bytes[offset + 2]) | Int(bytes[offset + 3]) << 8
            : Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
        let fieldCount = Int(bytes[offset + 4])
        offset += 5
        var fields: [FieldDefinition] = []
        for _ in 0..<fieldCount {
            guard offset + 3 <= end else { throw ImportError.malformed("truncated field definition") }
            fields.append(
                FieldDefinition(number: Int(bytes[offset]), size: Int(bytes[offset + 1]), baseType: bytes[offset + 2]))
            offset += 3
        }
        var developerBytes = 0
        if header & 0x20 != 0 {
            guard offset < end else { throw ImportError.malformed("truncated developer fields") }
            let count = Int(bytes[offset])
            offset += 1
            for _ in 0..<count {
                guard offset + 3 <= end else { throw ImportError.malformed("truncated developer field") }
                developerBytes += Int(bytes[offset + 1])
                offset += 3
            }
        }
        let definition = MessageDefinition(
            globalNumber: global, littleEndian: littleEndian, fields: fields, developerBytes: developerBytes)
        return (definition, offset)
    }

    /// Reads a data message. `last` carries the running timestamp: compressed-timestamp headers
    /// update it before calling, messages with a timestamp field overwrite it.
    private static func readData(
        _ bytes: [UInt8], at start: Int, definition: MessageDefinition, into decoded: inout Decoded, last: inout Double
    ) throws -> Int {
        guard start + definition.size <= bytes.count else { throw ImportError.malformed("truncated data message") }
        var values: [Int: Double] = [:]
        var offset = start
        for field in definition.fields {
            if let value = number(bytes, at: offset, field: field, littleEndian: definition.littleEndian) {
                values[field.number] = value
            }
            offset += field.size
        }
        offset += definition.developerBytes
        let stamp = values[253] ?? last
        last = stamp
        switch definition.globalNumber {
        case 20:  // record
            var record = Record(timestamp: stamp)
            record.latitude = values[0].map(semicircles)
            record.longitude = values[1].map(semicircles)
            record.altitude = values[78].map { $0 / 5 - 500 } ?? values[2].map { $0 / 5 - 500 }
            record.speed = values[73].map { $0 / 1000 } ?? values[6].map { $0 / 1000 }
            record.distance = values[5].map { $0 / 100 }
            record.heartRate = values[3]
            record.cadence = values[4]
            record.power = values[7]
            record.temperature = values[13]
            decoded.records.append(record)
        case 19:  // lap
            if let startTime = values[2] { decoded.lapStarts.append(startTime) }
        default:
            break
        }
        return offset
    }

    static func semicircles(_ value: Double) -> Double { value * 180 / 2_147_483_648 }

    /// Reads a numeric field, returning nil for the base type's "invalid" value.
    static func number(_ bytes: [UInt8], at offset: Int, field: FieldDefinition, littleEndian: Bool) -> Double? {
        let type = field.baseType & 0x1F
        var raw: UInt64 = 0
        let width = min(field.size, 8)
        for k in 0..<width {
            let byte = UInt64(bytes[offset + k])
            raw |= littleEndian ? byte << (8 * UInt64(k)) : byte << (8 * UInt64(width - 1 - k))
        }
        switch type {
        case 0x00, 0x02, 0x0A, 0x0D:  // enum, uint8, uint8z, byte
            return raw == 0xFF ? nil : Double(raw)
        case 0x01:  // sint8
            return raw == 0x7F ? nil : Double(Int8(bitPattern: UInt8(raw & 0xFF)))
        case 0x03:  // sint16
            return raw == 0x7FFF ? nil : Double(Int16(bitPattern: UInt16(raw & 0xFFFF)))
        case 0x04, 0x0B:  // uint16, uint16z
            return raw == 0xFFFF ? nil : Double(raw)
        case 0x05:  // sint32
            return raw == 0x7FFF_FFFF ? nil : Double(Int32(bitPattern: UInt32(raw & 0xFFFF_FFFF)))
        case 0x06, 0x0C:  // uint32, uint32z
            return raw == 0xFFFF_FFFF ? nil : Double(raw)
        case 0x08:  // float32
            return Double(Float(bitPattern: UInt32(raw & 0xFFFF_FFFF)))
        case 0x09:  // float64
            return Double(bitPattern: raw)
        case 0x0E:  // sint64
            return Double(Int64(bitPattern: raw))
        case 0x0F, 0x10:  // uint64, uint64z
            return raw == UInt64.max ? nil : Double(raw)
        default:  // strings and unknown types
            return nil
        }
    }

    static func le32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(
            bytes[offset + 3]) << 24
    }
}
