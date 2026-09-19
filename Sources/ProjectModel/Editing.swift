import CoreGraphics
import Foundation

/// Sync-wizard arithmetic: the user identifies one moment in the video (project time) and the
/// same moment in the data (input time); we solve for the data input's start position.
public enum SyncWizard {
    /// Start position such that `dataTime` is shown at `projectTime`, keeping offset and speed.
    public static func startPosition(projectTime: Double, dataTime: Double, sync: SyncSettings) -> Double {
        dataTime - (projectTime - sync.offsetInProject) * sync.playSpeed
    }
}

/// Which part of a display object a pointer hit.
public enum ObjectHandle: Sendable, Equatable {
    case body
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    public var resizesHorizontally: Bool {
        [.topLeft, .topRight, .right, .bottomRight, .bottomLeft, .left].contains(self)
    }
    public var resizesVertically: Bool {
        [.topLeft, .top, .topRight, .bottomRight, .bottom, .bottomLeft].contains(self)
    }
    public var movesLeftEdge: Bool { [.topLeft, .left, .bottomLeft].contains(self) }
    public var movesTopEdge: Bool { [.topLeft, .top, .topRight].contains(self) }
}

/// Pure geometry for dragging display objects on a preview. All coordinates are unit (0…1).
public enum ObjectGeometry {
    public static let minimumSize = 0.02

    /// Hit-tests `point` against `frame`; `handleSize` is the handle radius in unit space.
    public static func handle(at point: CGPoint, in frame: UnitRect, handleSize: Double) -> ObjectHandle? {
        let r = CGRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
        let corners: [(ObjectHandle, CGPoint)] = [
            (.topLeft, CGPoint(x: r.minX, y: r.minY)), (.topRight, CGPoint(x: r.maxX, y: r.minY)),
            (.bottomRight, CGPoint(x: r.maxX, y: r.maxY)), (.bottomLeft, CGPoint(x: r.minX, y: r.maxY)),
            (.top, CGPoint(x: r.midX, y: r.minY)), (.right, CGPoint(x: r.maxX, y: r.midY)),
            (.bottom, CGPoint(x: r.midX, y: r.maxY)), (.left, CGPoint(x: r.minX, y: r.midY)),
        ]
        for (handle, corner) in corners
        where abs(point.x - corner.x) <= handleSize && abs(point.y - corner.y) <= handleSize {
            return handle
        }
        return r.insetBy(dx: -handleSize / 2, dy: -handleSize / 2).contains(point) ? .body : nil
    }

    /// Applies a drag of `delta` (unit space) from `original` via `handle`, clamped to the frame.
    public static func drag(_ original: UnitRect, handle: ObjectHandle, delta: CGSize, keepAspect: Bool = false)
        -> UnitRect
    {
        var rect = original
        switch handle {
        case .body:
            rect.x += delta.width
            rect.y += delta.height
        default:
            if handle.resizesHorizontally {
                if handle.movesLeftEdge {
                    let newX = min(original.x + delta.width, original.x + original.width - minimumSize)
                    rect.width = original.width - (newX - original.x)
                    rect.x = newX
                } else {
                    rect.width = max(minimumSize, original.width + delta.width)
                }
            }
            if handle.resizesVertically {
                if handle.movesTopEdge {
                    let newY = min(original.y + delta.height, original.y + original.height - minimumSize)
                    rect.height = original.height - (newY - original.y)
                    rect.y = newY
                } else {
                    rect.height = max(minimumSize, original.height + delta.height)
                }
            }
            if keepAspect, original.height > 0 {
                let aspect = original.width / original.height
                if handle.resizesHorizontally && !handle.resizesVertically {
                    rect.height = rect.width / aspect
                } else {
                    rect.width = rect.height * aspect
                }
            }
        }
        rect.width = min(rect.width, 1)
        rect.height = min(rect.height, 1)
        rect.x = min(max(rect.x, 0), 1 - rect.width)
        rect.y = min(max(rect.y, 0), 1 - rect.height)
        return rect
    }
}

/// Factory defaults for new display objects so a freshly added gauge looks reasonable.
extension DisplayObject {
    public static func makeDefault(kind: DisplayObjectKind, inputID: InputID?, index: Int) -> DisplayObject {
        let stagger = Double(index % 5) * 0.04
        let frame: UnitRect =
            switch kind {
            case .video: .full
            case .speedometer, .tachometer, .gauge:
                UnitRect(x: 0.72 - stagger, y: 0.58 - stagger, width: 0.22, height: 0.38)
            case .trackMap: UnitRect(x: 0.03 + stagger, y: 0.03 + stagger, width: 0.18, height: 0.3)
            case .gForce: UnitRect(x: 0.03 + stagger, y: 0.6 - stagger, width: 0.16, height: 0.28)
            case .timer: UnitRect(x: 0.3, y: 0.03 + stagger, width: 0.4, height: 0.08)
            case .textData: UnitRect(x: 0.3, y: 0.88 - stagger, width: 0.4, height: 0.08)
            case .shape: UnitRect(x: 0.25 + stagger, y: 0.4, width: 0.5, height: 0.2)
            case .text: UnitRect(x: 0.2, y: 0.05 + stagger, width: 0.6, height: 0.1)
            case .image: UnitRect(x: 0.05 + stagger, y: 0.05 + stagger, width: 0.15, height: 0.15)
            case .bar: UnitRect(x: 0.3, y: 0.8 - stagger, width: 0.4, height: 0.05)
            case .graph: UnitRect(x: 0.03 + stagger, y: 0.7 - stagger, width: 0.3, height: 0.2)
            case .gear: UnitRect(x: 0.6 - stagger, y: 0.05 + stagger, width: 0.08, height: 0.14)
            case .lapCounter: UnitRect(x: 0.03 + stagger, y: 0.35 + stagger, width: 0.14, height: 0.08)
            case .scripted: UnitRect(x: 0.35 + stagger, y: 0.8 - stagger, width: 0.3, height: 0.12)
            case .indicator: UnitRect(x: 0.45 + stagger, y: 0.05 + stagger, width: 0.07, height: 0.1)
            case .lapPanel: UnitRect(x: 0.2, y: 0.03 + stagger, width: 0.6, height: 0.1)
            }
        return DisplayObject(label: kind.typeName, inputID: inputID, frame: frame, kind: kind)
    }

    /// Menu-ready templates for every kind.
    public static let templates: [(name: String, kind: DisplayObjectKind)] = [
        ("Speedometer", .speedometer(.speedometer())),
        ("Tachometer", .tachometer(.tachometer())),
        (
            "Gauge",
            .gauge(
                GaugeParams(
                    channel: "throttle", title: "THROTTLE", minValue: 0, maxValue: 100, unitLabel: "%", majorTick: 25,
                    minorTick: 5))
        ),
        ("Track Map", .trackMap(TrackMapParams())),
        ("G-Force", .gForce(GForceParams())),
        ("Bar", .bar(BarParams(channel: "throttle", label: "THROTTLE", unitLabel: "%"))),
        ("Graph", .graph(GraphParams(series: [GraphSeries(channel: "speed")], label: "SPEED"))),
        ("Gear", .gear(GearParams())),
        ("Lap Timer", .timer(TimerParams())),
        ("Lap Counter", .lapCounter(LapCounterParams())),
        ("Timing Panel", .lapPanel(LapPanelParams())),
        (
            "Delta Bar (time)",
            .bar(
                BarParams(
                    channel: "lapDelta", label: "Δ", minValue: -2, maxValue: 2,
                    zones: [
                        GaugeZone(from: -2, to: 0, color: RGBAColor(red: 0.13, green: 0.75, blue: 0.25)),
                        GaugeZone(from: 0, to: nil, color: RGBAColor(red: 0.88, green: 0.19, blue: 0.19)),
                    ], decimals: 2, unitLabel: "s", fillFromZero: true))
        ),
        (
            "Delta Bar (speed)",
            .bar(
                BarParams(
                    channel: "speedDelta", label: "Δ", minValue: -10, maxValue: 10,
                    zones: [
                        GaugeZone(from: -10, to: 0, color: RGBAColor(red: 0.88, green: 0.19, blue: 0.19)),
                        GaugeZone(from: 0, to: nil, color: RGBAColor(red: 0.13, green: 0.75, blue: 0.25)),
                    ], decimals: 0, fillFromZero: true))
        ),
        ("ABS Light", .indicator(.abs)),
        ("Traction Light", .indicator(.traction)),
        ("Brake Light", .indicator(.brake)),
        ("Text Data", .textData(TextDataParams(channel: "rpm", label: "RPM"))),
        ("Script", .scripted(ScriptedParams())),
        ("Shape", .shape(ShapeParams())),
        ("Text", .text(TextParams())),
    ]
}
