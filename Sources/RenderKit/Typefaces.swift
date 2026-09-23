import CoreGraphics
import CoreText
import Foundation
import ProjectModel

/// The fonts installed on this Mac, and a chosen `Typeface` turned into one (#118).
///
/// CoreText rather than AppKit's font manager, so the renderer, the CLI and the inspector's lists
/// all agree on what a family and a face are called. The public lookups take `TextDrawing`'s font
/// lock: the inspector asks from the main thread while frames render, and concurrent lookups have
/// wedged the font server before.
public enum Typefaces {
    /// Every family a user can choose, in the order Font Book lists them. Families whose names
    /// start with a full stop are the system's private UI fonts and cannot be asked for by name.
    public static func families() -> [String] {
        let names = TextDrawing.fontLock.withLock { CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? [] }
        return names.filter { !$0.hasPrefix(".") }
    }

    /// The faces of `family`, lightest first with each italic after its upright, as a font menu
    /// lists them. Empty when the family is not installed.
    public static func faces(of family: String) -> [String] {
        let attributes = [kCTFontFamilyNameAttribute: family] as CFDictionary
        let collection = CTFontCollectionCreateWithFontDescriptors(
            [CTFontDescriptorCreateWithAttributes(attributes)] as CFArray, nil)
        let descriptors = TextDrawing.fontLock.withLock {
            CTFontCollectionCreateMatchingFontDescriptors(collection) as? [CTFontDescriptor] ?? []
        }
        var seen = Set<String>()
        return
            descriptors
            .filter { CTFontDescriptorCopyAttribute($0, kCTFontFamilyNameAttribute) as? String == family }
            .compactMap { descriptor -> Face? in
                guard let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontStyleNameAttribute) as? String,
                    seen.insert(name).inserted
                else { return nil }
                let traits = CTFontDescriptorCopyAttribute(descriptor, kCTFontTraitsAttribute) as? [CFString: Any]
                return Face(
                    name: name, weight: traits?[kCTFontWeightTrait] as? Double ?? 0,
                    italic: (traits?[kCTFontSlantTrait] as? Double ?? 0) != 0)
            }
            .sorted { ($0.weight, $0.italic ? 1 : 0, $0.name) < ($1.weight, $1.italic ? 1 : 0, $1.name) }
            .map(\.name)
    }

    private struct Face {
        let name: String
        let weight: Double
        let italic: Bool
    }

    /// Whether `typeface` can be drawn on this Mac.
    public static func isInstalled(_ typeface: Typeface) -> Bool {
        TextDrawing.fontLock.withLock { font(typeface, size: 12) != nil }
    }

    /// The face to show when the user picks `family`: the face they had if the new family has it
    /// too, then bold (what overlays mostly draw in), then regular, then the family's first.
    public static func face(for family: String, keeping current: String?) -> String? {
        let faces = faces(of: family)
        for candidate in [current, "Bold", "Regular"].compactMap(\.self) where faces.contains(candidate) {
            return candidate
        }
        return faces.first
    }

    /// `typeface` at `size`, or `nil` when this Mac does not have it — never a stand-in the system
    /// picked, because a stand-in would draw in a font nobody chose while looking like success.
    /// The caller holds the font lock.
    static func font(_ typeface: Typeface, size: Double) -> CTFont? {
        let attributes =
            [kCTFontFamilyNameAttribute: typeface.family, kCTFontStyleNameAttribute: typeface.face] as CFDictionary
        // Matching treats even "mandatory" attributes as preferences for the face, so the result
        // is checked by name rather than trusted.
        guard
            let matched = CTFontDescriptorCreateMatchingFontDescriptor(
                CTFontDescriptorCreateWithAttributes(attributes), nil),
            CTFontDescriptorCopyAttribute(matched, kCTFontFamilyNameAttribute) as? String == typeface.family,
            CTFontDescriptorCopyAttribute(matched, kCTFontStyleNameAttribute) as? String == typeface.face
        else { return nil }
        return CTFontCreateWithFontDescriptor(matched, size, nil)
    }

    /// `font` with digits of one width, where the font has them.
    static func withTabularFigures(_ font: CTFont, size: Double) -> CTFont {
        let descriptor = CTFontDescriptorCreateCopyWithFeature(
            CTFontCopyFontDescriptor(font), kNumberSpacingType as CFNumber, kMonospacedNumbersSelector as CFNumber)
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }
}
