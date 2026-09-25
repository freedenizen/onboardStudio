import CoreGraphics
import Foundation

/// Sync-wizard arithmetic: the user identifies one moment in the video (project time) and the
/// same moment in the data (input time); we solve for the data input's start position.
public enum SyncWizard {
    /// Start position such that `dataTime` is shown at `projectTime`, keeping offset and speed.
    public static func startPosition(projectTime: Double, dataTime: Double, sync: SyncSettings) -> Double {
        dataTime - (projectTime - sync.offsetInProject) * sync.playSpeed
    }

    /// Moves an input `seconds` later on the project timeline; negative moves it earlier.
    ///
    /// Shifting `offsetInProject` rather than `startPositionInInput` keeps the step in *project*
    /// seconds whatever the play speed, which is what a nudge means to the user: one frame later
    /// is one frame later on screen, not one frame of the source file.
    public static func shifted(_ sync: SyncSettings, byProjectSeconds seconds: Double) -> SyncSettings {
        var moved = sync
        moved.offsetInProject += seconds
        return moved
    }

    /// The finest useful sync step: one frame of the project's own rate.
    ///
    /// A tenth of a second is three to six frames at normal rates, so alignment that looks right
    /// to a tenth can still be visibly out on a braking marker or a gear change.
    public static func frameStep(frameRate: Double) -> Double { 1 / max(frameRate, 1) }
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

    /// Whether a click on the preview can pick `object`. A video is under almost every point of
    /// the picture, so clicking beside a small gauge kept selecting it: a video is picked only
    /// once it is already selected (from the sidebar, say) or while the picture is being cropped
    /// or framed. A locked or hidden object is never picked (#90, #278).
    public static func isPickable(_ object: DisplayObject, selected: Bool, editingFraming: Bool = false) -> Bool {
        guard object.isVisible, !object.isLocked else { return false }
        if case .video = object.kind { return selected || editingFraming }
        return true
    }

    /// Objects are allowed to hang off the edges of the frame, and some are meant to: the Glass
    /// Cockpit steering wheel is placed taller than the frame with only its upper arc showing.
    /// A drag therefore only has to leave enough of the object on screen to grab again, rather
    /// than pulling the whole rectangle back inside.
    public static let minimumVisible = 0.06

    /// An object may be up to four frames across, so a wheel or a dial can overflow the picture.
    public static let maximumSize = 4.0

    /// Limits a frame to somewhere it can still be grabbed, allowing it off the edges.
    public static func clamped(_ rect: UnitRect) -> UnitRect {
        var rect = rect
        rect.width = min(max(rect.width, minimumSize), maximumSize)
        rect.height = min(max(rect.height, minimumSize), maximumSize)
        let grabX = min(minimumVisible, rect.width)
        let grabY = min(minimumVisible, rect.height)
        rect.x = min(max(rect.x, grabX - rect.width), 1 - grabX)
        rect.y = min(max(rect.y, grabY - rect.height), 1 - grabY)
        return rect
    }

    /// Whether `rect` is taller than it is wide on the output picture, which is not the same as
    /// in unit coordinates: a 16:9 frame makes a unit square wide.
    public static func isPortrait(_ rect: UnitRect, in settings: ProjectSettings) -> Bool {
        rect.height * Double(settings.outputHeight) > rect.width * Double(settings.outputWidth)
    }

    /// `rect` given a quarter turn about its centre as it appears on the picture: what was its
    /// width in pixels becomes its height. Clamped like a drag.
    public static func transposed(_ rect: UnitRect, in settings: ProjectSettings) -> UnitRect {
        let aspect = Double(max(1, settings.outputWidth)) / Double(max(1, settings.outputHeight))
        let width = rect.height / aspect
        let height = rect.width * aspect
        let centreX = rect.x + rect.width / 2
        let centreY = rect.y + rect.height / 2
        return clamped(UnitRect(x: centreX - width / 2, y: centreY - height / 2, width: width, height: height))
    }

    /// Moves `rect` by a number of **output pixels**, clamped like a drag.
    ///
    /// Object frames are fractions of the picture, but a nudge is specified in pixels so the step
    /// means the same thing in a 1080p project and a 4K one. `dx` is positive to the right, `dy`
    /// positive downwards, matching the frame's own coordinates.
    public static func nudged(
        _ rect: UnitRect, byPixels dx: Double, _ dy: Double, in settings: ProjectSettings
    ) -> UnitRect {
        var moved = rect
        if settings.outputWidth > 0 { moved.x += dx / Double(settings.outputWidth) }
        if settings.outputHeight > 0 { moved.y += dy / Double(settings.outputHeight) }
        return clamped(moved)
    }

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

    /// Applies a drag of `delta` (unit space) from `original` via `handle`. The result may hang
    /// off the edges of the frame; see `clamped(_:)`.
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
        return clamped(rect)
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
            case .statCard: UnitRect(x: 0.03 + stagger, y: 0.05 + stagger, width: 0.3, height: 0.3)
            case .sectorPanel: UnitRect(x: 0.25, y: 0.15 + stagger, width: 0.5, height: 0.09)
            // A wide wheel whose upper arc rises out of the bottom of a 16:9 frame.
            case .steeringWheel: UnitRect(x: 0.22, y: 0.5, width: 0.56, height: 0.56 * 16 / 9)
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
        ("Sector Times", .sectorPanel(SectorPanelParams())),
        ("Stat Card", .statCard(StatCardParams())),
        ("Steering Wheel", .steeringWheel(SteeringWheelParams())),
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
        // Filled from the project's details (#74), so it reads right in any project it lands in.
        ("Title Card", .text(TextParams(text: "{track} · {date}"))),
    ]
}

extension GaugeParams {
    /// The same gauge, scaled to what its channel actually reads in this data (#180).
    ///
    /// Applied when an object is **created**, never when a project is opened: a saved project
    /// keeps the scale it was saved with, whatever the data now says.
    ///
    /// A gauge carrying zones keeps its authored scale. A redline at 6500 of 8000 is a statement
    /// about the scale it was drawn against, and moving the scale underneath it would leave the
    /// zone somewhere its author never put it — possibly off the dial entirely.
    public func fitted(to channels: [ChannelSummary]) -> GaugeParams {
        guard zones.isEmpty, let summary = channels.first(where: { $0.identifier == channel }),
            !summary.isConvertedForDisplay, let bounds = summary.suggestedBounds
        else { return self }
        var result = self
        result.minValue = bounds.min
        result.maxValue = bounds.max
        result.majorTick = GaugeParams.tick(over: bounds.max - bounds.min, parts: 5)
        result.minorTick = GaugeParams.tick(over: bounds.max - bounds.min, parts: 10)
        // The template's label states a unit the channel may not be in; the channel's own is right
        // whenever it has one. An empty unit leaves the label alone rather than blanking it.
        if !summary.unit.isEmpty { result.unitLabel = summary.unit }
        return result
    }

    /// A tick that divides `span` into roughly `parts`, rounded to something a person would write.
    static func tick(over span: Double, parts: Int) -> Double {
        guard span > 0, parts > 0 else { return 1 }
        let raw = span / Double(parts)
        let step = pow(10, floor(log10(raw)))
        guard step > 0, step.isFinite else { return raw }
        return [1.0, 2.0, 2.5, 5.0, 10.0].first { raw <= $0 * step }.map { $0 * step } ?? 10 * step
    }
}

extension BarParams {
    /// The same bar, scaled to what its channel actually reads in this data (#180). Zones pin the
    /// scale here for the same reason they do on a gauge — the delta bars are built from them.
    public func fitted(to channels: [ChannelSummary]) -> BarParams {
        guard zones.isEmpty, let summary = channels.first(where: { $0.identifier == channel }),
            !summary.isConvertedForDisplay, let bounds = summary.suggestedBounds
        else { return self }
        var result = self
        result.minValue = bounds.min
        result.maxValue = bounds.max
        if !summary.unit.isEmpty { result.unitLabel = summary.unit }
        return result
    }
}

extension DisplayObject {
    /// Turns a bar to `orientation`, and its frame with it when the frame is the wrong way round
    /// for the new orientation (#113): a vertical bar in a long, thin horizontal box is a stub,
    /// and transposing it by hand was arithmetic the app should do. A frame already the right way
    /// round — a bar someone sized deliberately — is left alone.
    public mutating func setBarOrientation(_ orientation: BarOrientation, in settings: ProjectSettings) {
        guard case .bar(var params) = kind, params.orientation != orientation else { return }
        params.orientation = orientation
        kind = .bar(params)
        if ObjectGeometry.isPortrait(frame, in: settings) != (orientation == .vertical) {
            frame = ObjectGeometry.transposed(frame, in: settings)
        }
    }
}

// MARK: - Groups and locks (#90)

extension ObjectGeometry {
    /// The smallest rectangle around every one of `frames`, or `nil` for none.
    public static func bounds(_ frames: [UnitRect]) -> UnitRect? {
        guard let first = frames.first else { return nil }
        var minX = first.x
        var minY = first.y
        var maxX = first.x + first.width
        var maxY = first.y + first.height
        for frame in frames.dropFirst() {
            minX = min(minX, frame.x)
            minY = min(minY, frame.y)
            maxX = max(maxX, frame.x + frame.width)
            maxY = max(maxY, frame.y + frame.height)
        }
        return UnitRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// `frame`'s place inside `old` carried into `new`: how each member of a group follows the
    /// group's box when the box is moved or resized.
    public static func mapped(_ frame: UnitRect, from old: UnitRect, to new: UnitRect) -> UnitRect {
        let sx = old.width > 0 ? new.width / old.width : 1
        let sy = old.height > 0 ? new.height / old.height : 1
        return UnitRect(
            x: new.x + (frame.x - old.x) * sx, y: new.y + (frame.y - old.y) * sy,
            width: max(frame.width * sx, minimumSize), height: max(frame.height * sy, minimumSize))
    }
}

extension Project {
    /// `ids` with every other member of any group one of them belongs to: what a click on one
    /// member of a group selects.
    public func expandingGroups(_ ids: Set<DisplayObjectID>) -> Set<DisplayObjectID> {
        let groups = Set(displayObjects.filter { ids.contains($0.id) }.compactMap(\.groupID))
        guard !groups.isEmpty else { return ids }
        return ids.union(displayObjects.filter { $0.groupID.map(groups.contains) ?? false }.map(\.id))
    }

    /// Makes one group of `ids` and every group they already belong to. Fewer than two objects
    /// make no group, and nor does a selection with a locked object in it: as in Keynote, locked
    /// objects are unlocked before they are grouped, so a group is never half locked.
    @discardableResult
    public mutating func group(_ ids: Set<DisplayObjectID>) -> ObjectGroupID? {
        let members = expandingGroups(ids)
        guard members.count >= 2,
            !displayObjects.contains(where: { members.contains($0.id) && $0.isLocked })
        else { return nil }
        let group = ObjectGroupID()
        for index in displayObjects.indices where members.contains(displayObjects[index].id) {
            displayObjects[index].groupID = group
        }
        return group
    }

    /// Breaks up every group any of `ids` belongs to.
    public mutating func ungroup(_ ids: Set<DisplayObjectID>) {
        let members = expandingGroups(ids)
        for index in displayObjects.indices where members.contains(displayObjects[index].id) {
            displayObjects[index].groupID = nil
        }
    }

    /// Removes `ids`, their segment overrides, and any group left with a single member: one
    /// object is not a group, and a leftover `groupID` would still say "moves with the others".
    public mutating func removeObjects(_ ids: Set<DisplayObjectID>) {
        displayObjects.removeAll { ids.contains($0.id) }
        timeline.prune(keeping: displayObjects.map(\.id))
        let counts = Dictionary(grouping: displayObjects.compactMap(\.groupID), by: { $0 }).mapValues(\.count)
        for index in displayObjects.indices {
            if let group = displayObjects[index].groupID, counts[group, default: 0] < 2 {
                displayObjects[index].groupID = nil
            }
        }
    }

    /// Locks or unlocks `ids` and the rest of their groups: a group is locked as a whole.
    public mutating func setLocked(_ locked: Bool, _ ids: Set<DisplayObjectID>) {
        let members = expandingGroups(ids)
        for index in displayObjects.indices where members.contains(displayObjects[index].id) {
            displayObjects[index].isLocked = locked
        }
    }
}
