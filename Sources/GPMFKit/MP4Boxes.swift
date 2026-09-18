import Foundation

/// Just enough of the ISO base media (MP4/MOV) container to find a track by its sample
/// description type and pull its samples out of `mdat`. AVFoundation does not expose GoPro's
/// `gpmd` metadata track at all, so this reads the tables directly and never loads the whole file.
public enum MP4Boxes {
    public enum ReadError: Error, CustomStringConvertible {
        case notAnMP4(URL)
        case noTrack(String, URL)
        case malformed(String)

        public var description: String {
            switch self {
            case .notAnMP4(let url): "\(url.lastPathComponent) is not an MP4/MOV file."
            case .noTrack(let type, let url): "\(url.lastPathComponent) has no '\(type)' track."
            case .malformed(let why): "Malformed MP4: \(why)"
            }
        }
    }

    /// One track's samples: presentation times in seconds and where the bytes live.
    public struct TrackSamples: Sendable {
        public let timescale: Int
        /// Decode/presentation time of each sample in seconds (from `stts`).
        public let times: [Double]
        /// Duration of each sample in seconds.
        public let durations: [Double]
        public let sizes: [Int]
        public let offsets: [UInt64]
        public var count: Int { sizes.count }
    }

    struct Box {
        let type: String
        let start: UInt64  // first byte of the payload
        let end: UInt64  // one past the last byte
    }

    /// Whether the file has a track whose sample description is `sampleType` (e.g. `gpmd`).
    public static func hasTrack(_ sampleType: String, in url: URL) -> Bool {
        (try? trackSamples(sampleType, in: url)) != nil
    }

    /// Locates the first track with sample description `sampleType` and reads its sample tables.
    public static func trackSamples(_ sampleType: String, in url: URL) throws -> TrackSamples {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        let top = try boxes(in: handle, from: 0, to: size)
        guard top.contains(where: { $0.type == "ftyp" }) || top.contains(where: { $0.type == "moov" }) else {
            throw ReadError.notAnMP4(url)
        }
        guard let moov = top.first(where: { $0.type == "moov" }) else { throw ReadError.malformed("no moov") }
        for trak in try boxes(in: handle, from: moov.start, to: moov.end) where trak.type == "trak" {
            guard let mdia = try child("mdia", of: trak, in: handle),
                let minf = try child("minf", of: mdia, in: handle),
                let stbl = try child("stbl", of: minf, in: handle),
                let stsd = try child("stsd", of: stbl, in: handle)
            else { continue }
            // stsd: version/flags(4) entryCount(4) then entries: size(4) type(4) …
            let entryType = try string(at: stsd.start + 12, in: handle)
            guard entryType == sampleType else { continue }
            guard let mdhd = try child("mdhd", of: mdia, in: handle) else { throw ReadError.malformed("no mdhd") }
            let version = try bytes(at: mdhd.start, count: 1, in: handle)[0]
            let timescale = Int(try uint32(at: mdhd.start + (version == 1 ? 20 : 12), in: handle))
            return try samples(stbl: stbl, timescale: timescale, in: handle)
        }
        throw ReadError.noTrack(sampleType, url)
    }

    /// Reads one sample's bytes.
    public static func sampleData(_ track: TrackSamples, index: Int, in handle: FileHandle) throws -> Data {
        try handle.seek(toOffset: track.offsets[index])
        return try handle.read(upToCount: track.sizes[index]) ?? Data()
    }

    // MARK: - Tables

    private static func samples(stbl: Box, timescale: Int, in handle: FileHandle) throws -> TrackSamples {
        guard let stsz = try child("stsz", of: stbl, in: handle), let stts = try child("stts", of: stbl, in: handle),
            let stsc = try child("stsc", of: stbl, in: handle)
        else { throw ReadError.malformed("missing sample tables") }
        let chunkBox = try child("co64", of: stbl, in: handle) ?? child("stco", of: stbl, in: handle)
        guard let chunkBox else { throw ReadError.malformed("missing chunk offsets") }

        // Sizes.
        let uniform = try uint32(at: stsz.start + 4, in: handle)
        let sampleCount = Int(try uint32(at: stsz.start + 8, in: handle))
        var sizes: [Int] = []
        if uniform != 0 {
            sizes = Array(repeating: Int(uniform), count: sampleCount)
        } else {
            let raw = try bytes(at: stsz.start + 12, count: sampleCount * 4, in: handle)
            sizes = (0..<sampleCount).map { Int(be32(raw, $0 * 4)) }
        }

        // Chunk offsets.
        let chunkCount = Int(try uint32(at: chunkBox.start + 4, in: handle))
        let wide = chunkBox.type == "co64"
        let rawOffsets = try bytes(at: chunkBox.start + 8, count: chunkCount * (wide ? 8 : 4), in: handle)
        let chunkOffsets: [UInt64] = (0..<chunkCount).map {
            wide ? be64(rawOffsets, $0 * 8) : UInt64(be32(rawOffsets, $0 * 4))
        }

        // Samples per chunk (stsc runs).
        let runCount = Int(try uint32(at: stsc.start + 4, in: handle))
        let rawRuns = try bytes(at: stsc.start + 8, count: runCount * 12, in: handle)
        var runs: [(firstChunk: Int, samplesPerChunk: Int)] = []
        for run in 0..<runCount {
            runs.append((Int(be32(rawRuns, run * 12)), Int(be32(rawRuns, run * 12 + 4))))
        }
        var offsets: [UInt64] = []
        offsets.reserveCapacity(sampleCount)
        var sampleIndex = 0
        for (chunkIndex, chunkStart) in chunkOffsets.enumerated() {
            let chunkNumber = chunkIndex + 1
            let perChunk = runs.last { $0.firstChunk <= chunkNumber }?.samplesPerChunk ?? 1
            var offset = chunkStart
            for _ in 0..<perChunk where sampleIndex < sampleCount {
                offsets.append(offset)
                offset += UInt64(sizes[sampleIndex])
                sampleIndex += 1
            }
        }
        guard offsets.count == sampleCount else { throw ReadError.malformed("chunk table does not cover all samples") }

        // Timing.
        let entryCount = Int(try uint32(at: stts.start + 4, in: handle))
        let rawTimes = try bytes(at: stts.start + 8, count: entryCount * 8, in: handle)
        var times: [Double] = []
        var durations: [Double] = []
        var clock = 0.0
        for entry in 0..<entryCount {
            let count = Int(be32(rawTimes, entry * 8))
            let delta = Double(be32(rawTimes, entry * 8 + 4)) / Double(max(timescale, 1))
            for _ in 0..<count where times.count < sampleCount {
                times.append(clock)
                durations.append(delta)
                clock += delta
            }
        }
        while times.count < sampleCount {
            times.append(clock)
            durations.append(durations.last ?? 1)
            clock += durations.last ?? 1
        }
        return TrackSamples(timescale: timescale, times: times, durations: durations, sizes: sizes, offsets: offsets)
    }

    // MARK: - Box walking

    static func boxes(in handle: FileHandle, from start: UInt64, to end: UInt64) throws -> [Box] {
        var result: [Box] = []
        var position = start
        while position + 8 <= end {
            let header = try bytes(at: position, count: 8, in: handle)
            var size = UInt64(be32(header, 0))
            let type = String(bytes: header[4..<8], encoding: .isoLatin1) ?? "????"
            var headerSize: UInt64 = 8
            if size == 1 {
                size = be64(try bytes(at: position + 8, count: 8, in: handle), 0)
                headerSize = 16
            } else if size == 0 {
                size = end - position
            }
            guard size >= headerSize, position + size <= end else { throw ReadError.malformed("box \(type) overruns") }
            result.append(Box(type: type, start: position + headerSize, end: position + size))
            position += size
        }
        return result
    }

    private static func child(_ type: String, of box: Box, in handle: FileHandle) throws -> Box? {
        try boxes(in: handle, from: box.start, to: box.end).first { $0.type == type }
    }

    private static func bytes(at offset: UInt64, count: Int, in handle: FileHandle) throws -> Data {
        try handle.seek(toOffset: offset)
        let data = try handle.read(upToCount: count) ?? Data()
        guard data.count == count else { throw ReadError.malformed("unexpected end of file") }
        return data
    }

    private static func uint32(at offset: UInt64, in handle: FileHandle) throws -> UInt32 {
        be32(try bytes(at: offset, count: 4, in: handle), 0)
    }

    private static func string(at offset: UInt64, in handle: FileHandle) throws -> String {
        String(bytes: try bytes(at: offset, count: 4, in: handle), encoding: .isoLatin1) ?? "????"
    }

    static func be32(_ data: Data, _ offset: Int) -> UInt32 {
        let i = data.startIndex + offset
        return UInt32(data[i]) << 24 | UInt32(data[i + 1]) << 16 | UInt32(data[i + 2]) << 8 | UInt32(data[i + 3])
    }

    static func be64(_ data: Data, _ offset: Int) -> UInt64 {
        UInt64(be32(data, offset)) << 32 | UInt64(be32(data, offset + 4))
    }
}
