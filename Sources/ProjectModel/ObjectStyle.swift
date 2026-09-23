import Foundation

/// A display object's look, saved on its own so it can be reused in other projects: the kind
/// with all its parameters, the opacity, the size and the font. Position, label and data source
/// are not part of a style.
public struct ObjectStyle: Hashable, Codable, Sendable {
    public static let formatVersion = 1
    public static let fileExtension = "onboardstyle"
    /// The extension used before the app was renamed from OverlayGen. Still opened, never written.
    public static let legacyFileExtension = "overlaystyle"
    public static let pasteboardType = "com.freedenizen.onboardstudio.style"
    public static let legacyPasteboardType = "com.freedenizen.overlaygen.style"

    public var formatVersion: Int
    public var kind: DisplayObjectKind
    public var opacity: Double
    public var width: Double
    public var height: Double
    /// The object's own font and text size (#118). Absent from a style saved before fonts could be
    /// chosen, which therefore leaves an object following the project's font, as it did then.
    public var typeface: Typeface?
    public var textScale: Double?

    public init(object: DisplayObject) {
        formatVersion = Self.formatVersion
        kind = object.kind
        opacity = object.opacity
        width = object.frame.width
        height = object.frame.height
        typeface = object.typeface
        textScale = object.textScale
    }

    /// Applies the style to `object`, keeping its identity, label, data source and position.
    /// The object's origin is nudged so it stays inside the frame after resizing.
    public func apply(to object: inout DisplayObject) {
        object.kind = kind
        object.opacity = opacity
        object.typeface = typeface
        object.textScale = textScale
        object.frame.width = min(width, 1)
        object.frame.height = min(height, 1)
        object.frame.x = min(object.frame.x, 1 - object.frame.width)
        object.frame.y = min(object.frame.y, 1 - object.frame.height)
    }

    public func data() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public init(data: Data) throws {
        var style = try JSONDecoder().decode(ObjectStyle.self, from: data)
        try style.migrateIfNeeded()
        self = style
    }

    /// Brings a style saved by an earlier build up to the current format, and refuses a newer one.
    ///
    /// The same seam `Project.migrateIfNeeded()` is, and for the same reason: applying a style
    /// replaces an object's whole `kind`, so a style saved last season can pick up a default
    /// changed since and quietly render differently from the day it was saved.
    ///
    /// **Every way in goes through `init(data:)`** — the file panels, the pasteboard and the CLI —
    /// so unlike `Project` there is no second door that skips this. Keep it that way: a
    /// `JSONDecoder().decode(ObjectStyle.self, …)` anywhere else would opt out silently.
    public mutating func migrateIfNeeded() throws {
        guard formatVersion != Self.formatVersion else { return }
        guard formatVersion < Self.formatVersion else { throw ObjectStyleError.newerFormat(formatVersion) }
        // Future migrations go here, stepping formatVersion up one at a time. A change that alters
        // a default on any type reachable from `kind` belongs here, pinning the old value.
        formatVersion = Self.formatVersion
    }
}

public enum ObjectStyleError: Error, CustomStringConvertible {
    case newerFormat(Int)

    public var description: String {
        switch self {
        case .newerFormat(let version):
            "This style was saved by a newer version of Onboard Studio (format \(version))."
        }
    }
}
