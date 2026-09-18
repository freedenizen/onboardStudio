import Foundation

/// A display object's look, saved on its own so it can be reused in other projects: the kind
/// with all its parameters, the opacity and the size. Position, label and data source are not
/// part of a style.
public struct ObjectStyle: Hashable, Codable, Sendable {
    public static let formatVersion = 1
    public static let fileExtension = "overlaystyle"
    public static let pasteboardType = "com.freedenizen.overlaygen.style"

    public var formatVersion: Int
    public var kind: DisplayObjectKind
    public var opacity: Double
    public var width: Double
    public var height: Double

    public init(object: DisplayObject) {
        formatVersion = Self.formatVersion
        kind = object.kind
        opacity = object.opacity
        width = object.frame.width
        height = object.frame.height
    }

    /// Applies the style to `object`, keeping its identity, label, data source and position.
    /// The object's origin is nudged so it stays inside the frame after resizing.
    public func apply(to object: inout DisplayObject) {
        object.kind = kind
        object.opacity = opacity
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
        let style = try JSONDecoder().decode(ObjectStyle.self, from: data)
        guard style.formatVersion <= Self.formatVersion else { throw ObjectStyleError.newerFormat(style.formatVersion) }
        self = style
    }
}

public enum ObjectStyleError: Error, CustomStringConvertible {
    case newerFormat(Int)

    public var description: String {
        switch self {
        case .newerFormat(let version):
            "This style was saved by a newer version of OverlayGen (format \(version))."
        }
    }
}
