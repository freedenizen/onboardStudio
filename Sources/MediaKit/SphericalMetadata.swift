import Foundation

/// Marks an MP4/MOV as a 360° equirectangular video by inserting Google's Spherical Video V1
/// `uuid` box into the video track, which YouTube, QuickTime-based and most other players read.
/// The box is added by rewriting `moov`; when `moov` precedes `mdat` (as `AVAssetWriter` writes
/// it) every chunk offset that points past it is shifted by the inserted size.
public enum SphericalMetadata {
    /// The Spherical Video V1 box UUID (ffcc8263-f855-4a93-8814-587a02521fdd).
    static let boxUUID: [UInt8] = [
        0xff, 0xcc, 0x82, 0x63, 0xf8, 0x55, 0x4a, 0x93, 0x88, 0x14, 0x58, 0x7a, 0x02, 0x52, 0x1f, 0xdd,
    ]

    public enum InjectError: Error, CustomStringConvertible {
        case notAnMP4(URL)
        case noVideoTrack(URL)
        case malformed(String)

        public var description: String {
            switch self {
            case .notAnMP4(let url): "\(url.lastPathComponent) is not an MP4/MOV file."
            case .noVideoTrack(let url): "\(url.lastPathComponent) has no video track to tag."
            case .malformed(let why): "Malformed MP4: \(why)"
            }
        }
    }

    static func xml(software: String) -> Data {
        let text = """
            <?xml version="1.0"?><rdf:SphericalVideo xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" \
            xmlns:GSpherical="http://ns.google.com/videos/1.0/spherical/"><GSpherical:Spherical>true\
            </GSpherical:Spherical><GSpherical:Stitched>true</GSpherical:Stitched><GSpherical:StitchingSoftware>\
            \(software)</GSpherical:StitchingSoftware><GSpherical:ProjectionType>equirectangular\
            </GSpherical:ProjectionType></rdf:SphericalVideo>
            """
        return Data(text.utf8)
    }

    static func uuidBox(software: String) -> Data {
        let payload = xml(software: software)
        var box = Data()
        box.append(be32(UInt32(8 + boxUUID.count + payload.count)))
        box.append(contentsOf: Array("uuid".utf8))
        box.append(contentsOf: boxUUID)
        box.append(payload)
        return box
    }

    /// Whether the first video track already carries the spherical box.
    public static func isSpherical(_ url: URL) throws -> Bool {
        let file = try TopLevel.read(url)
        return try videoTrack(in: file.moov).map { hasSphericalBox(in: file.moov, trak: $0) } ?? false
    }

    /// Inserts the spherical box into the first video track of `url` in place. Returns `false`
    /// (and leaves the file alone) when it is already tagged.
    @discardableResult
    public static func inject(into url: URL, software: String = "Onboard Studio") throws -> Bool {
        let file = try TopLevel.read(url)
        guard let trak = try videoTrack(in: file.moov) else { throw InjectError.noVideoTrack(url) }
        if hasSphericalBox(in: file.moov, trak: trak) { return false }
        let insert = uuidBox(software: software)
        let delta = UInt64(insert.count)
        let newMoovPayload = rewrite(
            file.moov, range: 0..<file.moov.count,
            edit: Edit(insert: insert, target: trak, shiftFrom: file.moovStart, delta: delta))
        var newMoov = Data()
        newMoov.append(be32(UInt32(8 + newMoovPayload.count)))
        newMoov.append(contentsOf: Array("moov".utf8))
        newMoov.append(newMoovPayload)

        let temporary = url.deletingLastPathComponent().appending(path: ".\(url.lastPathComponent).spherical")
        try? FileManager.default.removeItem(at: temporary)
        FileManager.default.createFile(atPath: temporary.path, contents: nil)
        let reader = try FileHandle(forReadingFrom: url)
        let writer = try FileHandle(forWritingTo: temporary)
        defer {
            try? reader.close()
            try? writer.close()
        }
        try copy(from: reader, to: writer, range: 0..<file.moovStart)
        try writer.write(contentsOf: newMoov)
        try copy(from: reader, to: writer, range: file.moovEnd..<file.size)
        try writer.close()
        try reader.close()
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
        return true
    }

    // MARK: - Boxes in memory

    struct Box {
        let type: String
        /// Whole box, header included, as a range in the parent data.
        let range: Range<Int>
        let payload: Range<Int>
    }

    static func boxes(in data: Data, range: Range<Int>) -> [Box] {
        var result: [Box] = []
        var position = range.lowerBound
        while position + 8 <= range.upperBound {
            var size = Int(be32(data, position))
            let type =
                String(
                    bytes: data[data.startIndex + position + 4..<data.startIndex + position + 8], encoding: .isoLatin1)
                ?? "????"
            var headerSize = 8
            if size == 1, position + 16 <= range.upperBound {
                size = Int(be64(data, position + 8))
                headerSize = 16
            } else if size == 0 {
                size = range.upperBound - position
            }
            guard size >= headerSize, position + size <= range.upperBound else { break }
            result.append(
                Box(type: type, range: position..<position + size, payload: position + headerSize..<position + size))
            position += size
        }
        return result
    }

    static func child(_ type: String, of box: Box, in data: Data) -> Box? {
        boxes(in: data, range: box.payload).first { $0.type == type }
    }

    static func videoTrack(in moov: Data) throws -> Box? {
        for trak in boxes(in: moov, range: 0..<moov.count) where trak.type == "trak" {
            guard let mdia = child("mdia", of: trak, in: moov), let hdlr = child("hdlr", of: mdia, in: moov),
                hdlr.payload.count >= 12
            else { continue }
            let handler = String(
                bytes: moov[hdlr.payload.lowerBound + 8..<hdlr.payload.lowerBound + 12], encoding: .isoLatin1)
            if handler == "vide" { return trak }
        }
        return nil
    }

    static func hasSphericalBox(in moov: Data, trak: Box) -> Bool {
        boxes(in: moov, range: trak.payload).contains { box in
            box.type == "uuid" && box.payload.count >= 16
                && Array(moov[box.payload.lowerBound..<box.payload.lowerBound + 16]) == boxUUID
        }
    }

    static let containers: Set<String> = ["trak", "mdia", "minf", "stbl"]

    /// What `rewrite` does to `moov`: append `insert` to the payload of `target` and shift chunk
    /// offsets at or beyond `shiftFrom` by `delta`.
    struct Edit {
        let insert: Data
        let target: Box
        let shiftFrom: UInt64
        let delta: UInt64
    }

    /// Copies the boxes in `range` applying `edit`. Box sizes are recomputed on the way out.
    static func rewrite(_ data: Data, range: Range<Int>, edit: Edit) -> Data {
        var out = Data()
        for box in boxes(in: data, range: range) {
            let isTarget = box.range == edit.target.range
            if containers.contains(box.type) {
                var payload = rewrite(data, range: box.payload, edit: edit)
                if isTarget { payload.append(edit.insert) }
                out.append(header(box.type, payloadSize: payload.count))
                out.append(payload)
            } else if box.type == "stco" || box.type == "co64" {
                out.append(header(box.type, payloadSize: box.payload.count))
                out.append(shiftedChunkOffsets(data, box: box, from: edit.shiftFrom, by: edit.delta))
            } else {
                out.append(data[data.startIndex + box.range.lowerBound..<data.startIndex + box.range.upperBound])
            }
        }
        return out
    }

    static func shiftedChunkOffsets(_ data: Data, box: Box, from shiftFrom: UInt64, by delta: UInt64) -> Data {
        var payload = Data(data[data.startIndex + box.payload.lowerBound..<data.startIndex + box.payload.upperBound])
        guard payload.count >= 8 else { return payload }
        let count = Int(be32(payload, 4))
        let wide = box.type == "co64"
        let entrySize = wide ? 8 : 4
        for index in 0..<count {
            let at = 8 + index * entrySize
            guard at + entrySize <= payload.count else { break }
            if wide {
                let value = be64(payload, at)
                if value >= shiftFrom { payload.replaceSubrange(at..<at + 8, with: be64Data(value + delta)) }
            } else {
                let value = UInt64(be32(payload, at))
                if value >= shiftFrom { payload.replaceSubrange(at..<at + 4, with: be32(UInt32(value + delta))) }
            }
        }
        return payload
    }

    static func header(_ type: String, payloadSize: Int) -> Data {
        var data = be32(UInt32(8 + payloadSize))
        data.append(contentsOf: Array(type.utf8))
        return data
    }

    // MARK: - File level

    struct TopLevel {
        let size: UInt64
        let moovStart: UInt64
        let moovEnd: UInt64
        let moov: Data

        static func read(_ url: URL) throws -> TopLevel {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let size = try handle.seekToEnd()
            var position: UInt64 = 0
            var sawFtyp = false
            while position + 8 <= size {
                try handle.seek(toOffset: position)
                guard let head = try handle.read(upToCount: 16), head.count >= 8 else { break }
                var boxSize = UInt64(be32(head, 0))
                let type = String(bytes: head[head.startIndex + 4..<head.startIndex + 8], encoding: .isoLatin1)
                var headerSize: UInt64 = 8
                if boxSize == 1, head.count >= 16 {
                    boxSize = be64(head, 8)
                    headerSize = 16
                } else if boxSize == 0 {
                    boxSize = size - position
                }
                guard boxSize >= headerSize, position + boxSize <= size else {
                    throw InjectError.malformed("box \(type ?? "?") overruns the file")
                }
                if type == "ftyp" { sawFtyp = true }
                if type == "moov" {
                    guard sawFtyp || position == 0 else { throw InjectError.notAnMP4(url) }
                    try handle.seek(toOffset: position + headerSize)
                    let payload = try handle.read(upToCount: Int(boxSize - headerSize)) ?? Data()
                    return TopLevel(size: size, moovStart: position, moovEnd: position + boxSize, moov: payload)
                }
                position += boxSize
            }
            throw sawFtyp ? InjectError.malformed("no moov box") : InjectError.notAnMP4(url)
        }
    }

    static func copy(from reader: FileHandle, to writer: FileHandle, range: Range<UInt64>) throws {
        guard range.upperBound > range.lowerBound else { return }
        try reader.seek(toOffset: range.lowerBound)
        var remaining = range.upperBound - range.lowerBound
        while remaining > 0 {
            let chunk = Int(min(remaining, 4 << 20))
            guard let data = try reader.read(upToCount: chunk), !data.isEmpty else {
                throw InjectError.malformed("unexpected end of file while copying")
            }
            try writer.write(contentsOf: data)
            remaining -= UInt64(data.count)
        }
    }

    // MARK: - Big-endian helpers

    static func be32(_ data: Data, _ offset: Int) -> UInt32 {
        let i = data.startIndex + offset
        return UInt32(data[i]) << 24 | UInt32(data[i + 1]) << 16 | UInt32(data[i + 2]) << 8 | UInt32(data[i + 3])
    }

    static func be64(_ data: Data, _ offset: Int) -> UInt64 {
        UInt64(be32(data, offset)) << 32 | UInt64(be32(data, offset + 4))
    }

    static func be32(_ value: UInt32) -> Data {
        Data([UInt8(value >> 24 & 0xff), UInt8(value >> 16 & 0xff), UInt8(value >> 8 & 0xff), UInt8(value & 0xff)])
    }

    static func be64Data(_ value: UInt64) -> Data {
        be32(UInt32(value >> 32)) + be32(UInt32(value & 0xffff_ffff))
    }
}
