import AVKit
import AppKit
import ProjectModel
import RenderKit
import SwiftUI

/// The video preview with a draggable gizmo layer over it.
struct PreviewView: View {
    @Bindable var editor: EditorModel

    var body: some View {
        ZStack {
            Color.black
            if editor.project.videoInputs.isEmpty {
                WelcomeOverlay(editor: editor)
            } else {
                PlayerAndGizmo(editor: editor)
            }
        }
        .frame(minWidth: 480, minHeight: 270)
    }
}

/// AVPlayerView plus an NSView overlay that draws selection handles and handles dragging.
struct PlayerAndGizmo: NSViewRepresentable {
    let editor: EditorModel

    func makeNSView(context: Context) -> PreviewContainerView {
        let view = PreviewContainerView(editor: editor)
        view.playerView.player = editor.preview.player
        return view
    }

    func updateNSView(_ nsView: PreviewContainerView, context: Context) {
        nsView.gizmo.objects = editor.resolvedObjects
        nsView.gizmo.selectedID = editor.selectedObjectID
        nsView.gizmo.selectedIDs = editor.selectedObjectIDs
        nsView.gizmo.startFinish = editor.startFinishTarget
        let settings = editor.project.settings
        nsView.gizmo.outputAspect = Double(settings.outputWidth) / Double(max(settings.outputHeight, 1))
        nsView.gizmo.needsDisplay = true
    }
}

final class PreviewContainerView: NSView {
    let playerView = AVPlayerView()
    let gizmo: GizmoView

    init(editor: EditorModel) {
        gizmo = GizmoView(editor: editor)
        super.init(frame: .zero)
        playerView.controlsStyle = .none
        playerView.showsFullScreenToggleButton = false
        playerView.videoGravity = .resizeAspect
        addSubview(playerView)
        addSubview(gizmo)
        gizmo.playerView = playerView
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityIdentifier("preview")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func layout() {
        super.layout()
        playerView.frame = bounds
        gizmo.frame = bounds
        gizmo.needsDisplay = true
    }
}

/// Draws object outlines over the video and converts mouse drags into frame edits.
final class GizmoView: NSView {
    var objects: [DisplayObject] = []
    var selectedID: DisplayObjectID?
    /// The whole selection: a group, or objects picked with ⌘ or ⇧ (#90).
    var selectedIDs: Set<DisplayObjectID> = []
    /// Output width / height; the player uses aspect-fit, so this defines where the video sits.
    var outputAspect: Double = 16.0 / 9.0
    weak var playerView: AVPlayerView?
    let editor: EditorModel
    /// A move or resize of the selection's box, carrying every selected object with it.
    private struct DragState {
        let handle: ObjectHandle
        let box: UnitRect
        let originals: [DisplayObjectID: UnitRect]
        let start: CGPoint
    }

    private var drag: DragState?
    /// A drag on empty picture while the camera framing is zoomed pans the framing (as dragging
    /// the viewer in an editor's transform mode does).
    private struct PanState {
        let start: CGPoint
        let center: CGPoint
    }

    private var pan: PanState?

    /// The start/finish line being placed on a track map, or `nil` when nobody is placing one.
    var startFinish: StartFinishTarget?
    /// How near the pointer has to be to grab the line or one of its ends, in points.
    private let lineTolerance = 7.0
    /// How far apart the two rotation handles are kept, whatever the line's real width works out
    /// to on screen — comfortably more than twice `lineTolerance`, or one would swallow the other.
    private let handleReach = 18.0
    private struct LineDragState {
        let input: InputID
        let handle: TrackMapEditing.Handle
        /// Pointer minus the line's centre when the drag began, so a line grabbed near one end
        /// travels with the pointer instead of jumping its middle under it.
        let grab: CGSize
        var line: LapLineSpec
    }

    private var lineDrag: LineDragState?

    /// One accessibility element per object, kept rather than rebuilt per request: AppKit holds
    /// the children it is handed only weakly, so a fresh element is gone before it is read.
    var objectElements: [DisplayObjectID: PreviewObjectElement] = [:]

    init(editor: EditorModel) {
        self.editor = editor
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    /// The rectangle the video occupies inside this view: the output frame aspect-fitted into the
    /// bounds, matching `AVPlayerView`'s `.resizeAspect` gravity.
    var videoRect: CGRect {
        guard bounds.width > 0, bounds.height > 0, outputAspect > 0 else { return bounds }
        let scale = min(bounds.width / outputAspect, bounds.height)
        let width = scale * outputAspect
        let height = scale
        return CGRect(x: (bounds.width - width) / 2, y: (bounds.height - height) / 2, width: width, height: height)
    }

    func unitPoint(_ point: CGPoint) -> CGPoint {
        let v = videoRect
        return CGPoint(x: (point.x - v.minX) / v.width, y: (point.y - v.minY) / v.height)
    }

    func viewRect(_ frame: UnitRect) -> CGRect {
        let v = videoRect
        return CGRect(
            x: v.minX + frame.x * v.width, y: v.minY + frame.y * v.height, width: frame.width * v.width,
            height: frame.height * v.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        for object in objects where object.isVisible {
            let rect = viewRect(object.frame)
            let selected = selectedIDs.contains(object.id)
            context.setStrokeColor(
                selected ? NSColor.controlAccentColor.cgColor : NSColor.white.withAlphaComponent(0.35).cgColor)
            context.setLineWidth(selected ? 2 : 1)
            // A locked object is outlined in dashes: there, but not for the mouse.
            context.setLineDash(phase: 0, lengths: object.isLocked ? [4, 3] : [])
            context.stroke(rect)
        }
        context.setLineDash(phase: 0, lengths: [])
        if let box = movableSelectionBox {
            let rect = viewRect(box)
            if selectedIDs.count > 1 {
                context.setStrokeColor(NSColor.controlAccentColor.withAlphaComponent(0.6).cgColor)
                context.setLineWidth(1)
                context.stroke(rect.insetBy(dx: -3, dy: -3))
            }
            context.setFillColor(NSColor.controlAccentColor.cgColor)
            for point in handlePoints(selectedIDs.count > 1 ? rect.insetBy(dx: -3, dy: -3) : rect) {
                context.fill(CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8))
            }
        }
        drawStartFinish(in: context)
    }

    /// The start/finish line over its track map, while it is being placed.
    ///
    /// Drawn here rather than by the renderer on purpose: this is an editing affordance and must
    /// never reach the exported video. Nothing about how the project renders changes by opening
    /// this mode.
    private func drawStartFinish(in context: CGContext) {
        guard let target = startFinish, let line = currentStartFinishLine(target) else { return }
        context.setLineCap(.round)
        // The arms out to the handles, drawn thin: they are reach, not part of the line's width.
        context.setStrokeColor(NSColor.systemYellow.withAlphaComponent(0.5).cgColor)
        context.setLineWidth(1)
        context.move(to: line.leftHandle)
        context.addLine(to: line.rightHandle)
        context.strokePath()
        // The line itself, as wide as it really is, with a dark casing so it reads over a pale map
        // and over map imagery alike.
        for (colour, width) in [(NSColor.black.withAlphaComponent(0.7), 5.0), (NSColor.systemYellow, 2.5)] {
            context.setStrokeColor(colour.cgColor)
            context.setLineWidth(width)
            context.move(to: line.left)
            context.addLine(to: line.right)
            context.strokePath()
        }
        // Which way the car crosses, as a stub off the middle of the line.
        let across = CGPoint(x: line.right.x - line.centre.x, y: line.right.y - line.centre.y)
        let length = hypot(across.x, across.y)
        if length > 0 {
            let travel = CGPoint(x: across.y / length, y: -across.x / length)
            context.setStrokeColor(NSColor.systemYellow.cgColor)
            context.setLineWidth(2)
            context.move(to: line.centre)
            context.addLine(to: CGPoint(x: line.centre.x + travel.x * 14, y: line.centre.y + travel.y * 14))
            context.strokePath()
        }
        context.setFillColor(NSColor.systemYellow.cgColor)
        context.setStrokeColor(NSColor.black.cgColor)
        context.setLineWidth(1)
        for end in [line.leftHandle, line.rightHandle] {
            let box = CGRect(x: end.x - 4, y: end.y - 4, width: 8, height: 8)
            context.fillEllipse(in: box)
            context.strokeEllipse(in: box)
        }
    }

    /// The line as drawn right now: the one being dragged if a drag is under way, else the saved
    /// one. Without this the line would jump back to where it was for the length of every drag.
    private func currentStartFinishLine(_ target: StartFinishTarget) -> TrackMapEditing.Line? {
        let rect = viewRect(target.object.frame)
        guard rect.width > 4, rect.height > 4 else { return nil }
        let spec = lineDrag?.input == target.input ? (lineDrag?.line ?? target.line) : target.line
        return TrackMapEditing.line(
            spec, projection: target.projection, in: rect, minimumHandleDistance: handleReach)
    }

    private func handlePoints(_ r: CGRect) -> [CGPoint] {
        [
            CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
            CGPoint(x: r.maxX, y: r.midY),
            CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.midX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY),
            CGPoint(x: r.minX, y: r.midY),
        ]
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        // The line being placed wins over everything, including the map object under it: while
        // this mode is on, the gesture the pointer is near is the one that was meant.
        if let target = startFinish, let line = currentStartFinishLine(target),
            let handle = TrackMapEditing.handle(at: point, of: line, tolerance: lineTolerance)
        {
            lineDrag = LineDragState(
                input: target.input, handle: handle,
                grab: CGSize(width: point.x - line.centre.x, height: point.y - line.centre.y),
                line: target.line)
            return
        }
        let unit = unitPoint(point)
        let handleSize = 6 / max(videoRect.width, 1)
        let extending = !event.modifierFlags.isDisjoint(with: [.shift, .command])
        // The selection's handles win; then the topmost object under the pointer that is not
        // locked (#90) — a click meant for the video behind a finished gauge reaches the video.
        if !extending, let box = movableSelectionBox.map(handleBox),
            let handle = ObjectGeometry.handle(at: unit, in: box, handleSize: handleSize), handle != .body
        {
            beginDrag(handle, at: unit)
            return
        }
        let framing = editor.project.settings.framing
        for object in objects.reversed() where object.isVisible && !object.isLocked {
            if let handle = ObjectGeometry.handle(at: unit, in: object.frame, handleSize: handleSize) {
                if extending {
                    editor.selectObject(object.id, extending: true)
                    return
                }
                if !selectedIDs.contains(object.id) { editor.selectObject(object.id) }
                selectedIDs = editor.selectedObjectIDs
                needsDisplay = true
                // Inside a zoomed video's picture, dragging pans the camera framing (as dragging
                // the viewer does in an editor); the video object's edges still resize it.
                if handle == .body, framing.zoom > 1, case .video = object.kind {
                    pan = PanState(start: unit, center: CGPoint(x: framing.centerX, y: framing.centerY))
                    NSCursor.closedHand.push()
                    return
                }
                beginDrag(selectedIDs.count > 1 ? .body : handle, at: unit)
                return
            }
        }
        if extending { return }
        editor.selectedObjectID = nil
        needsDisplay = true
        if framing.zoom > 1, videoRect.contains(point) {
            pan = PanState(start: unit, center: CGPoint(x: framing.centerX, y: framing.centerY))
            NSCursor.closedHand.push()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if let lineDrag, let target = startFinish {
            let point = convert(event.locationInWindow, from: nil)
            // Only moving the line keeps the grab offset; an end is being pointed somewhere, and
            // the pointer is where it should end up.
            let corrected =
                lineDrag.handle == .body
                ? CGPoint(x: point.x - lineDrag.grab.width, y: point.y - lineDrag.grab.height) : point
            self.lineDrag?.line = TrackMapEditing.dragged(
                lineDrag.line, handle: lineDrag.handle, to: corrected,
                projection: target.projection, in: viewRect(target.object.frame))
            needsDisplay = true
            return
        }
        if let pan {
            let unit = unitPoint(convert(event.locationInWindow, from: nil))
            // Moving the pointer right must move the picture right, i.e. the window left; one
            // full drag across the view pans one window width.
            let zoom = max(editor.project.settings.framing.zoom, 1)
            let x = pan.center.x - (unit.x - pan.start.x) / zoom
            let y = pan.center.y - (unit.y - pan.start.y) / zoom
            editor.previewFraming(centerX: x, centerY: y)
            return
        }
        guard let drag else { return }
        let unit = unitPoint(convert(event.locationInWindow, from: nil))
        let delta = CGSize(width: unit.x - drag.start.x, height: unit.y - drag.start.y)
        let keepAspect = event.modifierFlags.contains(.shift)
        let box = ObjectGeometry.drag(drag.box, handle: drag.handle, delta: delta, keepAspect: keepAspect)
        for (id, original) in drag.originals {
            guard let index = objects.firstIndex(where: { $0.id == id }) else { continue }
            objects[index].frame =
                drag.originals.count == 1 ? box : ObjectGeometry.mapped(original, from: drag.box, to: box)
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if let lineDrag {
            self.lineDrag = nil
            // One undo step per drag, and none at all for a click that moved nothing.
            if lineDrag.line != startFinish?.line { editor.placeStartFinish(lineDrag.line, for: lineDrag.input) }
            needsDisplay = true
            return
        }
        if let pan {
            self.pan = nil
            NSCursor.pop()
            let framing = editor.project.settings.framing
            editor.commitFraming(centerX: framing.centerX, centerY: framing.centerY, from: pan.center)
            return
        }
        guard let drag else { return }
        self.drag = nil
        var moved: [DisplayObjectID: UnitRect] = [:]
        for (id, original) in drag.originals {
            if let object = objects.first(where: { $0.id == id }), object.frame != original { moved[id] = object.frame }
        }
        if moved.count == 1, let (id, frame) = moved.first {
            editor.moveObject(id, frame: frame)
        } else {
            editor.moveObjects(moved)
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if editor.project.settings.framing.zoom > 1 { addCursorRect(videoRect, cursor: .openHand) }
    }
}

/// How far one press of an arrow key moves the selected object, in output pixels.
///
/// The plain step is a preference so it can be matched to how fine the user's layouts are; ⇧
/// multiplies it, which is the gesture every editor uses for "the same thing, but coarser".
enum NudgeStep {
    static let shiftMultiplier = 10.0

    static func pixels(shift: Bool, defaults: UserDefaults = .standard) -> Double {
        // Read through `Preferences` like every other setting. It used to be `double(forKey:)`
        // here and `@AppStorage` in Settings — two mechanisms for one key, and this one needed a
        // "treat zero as unset" guard to make up for `double(forKey:)` returning zero for both.
        let step = defaults.value(for: Preferences.nudgeStepPixels)
        return shift ? step * shiftMultiplier : step
    }
}

// MARK: - Selection (#90)

extension GizmoView {
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 51, 117:  // delete, forward delete
            editor.deleteSelectedObject()
        case 49:  // space
            editor.togglePlayback()
        case 123, 124, 125, 126:  // arrows
            guard selectedID != nil else {
                // Nothing selected, so the arrows still belong to the playhead. `,`/`.` step
                // frames whatever has focus; this keeps the habit working over the picture.
                switch event.keyCode {
                case 123: editor.step(by: -1)
                case 124: editor.step(by: 1)
                default: super.keyDown(with: event)
                }
                return
            }
            // Nudge in pixels of the output frame, not a fraction of it, so the step means the
            // same thing whatever the project's size.
            let pixels = NudgeStep.pixels(shift: event.modifierFlags.contains(.shift))
            let (dx, dy): (Double, Double) =
                switch event.keyCode {
                case 123: (-pixels, 0)
                case 124: (pixels, 0)
                case 125: (0, pixels)
                default: (0, -pixels)
                }
            let selection = movableSelection
            guard !selection.isEmpty else {
                editor.statusMessage = "Locked objects stay where they are. Unlock them first (⌘L)."
                return
            }
            var frames: [DisplayObjectID: UnitRect] = [:]
            for object in selection {
                frames[object.id] = ObjectGeometry.nudged(object.frame, byPixels: dx, dy, in: editor.project.settings)
            }
            if frames.count == 1, let (id, frame) = frames.first {
                editor.moveObject(id, frame: frame)
            } else {
                editor.moveObjects(frames)
            }
        default:
            super.keyDown(with: event)
        }
    }

    /// The selected objects the mouse may move: none of them locked.
    fileprivate var movableSelection: [DisplayObject] {
        let selected = objects.filter { selectedIDs.contains($0.id) && $0.isVisible }
        return selected.contains(where: \.isLocked) ? [] : selected
    }

    /// The box the selection moves and resizes by: one object's frame, or the bounds of a group.
    fileprivate var movableSelectionBox: UnitRect? { ObjectGeometry.bounds(movableSelection.map(\.frame)) }

    /// Where the selection's handles sit: on the object itself, or just outside a group's
    /// bounds so they do not land on its members' own edges.
    fileprivate func handleBox(_ box: UnitRect) -> UnitRect {
        guard selectedIDs.count > 1 else { return box }
        let dx = 3 / max(videoRect.width, 1)
        let dy = 3 / max(videoRect.height, 1)
        return UnitRect(x: box.x - dx, y: box.y - dy, width: box.width + 2 * dx, height: box.height + 2 * dy)
    }

    fileprivate func beginDrag(_ handle: ObjectHandle, at unit: CGPoint) {
        let selection = movableSelection
        guard let box = ObjectGeometry.bounds(selection.map(\.frame)) else { return }
        drag = DragState(
            handle: handle, box: box, originals: Dictionary(uniqueKeysWithValues: selection.map { ($0.id, $0.frame) }),
            start: unit)
    }
}
