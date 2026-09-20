import AVKit
import AppKit
import ProjectModel
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
    /// Output width / height; the player uses aspect-fit, so this defines where the video sits.
    var outputAspect: Double = 16.0 / 9.0
    weak var playerView: AVPlayerView?
    private let editor: EditorModel
    private struct DragState {
        let id: DisplayObjectID
        let handle: ObjectHandle
        let original: UnitRect
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
            let selected = object.id == selectedID
            context.setStrokeColor(
                selected ? NSColor.controlAccentColor.cgColor : NSColor.white.withAlphaComponent(0.35).cgColor)
            context.setLineWidth(selected ? 2 : 1)
            context.stroke(rect)
            if selected {
                context.setFillColor(NSColor.controlAccentColor.cgColor)
                for point in handlePoints(rect) {
                    context.fill(CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8))
                }
            }
        }
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
        let unit = unitPoint(point)
        let handleSize = 6 / max(videoRect.width, 1)
        // Selected object's handles win; then topmost object under the pointer.
        if let id = selectedID, let object = objects.first(where: { $0.id == id }),
            let handle = ObjectGeometry.handle(at: unit, in: object.frame, handleSize: handleSize)
        {
            drag = DragState(id: id, handle: handle, original: object.frame, start: unit)
            return
        }
        let framing = editor.project.settings.framing
        for object in objects.reversed() where object.isVisible {
            if let handle = ObjectGeometry.handle(at: unit, in: object.frame, handleSize: handleSize) {
                editor.selectedObjectID = object.id
                needsDisplay = true
                // Inside a zoomed video's picture, dragging pans the camera framing (as dragging
                // the viewer does in an editor); the video object's edges still resize it.
                if handle == .body, framing.zoom > 1, case .video = object.kind {
                    pan = PanState(start: unit, center: CGPoint(x: framing.centerX, y: framing.centerY))
                    NSCursor.closedHand.push()
                    return
                }
                drag = DragState(id: object.id, handle: handle, original: object.frame, start: unit)
                return
            }
        }
        editor.selectedObjectID = nil
        needsDisplay = true
        if framing.zoom > 1, videoRect.contains(point) {
            pan = PanState(start: unit, center: CGPoint(x: framing.centerX, y: framing.centerY))
            NSCursor.closedHand.push()
        }
    }

    override func mouseDragged(with event: NSEvent) {
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
        let frame = ObjectGeometry.drag(drag.original, handle: drag.handle, delta: delta, keepAspect: keepAspect)
        if let index = objects.firstIndex(where: { $0.id == drag.id }) { objects[index].frame = frame }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if let pan {
            self.pan = nil
            NSCursor.pop()
            let framing = editor.project.settings.framing
            editor.commitFraming(centerX: framing.centerX, centerY: framing.centerY, from: pan.center)
            return
        }
        guard let drag else { return }
        self.drag = nil
        if let object = objects.first(where: { $0.id == drag.id }), object.frame != drag.original {
            editor.moveObject(drag.id, frame: object.frame)
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if editor.project.settings.framing.zoom > 1 { addCursorRect(videoRect, cursor: .openHand) }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 51, 117:  // delete, forward delete
            editor.deleteSelectedObject()
        case 49:  // space
            editor.togglePlayback()
        case 123, 124, 125, 126:  // arrows
            guard let id = selectedID, let object = objects.first(where: { $0.id == id }) else {
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
            let frame = ObjectGeometry.nudged(
                object.frame, byPixels: dx, dy, in: editor.project.settings)
            editor.moveObject(id, frame: frame)
        default:
            super.keyDown(with: event)
        }
    }
}

/// How far one press of an arrow key moves the selected object, in output pixels.
///
/// The plain step is a preference so it can be matched to how fine the user's layouts are; ⇧
/// multiplies it, which is the gesture every editor uses for "the same thing, but coarser".
enum NudgeStep {
    static let defaultPixels = 1.0
    static let shiftMultiplier = 10.0

    static func pixels(shift: Bool, defaults: UserDefaults = .standard) -> Double {
        let step = defaults.double(forKey: "nudgeStepPixels").nonZero(default: defaultPixels)
        return shift ? step * shiftMultiplier : step
    }
}

extension Double {
    fileprivate func nonZero(default value: Double) -> Double { self == 0 ? value : self }
}
