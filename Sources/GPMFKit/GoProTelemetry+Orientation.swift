import Foundation
import TelemetryKit

// The camera's orientation record and what the recording's settings say about its lens (#262).
extension GoProTelemetry {
    /// The camera's orientation through the recording (#262): CORI, and IORI where the camera
    /// stabilised in-camera. `nil` when the file carries neither (HERO7 and earlier, most others).
    public static func orientation(of url: URL) throws -> CameraOrientationTrack? {
        let track = try MP4Boxes.trackSamples("gpmd", in: url)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var payloads: [Payload] = []
        payloads.reserveCapacity(track.count)
        for index in 0..<track.count {
            let data = try MP4Boxes.sampleData(track, index: index, in: handle)
            let streams = extract(GPMFParser.parse(data)).0.filter { $0.key == "CORI" || $0.key == "IORI" }
            payloads.append(Payload(time: track.times[index], duration: track.durations[index], streams: streams))
        }
        guard var result = orientation(from: payloads) else { return nil }
        let settings = try MP4Boxes.userData("GPMF", in: url).map { GPMFParser.parse($0) } ?? []
        let lens = lens(from: settings)
        result.focalLength = lens.focalLength
        result.stabilisedInCamera = lens.stabilised
        return result.onFrameTimes()
    }

    /// What a recording's settings (`moov/udta/GPMF`) say about the picture: the lens's
    /// magnification at the centre, from its polynomial (`POLY`, the angle-to-radius slope at the
    /// centre) scaled by `ZMPL` and taken across half the frame height; and whether HyperSmooth ran
    /// (`EISE`). Measured on a HERO13, the slope agrees with the picture's own motion to within 10 %.
    static func lens(from items: [GPMFItem]) -> (focalLength: Double?, stabilised: Bool) {
        func find(_ key: String, in items: [GPMFItem]) -> GPMFItem? {
            for item in items {
                if item.key == key { return item }
                if let found = find(key, in: item.children) { return found }
            }
            return nil
        }
        let stabilised = find("EISE", in: items)?.string?.uppercased().hasPrefix("Y") ?? false
        guard let poly = find("POLY", in: items)?.numbers, poly.count > 1, poly[1] > 0,
            let zoom = find("ZMPL", in: items)?.numbers.first, zoom > 0
        else { return (nil, stabilised) }
        return (poly[1] * zoom / 2, stabilised)
    }

    static func orientation(from payloads: [Payload]) -> CameraOrientationTrack? {
        var times: [Double] = []
        var camera: [Quaternion] = []
        var image: [Quaternion] = []
        for (payloadIndex, payload) in payloads.enumerated() {
            // CORI and IORI come in the same payloads, one row per frame; they are paired by index.
            guard let cori = payload.streams.first(where: { $0.key == "CORI" }) else { continue }
            let iori = payload.streams.first { $0.key == "IORI" }
            let nextStart =
                payloadIndex + 1 < payloads.count
                ? payloads[payloadIndex + 1].streams.first { $0.key == "CORI" }?.startMicros.map { $0 / 1_000_000 }
                : nil
            for (index, raw) in cori.rows.enumerated() {
                let row = scaled(raw, by: cori.scale)
                guard row.count >= 4 else { continue }
                times.append(sampleTime(payload: payload, stream: cori, index: index, nextStart: nextStart))
                camera.append(Quaternion(w: row[0], x: row[1], y: row[2], z: row[3]).normalized)
                if let iori, index < iori.rows.count {
                    let r = scaled(iori.rows[index], by: iori.scale)
                    image.append(r.count >= 4 ? Quaternion(w: r[0], x: r[1], y: r[2], z: r[3]).normalized : .identity)
                } else {
                    image.append(.identity)
                }
            }
        }
        guard !times.isEmpty else { return nil }
        return CameraOrientationTrack(times: times, camera: camera, image: image)
    }
}

extension CameraOrientationTrack {
    /// The track with sample `k` at the time of frame `k` of its own file.
    ///
    /// GoPro writes exactly one CORI sample per frame (92,160 for the 92,160 frames of a 12:48 HERO13
    /// file), but their `STMP` times count from the start of the *recording*: the second chapter's
    /// samples start at 768.8 s although its frames start at 0. Frame numbers are the one clock both
    /// share. Measured against them the samples line up with their frames to within a third of a
    /// frame, so no lag is kept.
    func onFrameTimes() -> CameraOrientationTrack {
        guard times.count > 1, let first = times.first, let last = times.last, last > first else { return self }
        let frame = (last - first) / Double(times.count - 1)
        var result = self
        result.times = times.indices.map { Double($0) * frame }
        result.lag = 0
        return result
    }
}
