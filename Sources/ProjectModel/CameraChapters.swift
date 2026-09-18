import Foundation

/// Cameras split long recordings into numbered chapter files; this finds the files that follow a
/// given one so they can be added as one continuous video.
public enum CameraChapters {
    /// Chapter files after `url` in the same directory, in playback order. Understands GoPro's
    /// `GX01ABCD` / `GH01ABCD` / `GL01ABCD` (chapter number is the two digits after the prefix),
    /// the older `GOPR1234` → `GP011234` scheme, DJI's `_001` suffix and Sony/Insta360-style
    /// `..._1`, `..._2` numbering.
    public static func following(
        _ url: URL, fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    )
        -> [URL]
    {
        var found: [URL] = []
        var candidate = next(after: url)
        var guardCount = 0
        while let next = candidate, fileExists(next), guardCount < 999 {
            found.append(next)
            candidate = Self.next(after: next)
            guardCount += 1
        }
        return found
    }

    /// The file name a camera would give the chapter after `url`, or `nil` for unknown schemes.
    public static func next(after url: URL) -> URL? {
        let name = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let directory = url.deletingLastPathComponent()
        func sibling(_ base: String) -> URL { directory.appending(path: base).appendingPathExtension(ext) }
        let upper = name.uppercased()
        // GoPro HERO6+: G[XHL]ccnnnn — cc is the chapter (01…99), nnnn the recording.
        if upper.count == 8, upper.hasPrefix("G"), "XHL".contains(upper[upper.index(after: upper.startIndex)]),
            let chapter = Int(upper.dropFirst(2).prefix(2)), upper.dropFirst(4).allSatisfy(\.isNumber)
        {
            let prefix = String(name.prefix(2))
            return sibling(prefix + String(format: "%02d", chapter + 1) + String(name.dropFirst(4)))
        }
        // Older GoPro: GOPRnnnn is chapter 1, then GP01nnnn, GP02nnnn, …
        if upper.count == 8, upper.hasPrefix("GOPR"), upper.dropFirst(4).allSatisfy(\.isNumber) {
            return sibling("GP01" + String(name.dropFirst(4)))
        }
        if upper.count == 8, upper.hasPrefix("GP"), let chapter = Int(upper.dropFirst(2).prefix(2)),
            upper.dropFirst(4).allSatisfy(\.isNumber)
        {
            return sibling("GP" + String(format: "%02d", chapter + 1) + String(name.dropFirst(4)))
        }
        // A trailing _NNN or _N counter (DJI, Sony, Insta360 exports).
        if let underscore = name.lastIndex(of: "_") {
            let digits = name[name.index(after: underscore)...]
            if !digits.isEmpty, digits.allSatisfy(\.isNumber), let number = Int(digits) {
                let width = digits.count
                return sibling(String(name[...underscore]) + String(format: "%0\(width)d", number + 1))
            }
        }
        return nil
    }
}
