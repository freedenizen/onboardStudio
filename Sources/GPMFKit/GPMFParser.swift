import Foundation

/// One GPMF key-length-value item. Nested items (type 0) carry children; leaves carry a typed
/// payload of `repeatCount` samples of `sampleSize` bytes each, big-endian.
public struct GPMFItem: Sendable {
    public let key: String
    /// The type character (`0` for nested), e.g. `l` int32, `f` float, `c` string, `?` complex.
    public let type: UInt8
    public let sampleSize: Int
    public let repeatCount: Int
    public let payload: Data
    public let children: [GPMFItem]

    public var isNested: Bool { type == 0 }

    /// First child with `key`.
    public subscript(key: String) -> GPMFItem? { children.first { $0.key == key } }

    /// All children with `key`.
    public func all(_ key: String) -> [GPMFItem] { children.filter { $0.key == key } }

    /// The payload as a string (type `c`, NUL padded).
    public var string: String? {
        guard type == UInt8(ascii: "c") || type == UInt8(ascii: "F") else { return nil }
        return String(bytes: payload.prefix { $0 != 0 }, encoding: .utf8)
    }

    /// Every scalar in the payload as `Double`, in order, for the simple numeric types.
    public var numbers: [Double] {
        GPMFParser.decodeNumbers(payload, type: type, sampleSize: sampleSize)
    }

    /// The payload decoded as rows of a complex type (`?`), using the sibling `TYPE` string.
    public func rows(typeString: String) -> [[Double]] {
        GPMFParser.decodeComplex(payload, typeString: typeString, sampleSize: sampleSize, repeatCount: repeatCount)
    }
}

public enum GPMFParser {
    /// Parses a payload (one metadata track sample) into its top-level items.
    public static func parse(_ data: Data) -> [GPMFItem] {
        parseItems(data, from: data.startIndex, to: data.endIndex)
    }

    static func parseItems(_ data: Data, from start: Int, to end: Int) -> [GPMFItem] {
        var items: [GPMFItem] = []
        var i = start
        while i + 8 <= end {
            let key = String(bytes: data[i..<i + 4], encoding: .isoLatin1) ?? ""
            let type = data[i + 4]
            let size = Int(data[i + 5])
            let repeatCount = Int(data[i + 6]) << 8 | Int(data[i + 7])
            let length = size * repeatCount
            let padded = (length + 3) & ~3
            let payloadStart = i + 8
            guard payloadStart + length <= end, key.allSatisfy({ $0.isASCII && !$0.isWhitespace }) else { break }
            let payload = data.subdata(in: payloadStart..<payloadStart + length)
            let children = type == 0 ? parseItems(data, from: payloadStart, to: payloadStart + length) : []
            items.append(
                GPMFItem(
                    key: key, type: type, sampleSize: size, repeatCount: repeatCount, payload: payload,
                    children: children))
            i = payloadStart + padded
        }
        return items
    }

    /// Byte width of a type character, or nil for strings/complex/unknown.
    static func width(of type: UInt8) -> Int? {
        switch type {
        case UInt8(ascii: "b"), UInt8(ascii: "B"): 1
        case UInt8(ascii: "s"), UInt8(ascii: "S"): 2
        case UInt8(ascii: "l"), UInt8(ascii: "L"), UInt8(ascii: "f"): 4
        case UInt8(ascii: "j"), UInt8(ascii: "J"), UInt8(ascii: "d"): 8
        default: nil
        }
    }

    static func decodeNumbers(_ data: Data, type: UInt8, sampleSize: Int) -> [Double] {
        guard let width = width(of: type), width > 0 else { return [] }
        var result: [Double] = []
        result.reserveCapacity(data.count / width)
        var offset = data.startIndex
        while offset + width <= data.endIndex {
            result.append(scalar(data, at: offset, type: type))
            offset += width
        }
        return result
    }

    static func decodeComplex(_ data: Data, typeString: String, sampleSize: Int, repeatCount: Int) -> [[Double]] {
        let types = Array(typeString.utf8)
        var rows: [[Double]] = []
        var offset = data.startIndex
        for _ in 0..<repeatCount {
            var row: [Double] = []
            var cursor = offset
            for t in types {
                guard let width = width(of: t), cursor + width <= data.endIndex else { break }
                row.append(scalar(data, at: cursor, type: t))
                cursor += width
            }
            rows.append(row)
            offset += sampleSize
            if offset > data.endIndex { break }
        }
        return rows
    }

    static func scalar(_ data: Data, at offset: Int, type: UInt8) -> Double {
        func be(_ count: Int) -> UInt64 {
            var value: UInt64 = 0
            for k in 0..<count { value = value << 8 | UInt64(data[offset + k]) }
            return value
        }
        switch type {
        case UInt8(ascii: "b"): return Double(Int8(bitPattern: UInt8(be(1))))
        case UInt8(ascii: "B"): return Double(be(1))
        case UInt8(ascii: "s"): return Double(Int16(bitPattern: UInt16(be(2))))
        case UInt8(ascii: "S"): return Double(be(2))
        case UInt8(ascii: "l"): return Double(Int32(bitPattern: UInt32(be(4))))
        case UInt8(ascii: "L"): return Double(be(4))
        case UInt8(ascii: "f"): return Double(Float(bitPattern: UInt32(be(4))))
        case UInt8(ascii: "j"): return Double(Int64(bitPattern: be(8)))
        case UInt8(ascii: "J"): return Double(be(8))
        case UInt8(ascii: "d"): return Double(bitPattern: be(8))
        default: return 0
        }
    }

    /// Parses a `U` UTC item (`yymmddhhmmss.sss`) into seconds since 1970.
    public static func utcSeconds(_ text: String) -> Double? {
        let digits = text.trimmingCharacters(in: .whitespaces)
        guard digits.count >= 12, let year = Int(digits.prefix(2)), let month = Int(digits.dropFirst(2).prefix(2)),
            let day = Int(digits.dropFirst(4).prefix(2)), let hour = Int(digits.dropFirst(6).prefix(2)),
            let minute = Int(digits.dropFirst(8).prefix(2)), let second = Double(digits.dropFirst(10))
        else { return nil }
        var components = DateComponents()
        components.year = 2000 + year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = 0
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        guard let date = calendar.date(from: components) else { return nil }
        return date.timeIntervalSince1970 + second
    }
}
