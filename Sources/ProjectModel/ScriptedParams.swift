import Foundation

/// A JavaScript-drawn object: `background(canvas)` runs once per output size for static parts,
/// `frame(canvas, data)` runs every frame. See `docs/scripting.md`.
public struct ScriptedParams: Hashable, Codable, Sendable {
    public var source: String

    public init(source: String = ScriptedParams.defaultSource) {
        self.source = source
    }

    private enum CodingKeys: String, CodingKey {
        case source
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? Self.defaultSource
    }

    // swiftlint:disable line_length
    public static let defaultSource = """
        // Drawn once: a translucent rounded panel.
        function background(canvas) {
            canvas.fill("#00000088");
            canvas.roundRect(0, 0, canvas.width, canvas.height, canvas.height * 0.15);
        }

        // Drawn every frame: the speed in big digits.
        function frame(canvas, data) {
            const speed = data.speed("mph");
            canvas.fill("#ffffff");
            canvas.text(speed === null ? "--" : speed.toFixed(0), canvas.width * 0.5, canvas.height * 0.55,
                        { size: canvas.height * 0.6, align: "center", bold: true, mono: true });
            canvas.text("mph", canvas.width * 0.5, canvas.height * 0.9, { size: canvas.height * 0.18, align: "center" });
        }
        """
    // swiftlint:enable line_length
}
