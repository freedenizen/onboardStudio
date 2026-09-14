import CoreGraphics

/// A rectangle in unit coordinates (0…1) of the output frame, origin at the top-left.
public struct UnitRect: Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public static let full = UnitRect(x: 0, y: 0, width: 1, height: 1)

    /// Pixel rectangle (top-left origin) for an output of the given size.
    public func scaled(toWidth width: Double, height: Double) -> CGRect {
        CGRect(x: x * width, y: y * height, width: self.width * width, height: self.height * height)
    }
}
