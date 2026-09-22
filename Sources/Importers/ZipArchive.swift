import Compression
import Foundation

/// Just enough of the zip format to read the members of a RaceChrono `.rcz` (#68).
///
/// Hand-rolled because the only alternatives are a dependency or shelling out to `unzip`, and an
/// importer has to work headless with nothing installed. It reads the central directory, which is
/// the authoritative index, and inflates stored or deflated members.
///
/// Everything here is bounds-checked and throws rather than traps: the fuzz suite mutates every
/// fixture and feeds it back, so a truncated file or a length field claiming four gigabytes has to
/// come out as an error, not a crash.
struct ZipArchive {
    /// Members by name, in the order the central directory lists them.
    let entries: [Entry]

    struct Entry {
        let name: String
        /// Where the local header starts, from the beginning of the file.
        let localHeaderOffset: Int
        let compressedSize: Int
        let uncompressedSize: Int
        /// 0 = stored, 8 = deflate. Anything else is refused.
        let method: UInt16
    }

    enum Failure: Error, CustomStringConvertible {
        case notAZip
        case truncated
        case unsupportedCompression(UInt16)
        case corrupt(String)

        var description: String {
            switch self {
            case .notAZip: "Not a zip archive."
            case .truncated: "The archive ends in the middle of a record."
            case .unsupportedCompression(let method): "Unsupported zip compression method \(method)."
            case .corrupt(let what): "The archive is damaged: \(what)."
            }
        }
    }

    private let data: Data

    /// Upper bound on what a single member may inflate to. A zip bomb is a 4 KB file claiming to
    /// be a terabyte; refusing early is better than being killed by the allocator.
    private static let memberSizeLimit = 512 * 1024 * 1024

    init(data: Data) throws {
        self.data = data
        guard data.count >= 22 else { throw Failure.notAZip }
        let end = try Self.endOfCentralDirectory(in: data)
        var entries: [Entry] = []
        var offset = end.directoryOffset
        for _ in 0..<end.entryCount {
            guard let entry = try Self.readCentralEntry(in: data, at: &offset) else { break }
            entries.append(entry)
        }
        self.entries = entries
    }

    init(contentsOf url: URL) throws {
        try self.init(data: try Data(contentsOf: url, options: .mappedIfSafe))
    }

    /// The bytes of one member, inflating it if it was deflated. `nil` when there is no such member.
    func contents(of name: String) throws -> Data? {
        guard let entry = entries.first(where: { $0.name == name }) else { return nil }
        return try contents(of: entry)
    }

    func contents(of entry: Entry) throws -> Data {
        // The local header repeats the name and extra-field lengths, and only they are trustworthy
        // for finding where the data starts — the central directory's copies may differ.
        var offset = entry.localHeaderOffset
        guard try read32(&offset) == 0x0403_4B50 else { throw Failure.corrupt("local header") }
        offset = entry.localHeaderOffset + 26
        let nameLength = Int(try read16(&offset))
        let extraLength = Int(try read16(&offset))
        let start = entry.localHeaderOffset + 30 + nameLength + extraLength
        guard start >= 0, entry.compressedSize >= 0, start + entry.compressedSize <= data.count else {
            throw Failure.truncated
        }
        let payload = data.subdata(in: start..<(start + entry.compressedSize))
        switch entry.method {
        case 0: return payload
        case 8: return try Self.inflate(payload, expecting: entry.uncompressedSize)
        default: throw Failure.unsupportedCompression(entry.method)
        }
    }

    // MARK: - Reading

    private static func endOfCentralDirectory(in data: Data) throws -> (entryCount: Int, directoryOffset: Int) {
        // The record is at the end, but a comment of up to 64 KB may follow it, so scan backwards.
        let signature: UInt32 = 0x0605_4B50
        let lowest = max(0, data.count - 22 - 0xFFFF)
        var index = data.count - 22
        while index >= lowest {
            var offset = index
            if (try? read32(data, &offset)) == signature {
                var fields = index + 10
                let count = Int(try read16(data, &fields))
                fields = index + 16
                let directoryOffset = Int(try read32(data, &fields))
                guard directoryOffset >= 0, directoryOffset < data.count else { throw Failure.corrupt("directory") }
                // A count of tens of thousands is legitimate; one of millions is a damaged field.
                return (min(count, 100_000), directoryOffset)
            }
            index -= 1
        }
        throw Failure.notAZip
    }

    private static func readCentralEntry(in data: Data, at offset: inout Int) throws -> Entry? {
        let start = offset
        guard start + 46 <= data.count else { return nil }
        var cursor = start
        guard try read32(data, &cursor) == 0x0201_4B50 else { return nil }
        cursor = start + 10
        let method = try read16(data, &cursor)
        cursor = start + 20
        let compressed = Int(try read32(data, &cursor))
        let uncompressed = Int(try read32(data, &cursor))
        let nameLength = Int(try read16(data, &cursor))
        let extraLength = Int(try read16(data, &cursor))
        let commentLength = Int(try read16(data, &cursor))
        cursor = start + 42
        let localOffset = Int(try read32(data, &cursor))
        let nameStart = start + 46
        guard nameLength >= 0, nameStart + nameLength <= data.count else { return nil }
        let raw = data.subdata(in: nameStart..<(nameStart + nameLength))
        guard let name = String(bytes: raw, encoding: .utf8) else { return nil }
        offset = nameStart + nameLength + max(0, extraLength) + max(0, commentLength)
        guard localOffset >= 0, localOffset < data.count, compressed >= 0, uncompressed >= 0 else { return nil }
        return Entry(
            name: name, localHeaderOffset: localOffset, compressedSize: compressed,
            uncompressedSize: uncompressed, method: method)
    }

    private func read16(_ offset: inout Int) throws -> UInt16 { try Self.read16(data, &offset) }
    private func read32(_ offset: inout Int) throws -> UInt32 { try Self.read32(data, &offset) }

    private static func read16(_ data: Data, _ offset: inout Int) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= data.count else { throw Failure.truncated }
        defer { offset += 2 }
        return UInt16(data[data.startIndex + offset]) | UInt16(data[data.startIndex + offset + 1]) << 8
    }

    private static func read32(_ data: Data, _ offset: inout Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else { throw Failure.truncated }
        defer { offset += 4 }
        var value: UInt32 = 0
        for byte in 0..<4 { value |= UInt32(data[data.startIndex + offset + byte]) << (8 * byte) }
        return value
    }

    /// Raw deflate, which is what a zip member holds — no zlib header, so `COMPRESSION_ZLIB` is
    /// the right algorithm despite the name.
    private static func inflate(_ payload: Data, expecting size: Int) throws -> Data {
        guard size >= 0, size <= memberSizeLimit else { throw Failure.corrupt("declared size \(size)") }
        guard size > 0 else { return Data() }
        var output = Data(count: size)
        let written = output.withUnsafeMutableBytes { destination -> Int in
            payload.withUnsafeBytes { source -> Int in
                guard let destinationBase = destination.bindMemory(to: UInt8.self).baseAddress,
                    let sourceBase = source.bindMemory(to: UInt8.self).baseAddress
                else { return 0 }
                return compression_decode_buffer(
                    destinationBase, size, sourceBase, payload.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written == size else { throw Failure.corrupt("member did not inflate to its declared size") }
        return output
    }
}
