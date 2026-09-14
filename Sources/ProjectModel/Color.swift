/// An sRGB colour with 0…1 components, serialised as `#RRGGBB` or `#RRGGBBAA`.
public struct RGBAColor: Hashable, Sendable, Codable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    /// Components are quantised to 8 bits so a colour survives a hex round trip unchanged.
    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = Self.quantise(red)
        self.green = Self.quantise(green)
        self.blue = Self.quantise(blue)
        self.alpha = Self.quantise(alpha)
    }

    static func quantise(_ component: Double) -> Double {
        (min(max(component, 0), 1) * 255).rounded() / 255
    }

    /// Parses `#RGB`, `#RRGGBB` or `#RRGGBBAA` (leading `#` optional).
    public init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard let value = UInt32(text, radix: 16) else { return nil }
        switch text.count {
        case 3:
            red = Double((value >> 8) & 0xF) / 15
            green = Double((value >> 4) & 0xF) / 15
            blue = Double(value & 0xF) / 15
            alpha = 1
        case 6:
            red = Double((value >> 16) & 0xFF) / 255
            green = Double((value >> 8) & 0xFF) / 255
            blue = Double(value & 0xFF) / 255
            alpha = 1
        case 8:
            red = Double((value >> 24) & 0xFF) / 255
            green = Double((value >> 16) & 0xFF) / 255
            blue = Double((value >> 8) & 0xFF) / 255
            alpha = Double(value & 0xFF) / 255
        default:
            return nil
        }
    }

    public var hex: String {
        func byte(_ component: Double) -> String {
            String(format: "%02X", Int((min(max(component, 0), 1) * 255).rounded()))
        }
        let rgb = byte(red) + byte(green) + byte(blue)
        return alpha >= 1 ? "#" + rgb : "#" + rgb + byte(alpha)
    }

    public init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let color = RGBAColor(hex: text) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid colour \(text)"))
        }
        self = color
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }

    public static let white = RGBAColor(red: 1, green: 1, blue: 1)
    public static let black = RGBAColor(red: 0, green: 0, blue: 0)
    public static let red = RGBAColor(red: 0.9, green: 0.15, blue: 0.15)
    public static let accent = RGBAColor(red: 1, green: 0.62, blue: 0.1)
    public static let faceDark = RGBAColor(red: 0.08, green: 0.08, blue: 0.1, alpha: 0.75)
    public static let translucentBlack = RGBAColor(red: 0, green: 0, blue: 0, alpha: 0.55)
}
