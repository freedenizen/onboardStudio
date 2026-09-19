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

    /// Groups a selection of files into recordings: each group starts with a file that is not the
    /// chapter after another selected file, followed by its selected chapters in order. Files the
    /// schemes do not recognise are groups of one. Groups keep the selection's order.
    public static func group(_ urls: [URL]) -> [[URL]] {
        let names = Set(urls.map(\.standardizedFileURL.path))
        var consumed = Set<String>()
        var groups: [[URL]] = []
        for url in urls {
            let path = url.standardizedFileURL.path
            guard !consumed.contains(path) else { continue }
            // Skip files that are chapters of another selected file; they join that group.
            if let previous = previousChapter(of: url), names.contains(previous.standardizedFileURL.path) { continue }
            var group = [url]
            consumed.insert(path)
            var candidate = next(after: url)
            while let next = candidate, names.contains(next.standardizedFileURL.path) {
                group.append(next)
                consumed.insert(next.standardizedFileURL.path)
                candidate = Self.next(after: next)
            }
            groups.append(group)
        }
        return groups
    }

    /// The chapter file that would precede `url`, when the name says it is not the first.
    public static func previousChapter(of url: URL) -> URL? {
        let name = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let directory = url.deletingLastPathComponent()
        func sibling(_ base: String) -> URL { directory.appending(path: base).appendingPathExtension(ext) }
        let upper = name.uppercased()
        if upper.count == 8, upper.hasPrefix("G"), "XHL".contains(upper[upper.index(after: upper.startIndex)]),
            let chapter = Int(upper.dropFirst(2).prefix(2)), chapter > 1, upper.dropFirst(4).allSatisfy(\.isNumber)
        {
            return sibling(String(name.prefix(2)) + String(format: "%02d", chapter - 1) + String(name.dropFirst(4)))
        }
        if upper.count == 8, upper.hasPrefix("GP"), let chapter = Int(upper.dropFirst(2).prefix(2)),
            upper.dropFirst(4).allSatisfy(\.isNumber)
        {
            return chapter > 1
                ? sibling("GP" + String(format: "%02d", chapter - 1) + String(name.dropFirst(4)))
                : sibling("GOPR" + String(name.dropFirst(4)))
        }
        if let underscore = name.lastIndex(of: "_") {
            let digits = name[name.index(after: underscore)...]
            if !digits.isEmpty, digits.allSatisfy(\.isNumber), let number = Int(digits), number > 1 {
                return sibling(String(name[...underscore]) + String(format: "%0\(digits.count)d", number - 1))
            }
        }
        return nil
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
