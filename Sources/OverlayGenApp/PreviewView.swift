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
                VStack(spacing: 8) {
                    Image(systemName: "video.badge.plus").font(.system(size: 48)).foregroundStyle(.secondary)
                    Text("Add a video to start").foregroundStyle(.secondary)
                }
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
        for object in objects.reversed() where object.isVisible {
            if let handle = ObjectGeometry.handle(at: unit, in: object.frame, handleSize: handleSize) {
                editor.selectedObjectID = object.id
                drag = DragState(id: object.id, handle: handle, original: object.frame, start: unit)
                needsDisplay = true
                return
            }
        }
        editor.selectedObjectID = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let drag else { return }
        let unit = unitPoint(convert(event.locationInWindow, from: nil))
        let delta = CGSize(width: unit.x - drag.start.x, height: unit.y - drag.start.y)
        let keepAspect = event.modifierFlags.contains(.shift)
        let frame = ObjectGeometry.drag(drag.original, handle: drag.handle, delta: delta, keepAspect: keepAspect)
        if let index = objects.firstIndex(where: { $0.id == drag.id }) { objects[index].frame = frame }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let drag else { return }
        self.drag = nil
        if let object = objects.first(where: { $0.id == drag.id }), object.frame != drag.original {
            editor.moveObject(drag.id, frame: object.frame)
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 51, 117:  // delete, forward delete
            editor.deleteSelectedObject()
        case 49:  // space
            editor.togglePlayback()
        default:
            super.keyDown(with: event)
        }
    }
}
