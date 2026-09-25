import AppKit
import ProjectModel
import SwiftUI

// MARK: - Framing on the preview (#275)

/// A drag on the framed window: moving it, or one of its corners.
struct FramingDrag {
    enum Part { case window, corner, crop(ObjectHandle) }
    let part: Part
    /// The framing, or the video's picture, when the drag began; each step is worked out from it,
    /// so nothing drifts.
    var start: CameraFraming = .none
    var startPicture: VideoPicture?
    let startPoint: CGPoint
}

/// While Frame is on, the preview shows the whole shot (every video's own crop applied, the
/// framing not, the overlays put away) and this draws the framed window over it: the part the
/// finished video shows, with the rest dimmed. Drag inside to move it, a corner to zoom; pinch
/// or ⌥-scroll to zoom; the arrow keys move it; Return is Done and Escape Cancel.
extension GizmoView {
    /// Where the shot is drawn: the picture of the largest video on screen, aspect-fitted into its
    /// box as the renderer places it, or the whole output when there is no video.
    var framingTarget: CGRect {
        let cropping = editor.pictureTool?.cropInput
        let videos = objects.filter { object in
            guard object.isVisible, case .video = object.kind else { return false }
            return cropping == nil || object.inputID == cropping
        }
        guard let largest = videos.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })
        else { return videoRect }
        return viewRect(pictureBox(of: largest))
    }

    /// The part of `object`'s box its picture fills (unit coordinates of the output).
    func pictureBox(of object: DisplayObject) -> UnitRect {
        guard let id = object.inputID, let input = editor.project.input(id), case .video(let settings) = input.kind,
            let info = editor.loaded?.mediaInfo[id],
            let aspect = FramingEditing.pictureAspect(
                width: info.width, height: info.height,
                // While cropping it the preview shows the whole of it.
                crop: editor.pictureTool?.cropInput == id ? .none : settings.crop, rotation: settings.rotation),
            object.frame.height > 0
        else { return object.frame }
        let boxAspect = object.frame.width / object.frame.height * outputAspect
        return FramingEditing.fitted(aspect: aspect, in: object.frame, boxAspect: boxAspect)
    }

    /// The framed window on the preview, in view coordinates.
    var framingWindow: CGRect {
        let target = framingTarget
        let region = FramingEditing.region(of: editor.project.settings.framing)
        return CGRect(
            x: target.minX + region.x * target.width, y: target.minY + region.y * target.height,
            width: region.width * target.width, height: region.height * target.height)
    }

    func drawFraming(in context: CGContext) {
        drawDimmed(outside: framingWindow, in: framingTarget, context: context)
        drawToolWindow(framingWindow, in: context, edgeHandles: false)
    }

    func corners(of rect: CGRect) -> [CGPoint] {
        [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY),
        ]
    }

    func framingMouseDown(at point: CGPoint) {
        let window = framingWindow
        let framing = editor.project.settings.framing
        if corners(of: window).contains(where: { hypot($0.x - point.x, $0.y - point.y) <= 9 }) {
            framingDrag = FramingDrag(part: .corner, start: framing, startPoint: point)
        } else if window.contains(point) {
            framingDrag = FramingDrag(part: .window, start: framing, startPoint: point)
            NSCursor.closedHand.push()
        }
    }

    func framingMouseDragged(to point: CGPoint) {
        guard let drag = framingDrag else { return }
        let target = framingTarget
        guard target.width > 0, target.height > 0 else { return }
        switch drag.part {
        case .window:
            let dx = (point.x - drag.startPoint.x) / target.width
            let dy = (point.y - drag.startPoint.y) / target.height
            editor.adjustFraming { _ in FramingEditing.moved(drag.start, dx: dx, dy: dy) }
        case .corner:
            // The window keeps its centre and shape; the corner says how far out it reaches.
            let window = framingWindow
            let across = 2 * abs(point.x - window.midX) / target.width
            let down = 2 * abs(point.y - window.midY) / target.height
            editor.adjustFraming { _ in FramingEditing.resized(drag.start, toWidth: across, height: down) }
        case .crop: break  // PreviewCropping.swift
        }
        needsDisplay = true
    }

    func framingMouseUp() {
        if case .window = framingDrag?.part { NSCursor.pop() }
        framingDrag = nil
        window?.invalidateCursorRects(for: self)
    }

    /// Returns whether the key was framing's to handle.
    func framingKeyDown(_ event: NSEvent) -> Bool {
        let step = event.modifierFlags.contains(.shift) ? 0.1 : 0.01
        switch event.keyCode {
        case 36, 76: editor.finishFraming()  // return, enter
        case 53: editor.cancelFraming()  // escape
        case 123: editor.adjustFraming { FramingEditing.moved($0, dx: -step, dy: 0) }
        case 124: editor.adjustFraming { FramingEditing.moved($0, dx: step, dy: 0) }
        case 125: editor.adjustFraming { FramingEditing.moved($0, dx: 0, dy: step) }
        case 126: editor.adjustFraming { FramingEditing.moved($0, dx: 0, dy: -step) }
        default:
            switch event.charactersIgnoringModifiers {
            case "=", "+": editor.adjustFraming { FramingEditing.zoomed($0, by: 1.1) }
            case "-": editor.adjustFraming { FramingEditing.zoomed($0, by: 1 / 1.1) }
            default: return false
            }
        }
        needsDisplay = true
        return true
    }

    override func magnify(with event: NSEvent) {
        guard editor.pictureTool == .frame else { return super.magnify(with: event) }
        editor.adjustFraming { FramingEditing.zoomed($0, by: 1 + event.magnification) }
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        guard editor.pictureTool == .frame, event.modifierFlags.contains(.option) else {
            return super.scrollWheel(with: event)
        }
        editor.adjustFraming { FramingEditing.zoomed($0, by: exp(event.scrollingDeltaY * 0.01)) }
        needsDisplay = true
    }

    func framingCursorRects() {
        let window = framingWindow
        addCursorRect(window, cursor: .openHand)
        let positions: [NSCursor.FrameResizePosition] = [.topLeft, .topRight, .bottomLeft, .bottomRight]
        for (corner, position) in zip(corners(of: window), positions) {
            addCursorRect(
                CGRect(x: corner.x - 9, y: corner.y - 9, width: 18, height: 18),
                cursor: .frameResize(position: position, directions: .all))
        }
    }

    /// The window as one VoiceOver element, whose actions move and zoom it; the inspector's Frame
    /// section has the same values as fields.
    func framingAccessibilityChildren() -> [Any] {
        let element = framingElement ?? PreviewFramingElement(in: self)
        framingElement = element
        element.update(in: self)
        return [element]
    }
}

// AppKit asks for these off the main actor's knowledge but always on the main thread.
nonisolated final class PreviewFramingElement: NSAccessibilityElement {
    private weak var gizmo: GizmoView?

    @MainActor
    init(in gizmo: GizmoView) {
        self.gizmo = gizmo
        super.init()
        setAccessibilityParent(gizmo)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Frame")
        setAccessibilityIdentifier("preview.frame")
        setAccessibilityHelp("The part of the shot the finished video shows. The actions move and zoom it.")
        let actions: [(String, (CameraFraming) -> CameraFraming)] = [
            ("Zoom In", { FramingEditing.zoomed($0, by: 1.1) }),
            ("Zoom Out", { FramingEditing.zoomed($0, by: 1 / 1.1) }),
            ("Move Left", { FramingEditing.moved($0, dx: -0.05, dy: 0) }),
            ("Move Right", { FramingEditing.moved($0, dx: 0.05, dy: 0) }),
            ("Move Up", { FramingEditing.moved($0, dx: 0, dy: -0.05) }),
            ("Move Down", { FramingEditing.moved($0, dx: 0, dy: 0.05) }),
        ]
        setAccessibilityCustomActions(
            actions.map { name, change in
                NSAccessibilityCustomAction(name: name) { [weak self] in
                    guard let gizmo = self?.gizmo else { return false }
                    return MainActor.assumeIsolated {
                        gizmo.editor.adjustFraming(change)
                        gizmo.needsDisplay = true
                        return true
                    }
                }
            })
    }

    @MainActor
    func update(in gizmo: GizmoView) {
        let framing = gizmo.editor.project.settings.framing
        let zoom = framing.zoom.formatted(.number.precision(.fractionLength(0...2)))
        let x = Int(((framing.centerX - 0.5) * 200).rounded())
        let y = Int(((framing.centerY - 0.5) * 200).rounded())
        setAccessibilityValue("Zoom \(zoom) times, \(x) percent across, \(y) percent down")
        if let window = gizmo.window {
            setAccessibilityFrame(window.convertToScreen(gizmo.convert(gizmo.framingWindow, to: nil)))
        }
    }
}

// MARK: - The bar and the way in

/// Across the top of the preview while a picture tool is open (#275, #276): which tool, what it
/// has done, its own controls, and the way out. A strip of its own rather than over the picture,
/// which is what is being judged.
struct PictureToolBar: View {
    @Bindable var editor: EditorModel

    var cropping: Bool { editor.pictureTool?.cropInput != nil }

    var body: some View {
        HStack(spacing: 12) {
            Picker("Tool", selection: Binding(get: { cropping }, set: { editor.switchPictureTool(toCrop: $0) })) {
                Label("Crop", systemImage: "crop").tag(true)
                Label("Frame", systemImage: "viewfinder").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Crop cuts this video's own picture; Frame chooses what every video shows")
            .accessibilityIdentifier("pictureTool.switch")
            if cropping { cropControls } else { frameSummary }
            Spacer()
            Button("Reset") { editor.resetPictureTool() }
                .disabled(!canReset)
                .help(cropping ? "Show the whole picture again, upright" : "Show the whole shot again")
                .accessibilityIdentifier("framing.reset")
            Button("Cancel") { editor.cancelPictureTool() }
                .keyboardShortcut(.cancelAction)
                .help("Put it back as it was (Escape)")
                .accessibilityIdentifier("framing.cancel")
            Button("Done") { editor.finishPictureTool() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .help("Keep it (Return)")
                .accessibilityIdentifier("framing.done")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    var canReset: Bool {
        if let id = editor.pictureTool?.cropInput {
            return editor.videoPicture(of: id) != VideoPicture(crop: .none, rotation: 0, mirror: .none)
        }
        return editor.project.settings.framing != .none
    }

    @ViewBuilder var frameSummary: some View {
        let framing = editor.project.settings.framing
        Text(
            framing.zoom > 1
                ? "Zoom \(framing.zoom.formatted(.number.precision(.fractionLength(2))))×. Drag the frame to move it."
                : "The whole shot. Drag a corner in, pinch, or press + to zoom."
        )
        .foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
    }

    @ViewBuilder var cropControls: some View {
        Picker(
            "Shape",
            selection: Binding(
                get: { if case .crop(_, let aspect) = editor.pictureTool { aspect } else { .free } },
                set: { editor.setCropAspect($0) })
        ) {
            ForEach(CropAspect.allCases) { Text($0.displayName).tag($0) }
        }
        .fixedSize()
        .help("Hold the crop to a shape; a fixed shape is applied at once, as large as it fits")
        .accessibilityIdentifier("crop.aspect")
        ControlGroup {
            Button {
                turn(by: -90)
            } label: {
                Label("Rotate Left", systemImage: "rotate.left")
            }
            .help("Turn the picture a quarter turn to the left")
            Button {
                turn(by: 90)
            } label: {
                Label("Rotate Right", systemImage: "rotate.right")
            }
            .help("Turn the picture a quarter turn to the right")
        }
        .fixedSize()
        ControlGroup {
            Button {
                flip(horizontal: true)
            } label: {
                Label("Flip Horizontal", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right")
            }
            .help("Mirror the picture left to right")
            Button {
                flip(horizontal: false)
            } label: {
                Label("Flip Vertical", systemImage: "arrow.up.and.down.righttriangle.up.righttriangle.down")
            }
            .help("Mirror the picture top to bottom")
        }
        .fixedSize()
    }

    func turn(by degrees: Double) {
        editor.adjustPicture { picture in
            var picture = picture
            picture.rotation = (picture.rotation + degrees).truncatingRemainder(dividingBy: 360)
            if picture.rotation < 0 { picture.rotation += 360 }
            return picture
        }
    }

    func flip(horizontal: Bool) {
        editor.adjustPicture { picture in
            var picture = picture
            if horizontal { picture.mirror.horizontal.toggle() } else { picture.mirror.vertical.toggle() }
            return picture
        }
    }
}

/// The way into the picture tools, at the left end of the transport under the preview: where Final
/// Cut Pro and DaVinci Resolve keep theirs, on the viewer's own bar (#275).
struct PictureToolMenu: View {
    @Bindable var editor: EditorModel

    var body: some View {
        Menu {
            Button("Crop Picture") { editor.beginCropping() }
                .disabled(!editor.canCropPicture)
            Button("Frame Picture") { editor.beginFraming() }
                .disabled(!editor.canFramePicture)
        } label: {
            Label("Picture Tools", systemImage: "crop")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .fixedSize()
        .labelStyle(.iconOnly)
        .disabled(editor.pictureTool != nil)
        .help("Crop (⇧C) or frame (⇧T) the picture on the preview")
        .accessibilityLabel("Picture Tools")
        .accessibilityIdentifier("preview.tools")
    }
}
