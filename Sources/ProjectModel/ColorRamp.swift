import Foundation

/// The colours a value is painted in from its lowest to its highest, evenly spaced and blended
/// between (#561): the Track Map's line coloured by a channel. One ramp serves every map, set in
/// Settings, so the same colour means the same thing in every project.
public struct ColorRamp: Hashable, Sendable {
    /// At least two; the first is the lowest value's colour, the last the highest's.
    public var stops: [RGBAColor]

    /// Fewer than two colours falls back to the standard ramp, which keeps every caller from
    /// having to guard against a ramp that cannot blend.
    public init(stops: [RGBAColor]) {
        self.stops = stops.count >= 2 ? stops : Self.standard.stops
    }

    /// Blue, green, yellow, red: the heat-map order RaceChrono and MoTeC use, so slow and fast,
    /// off and on, read the way a driver already reads them.
    public static let standard = ColorRamp(
        uncheckedStops: [
            RGBAColor(red: 0.2, green: 0.45, blue: 1),
            RGBAColor(red: 0.18, green: 0.8, blue: 0.35),
            RGBAColor(red: 1, green: 0.85, blue: 0.15),
            RGBAColor(red: 0.92, green: 0.2, blue: 0.18),
        ])

    private init(uncheckedStops: [RGBAColor]) {
        stops = uncheckedStops
    }

    /// The colour at `fraction` of the way from the lowest value to the highest, clamped to the
    /// ends.
    public func color(at fraction: Double) -> RGBAColor {
        guard fraction.isFinite else { return stops[0] }
        let position = min(max(fraction, 0), 1) * Double(stops.count - 1)
        let index = min(Int(position), stops.count - 2)
        let mix = position - Double(index)
        let low = stops[index]
        let high = stops[index + 1]
        func blend(_ a: Double, _ b: Double) -> Double { a + (b - a) * mix }
        return RGBAColor(
            red: blend(low.red, high.red), green: blend(low.green, high.green), blue: blend(low.blue, high.blue),
            alpha: blend(low.alpha, high.alpha))
    }

    // MARK: - As a preference

    /// The hex colours separated by spaces, as `Preferences.mapColorRamp` keeps them: a property-
    /// list string `@AppStorage` can hold.
    public var preferenceText: String {
        stops.map(\.hex).joined(separator: " ")
    }

    /// The ramp a preference holds; empty or unreadable text is the standard ramp.
    public init(preferenceText text: String) {
        let parsed = text.split(separator: " ").compactMap { RGBAColor(hex: String($0)) }
        self.init(stops: parsed)
    }
}
