import CoreGraphics
import Foundation
import ProjectModel
import RenderKit

/// Draws a scripted object: the cached `background` image, then `frame` every frame, clipped to
/// the object's rectangle. A broken script draws a badge with the error instead of nothing.
public struct ScriptedRenderer: OverlayDrawing {
    public let context: ObjectContext
    public let params: ScriptedParams
    public let engine: ScriptEngine

    public init(context: ObjectContext, params: ScriptedParams) {
        self.context = context
        self.params = params
        engine = ScriptEngine(source: params.source)
    }

    public func draw(in cg: CGContext, size: CGSize, time: Double) {
        let rect = context.rect(in: size)
        guard rect.width > 2, rect.height > 2 else { return }
        cg.setAlpha(context.opacity)
        if let problem = engine.error {
            drawBadge(problem, in: cg, rect: rect)
            return
        }
        if engine.hasBackground {
            let key = context.cacheKey("script|\(params.source.hashValue)", size: size)
            if let image = context.cache.image(
                for: key, size: rect.size,
                draw: { faceContext, faceSize in engine.drawBackground(into: faceContext, size: faceSize) })
            {
                context.cache.drawImage(image, in: rect, context: cg)
            }
        }
        cg.saveGState()
        cg.clip(to: rect)
        cg.translateBy(x: rect.minX, y: rect.minY)
        engine.drawFrame(into: cg, size: rect.size, time: time, objectContext: context)
        cg.restoreGState()
        if let problem = engine.error {
            drawBadge(problem, in: cg, rect: rect)
        }
    }

    func drawBadge(_ problem: ScriptEngine.Problem, in cg: CGContext, rect: CGRect) {
        cg.saveGState()
        cg.setAlpha(1)
        cg.fillRoundedRect(
            rect, radius: rect.height * 0.1, color: RGBAColor(red: 0.6, green: 0.1, blue: 0.1, alpha: 0.85).cgColor)
        let style = TextDrawing.Style(pointSize: max(10, min(rect.height * 0.22, rect.width * 0.05)), color: .white)
        let location = problem.line.map { " (line \($0))" } ?? ""
        TextDrawing.draw(
            "Script error\(location)", at: CGPoint(x: rect.minX + 8, y: rect.minY + 6), style: style, in: cg)
        let detail = TextDrawing.Style(pointSize: style.pointSize * 0.8, color: .white, weightBold: false)
        TextDrawing.draw(
            String(problem.message.prefix(120)),
            at: CGPoint(x: rect.minX + 8, y: rect.minY + 8 + style.pointSize * 1.3),
            style: detail, in: cg)
        cg.restoreGState()
    }
}

// swiftlint:disable line_length
/// Ready-made scripts for the inspector's Examples menu.
public enum ScriptExamples {
    public struct Example: Sendable, Identifiable {
        public let name: String
        public let source: String
        public var id: String { name }
    }

    public static let all: [Example] = [
        Example(name: "Speed readout", source: ScriptedParams.defaultSource),
        Example(
            name: "Shift light",
            source: """
                // Flashes red above 6500 rpm, amber from 6000.
                function frame(canvas, data) {
                    const rpm = data.value("rpm");
                    if (rpm === null) return;
                    const r = Math.min(canvas.width, canvas.height) * 0.45;
                    let color = "#333333aa";
                    if (rpm >= 6500) color = (Math.floor(canvas.time * 8) % 2 === 0) ? "#ff2020" : "#600000";
                    else if (rpm >= 6000) color = "#ffb000";
                    canvas.fill(color);
                    canvas.circle(canvas.width / 2, canvas.height / 2, r);
                    canvas.stroke("#ffffff", 2);
                    canvas.strokeCircle(canvas.width / 2, canvas.height / 2, r);
                }
                """),
        Example(
            name: "Throttle & brake bars",
            source: """
                function background(canvas) {
                    canvas.fill("#00000066");
                    canvas.roundRect(0, 0, canvas.width, canvas.height, 6);
                }
                function frame(canvas, data) {
                    const throttle = data.value("throttle") || 0;
                    const brake = data.value("brake") || 0;
                    const h = canvas.height * 0.36, pad = canvas.height * 0.1;
                    canvas.fill("#30c040");
                    canvas.rect(pad, pad, (canvas.width - 2 * pad) * clamp(throttle / 100, 0, 1), h);
                    canvas.fill("#e03030");
                    canvas.rect(pad, canvas.height - pad - h, (canvas.width - 2 * pad) * clamp(brake / 100, 0, 1), h);
                    canvas.fill("#ffffff");
                    canvas.text("THR", pad, pad, { size: h * 0.7, bold: true });
                    canvas.text("BRK", pad, canvas.height - pad - h, { size: h * 0.7, bold: true });
                }
                """),
        Example(
            name: "Lap delta (RaceRender style)",
            source: """
                // Uses the RaceRender-style helper names.
                function frame(canvas, data) {
                    SetColor(0, 0, 0, 160);
                    DrawRoundRect(0, 0, Width(), Height(), 8);
                    const delta = GetLapDelta();
                    if (delta < 0) SetColor(60, 220, 90); else if (delta > 0) SetColor(230, 60, 60); else SetColor(255, 255, 255);
                    DrawText(Width() * 0.5, Height() * 0.15, formatDelta(delta), Height() * 0.6, "center");
                    SetColor(255, 255, 255);
                    DrawText(8, 6, "LAP " + GetLapNumber() + "  " + formatTime(GetLapTime()), Height() * 0.2);
                }
                """),
        Example(
            name: "Speed trace",
            source: """
                // The last 10 seconds of speed as a sparkline.
                function frame(canvas, data) {
                    canvas.fill("#00000088");
                    canvas.roundRect(0, 0, canvas.width, canvas.height, 6);
                    const range = data.range("speed");
                    if (!range) return;
                    const points = [];
                    const n = 60;
                    for (let i = 0; i <= n; i++) {
                        const v = data.valueAgo("speed", 10 * (1 - i / n));
                        if (v === null) continue;
                        points.push(canvas.width * i / n, canvas.height - (v - range[0]) / Math.max(range[1] - range[0], 0.1) * canvas.height);
                    }
                    canvas.stroke("#ff9e1a", 3);
                    for (let i = 2; i < points.length; i += 2) canvas.line(points[i - 2], points[i - 1], points[i], points[i + 1]);
                }
                """),
    ]
}
// swiftlint:enable line_length
