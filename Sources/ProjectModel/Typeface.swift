import Foundation

/// A font the user chose for an object's text (#118): a family and one face within it, named as
/// Font Book names them — `Typeface(family: "Futura", face: "Condensed Medium")`.
///
/// Names rather than a PostScript name, because a project travels: the names read in the file,
/// and a Mac without the font can still say which one is missing. Resolving the names to a font
/// is `RenderKit`'s job; when it cannot, the object draws in its own built-in fonts rather than
/// in whatever the system would substitute.
public struct Typeface: Hashable, Codable, Sendable {
    public var family: String
    /// The face's style name within the family: "Regular", "Bold", "Condensed Black".
    public var face: String

    public init(family: String, face: String) {
        self.family = family
        self.face = face
    }

    /// "Helvetica Neue Bold"; a face named "Regular" is left unsaid, as the Font panel does.
    public var displayName: String {
        face.isEmpty || face == "Regular" ? family : "\(family) \(face)"
    }
}

/// Text sizes an object's text can be scaled to, as a multiple of what the object lays out.
public enum TextScale {
    public static let range: ClosedRange<Double> = 0.5...2
}
