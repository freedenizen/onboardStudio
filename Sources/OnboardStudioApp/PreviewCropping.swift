import AppKit
import ProjectModel

// MARK: - Cropping on the preview (#276), and the dispatch between the picture tools

/// While Crop is on, the preview shows the video's whole picture, turned and flipped as it will
/// be, and this draws the crop over it with the cut-away parts dimmed. Drag an edge or a corner to
/// cut it back, inside to move the crop; the arrow keys move it; Return is Done, Escape Cancel.
extension GizmoView {
    func drawPictureTool(in context: CGContext) {
        if editor.pictureTool?.cropInput != nil { drawCropping(in: context) } else { drawFraming(in: context) }
    }

    func pictureToolMouseDown(at point: CGPoint) {
        if editor.pictureTool?.cropInput != nil { croppingMouseDown(at: point) } else { framingMouseDown(at: point) }
    }

    func pictureToolMouseDragged(to point: CGPoint) {
        if case .crop = framingDrag?.part { croppingMouseDragged(to: point) } else { framingMouseDragged(to: point) }
    }

    func pictureToolKeyDown(_ event: NSEvent) -> Bool {
        editor.pictureTool?.cropInput != nil ? croppingKeyDown(event) : framingKeyDown(event)
    }

    func pictureToolCursorRects() {
        if editor.pictureTool?.cropInput != nil { croppingCursorRects() } else { framingCursorRects() }
    }

    func pictureToolAccessibilityChildren() -> [Any] {
        editor.pictureTool?.cropInput != nil ? croppingAccessibilityChildren() : framingAccessibilityChildren()
    }

    // MARK: Crop

    var croppedPicture: VideoPicture? { editor.pictureTool?.cropInput.flatMap(editor.videoPicture) }

    /// The crop as the preview shows it (turned and flipped), in unit fractions of the picture.
    var shownCrop: CropInsets? {
        croppedPicture.map { CropEditing.displayed($0.crop, rotation: $0.rotation, mirror: $0.mirror) }
    }

    /// The crop's rectangle on the preview, in view coordinates.
    var cropWindow: CGRect {
        let target = framingTarget
        guard let shownCrop else { return target }
        let region = CropEditing.region(of: shownCrop)
        return CGRect(
            x: target.minX + region.x * target.width, y: target.minY + region.y * target.height,
            width: region.width * target.width, height: region.height * target.height)
    }

    func drawCropping(in context: CGContext) {
        drawDimmed(outside: cropWindow, in: framingTarget, context: context)
        drawToolWindow(cropWindow, in: context, edgeHandles: true)
    }

    /// Dims `target` outside `window`: what is being cut, still visible.
    func drawDimmed(outside window: CGRect, in target: CGRect, context: CGContext) {
        context.setFillColor(NSColor.black.withAlphaComponent(0.55).cgColor)
        for piece in [
            CGRect(x: target.minX, y: target.minY, width: target.width, height: window.minY - target.minY),
            CGRect(x: target.minX, y: window.maxY, width: target.width, height: target.maxY - window.maxY),
            CGRect(x: target.minX, y: window.minY, width: window.minX - target.minX, height: window.height),
            CGRect(x: window.maxX, y: window.minY, width: target.maxX - window.maxX, height: window.height),
        ] where piece.width > 0 && piece.height > 0 {
            context.fill(piece)
        }
    }

    /// The tool's rectangle: thirds, a white edge on a dark one so it reads over any footage, and
    /// handles at the corners (and the middle of each edge, for a crop).
    func drawToolWindow(_ window: CGRect, in context: CGContext, edgeHandles: Bool) {
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.35).cgColor)
        context.setLineWidth(1)
        for third in [1.0 / 3, 2.0 / 3] {
            context.strokeLineSegments(between: [
                CGPoint(x: window.minX + window.width * third, y: window.minY),
                CGPoint(x: window.minX + window.width * third, y: window.maxY),
                CGPoint(x: window.minX, y: window.minY + window.height * third),
                CGPoint(x: window.maxX, y: window.minY + window.height * third),
            ])
        }
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.6).cgColor)
        context.setLineWidth(4)
        context.stroke(window)
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(2)
        context.stroke(window)
        var points = corners(of: window)
        if edgeHandles {
            points += [
                CGPoint(x: window.midX, y: window.minY), CGPoint(x: window.midX, y: window.maxY),
                CGPoint(x: window.minX, y: window.midY), CGPoint(x: window.maxX, y: window.midY),
            ]
        }
        for point in points {
            let square = CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)
            context.setFillColor(NSColor.white.cgColor)
            context.fill(square)
            context.setStrokeColor(NSColor.black.withAlphaComponent(0.6).cgColor)
            context.setLineWidth(1)
            context.stroke(square)
        }
    }

    /// Which part of the crop a view point is on.
    func cropHandle(at point: CGPoint) -> ObjectHandle? {
        let target = framingTarget
        guard target.width > 0, target.height > 0, let shownCrop else { return nil }
        let unit = CGPoint(x: (point.x - target.minX) / target.width, y: (point.y - target.minY) / target.height)
        return CropEditing.handle(
            at: unit, in: CropEditing.region(of: shownCrop),
            tolerance: CGSize(width: 8 / target.width, height: 8 / target.height))
    }

    func croppingMouseDown(at point: CGPoint) {
        guard let handle = cropHandle(at: point), let picture = croppedPicture else { return }
        framingDrag = FramingDrag(part: .crop(handle), startPicture: picture, startPoint: point)
        if handle == .body { NSCursor.closedHand.push() }
    }

    func croppingMouseDragged(to point: CGPoint) {
        guard let drag = framingDrag, case .crop(let handle) = drag.part, let start = drag.startPicture,
            let id = editor.pictureTool?.cropInput
        else { return }
        let target = framingTarget
        guard target.width > 0, target.height > 0 else { return }
        let dx = (point.x - drag.startPoint.x) / target.width
        let dy = (point.y - drag.startPoint.y) / target.height
        let pictureAspect = editor.shownPictureAspect(of: id) ?? 16.0 / 9
        let ratio: Double? =
            if case .crop(_, let aspect) = editor.pictureTool { aspect.ratio(picture: pictureAspect) } else { nil }
        editor.adjustPicture { picture in
            let shown = CropEditing.displayed(start.crop, rotation: start.rotation, mirror: start.mirror)
            let dragged = CropEditing.dragged(
                shown, handle: handle, dx: dx, dy: dy, ratio: ratio, pictureAspect: pictureAspect)
            var picture = picture
            picture.crop = CropEditing.source(dragged, rotation: start.rotation, mirror: start.mirror)
            return picture
        }
        needsDisplay = true
    }

    func croppingKeyDown(_ event: NSEvent) -> Bool {
        let step = event.modifierFlags.contains(.shift) ? 0.1 : 0.01
        let move: (Double, Double)
        switch event.keyCode {
        case 36, 76:
            editor.finishPictureTool()
            return true  // return, enter
        case 53:
            editor.cancelPictureTool()
            return true  // escape
        case 123: move = (-step, 0)
        case 124: move = (step, 0)
        case 125: move = (0, step)
        case 126: move = (0, -step)
        default: return false
        }
        editor.adjustPicture { picture in
            let shown = CropEditing.displayed(picture.crop, rotation: picture.rotation, mirror: picture.mirror)
            let moved = CropEditing.dragged(shown, handle: .body, dx: move.0, dy: move.1)
            var picture = picture
            picture.crop = CropEditing.source(moved, rotation: picture.rotation, mirror: picture.mirror)
            return picture
        }
        needsDisplay = true
        return true
    }

    func croppingCursorRects() {
        let window = cropWindow
        addCursorRect(window.insetBy(dx: 8, dy: 8), cursor: .openHand)
        let edges: [(CGRect, NSCursor.FrameResizePosition)] = [
            (CGRect(x: window.minX - 8, y: window.minY + 8, width: 16, height: max(window.height - 16, 0)), .left),
            (CGRect(x: window.maxX - 8, y: window.minY + 8, width: 16, height: max(window.height - 16, 0)), .right),
            (CGRect(x: window.minX + 8, y: window.minY - 8, width: max(window.width - 16, 0), height: 16), .top),
            (CGRect(x: window.minX + 8, y: window.maxY - 8, width: max(window.width - 16, 0), height: 16), .bottom),
        ]
        for (rect, position) in edges {
            addCursorRect(rect, cursor: .frameResize(position: position, directions: .all))
        }
        let positions: [NSCursor.FrameResizePosition] = [.topLeft, .topRight, .bottomLeft, .bottomRight]
        for (corner, position) in zip(corners(of: window), positions) {
            addCursorRect(
                CGRect(x: corner.x - 9, y: corner.y - 9, width: 18, height: 18),
                cursor: .frameResize(position: position, directions: .all))
        }
    }

    func croppingAccessibilityChildren() -> [Any] {
        let element = cropElement ?? PreviewCropElement(in: self)
        cropElement = element
        element.update(in: self)
        return [element]
    }
}

// AppKit asks for these off the main actor's knowledge but always on the main thread.
nonisolated final class PreviewCropElement: NSAccessibilityElement {
    private weak var gizmo: GizmoView?

    @MainActor
    init(in gizmo: GizmoView) {
        self.gizmo = gizmo
        super.init()
        setAccessibilityParent(gizmo)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Crop")
        setAccessibilityIdentifier("preview.crop")
        setAccessibilityHelp("What this video keeps of its picture. The actions cut each edge back or give it back.")
        struct EdgeAction {
            let name: String
            let handle: ObjectHandle
            let dx: Double
            let dy: Double
        }
        let edges = [
            EdgeAction(name: "Cut Top", handle: .top, dx: 0, dy: 0.02),
            EdgeAction(name: "Restore Top", handle: .top, dx: 0, dy: -0.02),
            EdgeAction(name: "Cut Bottom", handle: .bottom, dx: 0, dy: -0.02),
            EdgeAction(name: "Restore Bottom", handle: .bottom, dx: 0, dy: 0.02),
            EdgeAction(name: "Cut Left", handle: .left, dx: 0.02, dy: 0),
            EdgeAction(name: "Restore Left", handle: .left, dx: -0.02, dy: 0),
            EdgeAction(name: "Cut Right", handle: .right, dx: -0.02, dy: 0),
            EdgeAction(name: "Restore Right", handle: .right, dx: 0.02, dy: 0),
        ]
        setAccessibilityCustomActions(
            edges.map { edge in
                NSAccessibilityCustomAction(name: edge.name) { [weak self] in
                    guard let gizmo = self?.gizmo else { return false }
                    return MainActor.assumeIsolated {
                        gizmo.editor.adjustPicture { picture in
                            let shown = CropEditing.displayed(
                                picture.crop, rotation: picture.rotation, mirror: picture.mirror)
                            var picture = picture
                            picture.crop = CropEditing.source(
                                CropEditing.dragged(shown, handle: edge.handle, dx: edge.dx, dy: edge.dy),
                                rotation: picture.rotation, mirror: picture.mirror)
                            return picture
                        }
                        gizmo.needsDisplay = true
                        return true
                    }
                }
            })
    }

    @MainActor
    func update(in gizmo: GizmoView) {
        if let crop = gizmo.shownCrop {
            let percent = { (value: Double) in Int((value * 100).rounded()) }
            setAccessibilityValue(
                "Top \(percent(crop.top)), bottom \(percent(crop.bottom)), left \(percent(crop.left)), "
                    + "right \(percent(crop.right)) percent cut")
        }
        if let window = gizmo.window {
            setAccessibilityFrame(window.convertToScreen(gizmo.convert(gizmo.cropWindow, to: nil)))
        }
    }
}
