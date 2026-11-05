import AppKit
import RenderKit
import SceneKit
import SwiftUI

/// The SceneKit view with the keys and gestures a replay wants: Space plays and pauses, ← and →
/// step, 1–5 pick a camera, a drag orbits the free camera, a scroll or pinch zooms it.
final class ReplaySceneView: SCNView {
    var onKey: ((String) -> Bool)?
    var onOrbit: ((Float, Float) -> Void)?
    var onZoom: ((Float) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let key = event.charactersIgnoringModifiers ?? ""
        let handled: Bool
        switch event.keyCode {
        case 123: handled = onKey?("left") ?? false
        case 124: handled = onKey?("right") ?? false
        default: handled = onKey?(key) ?? false
        }
        if !handled { super.keyDown(with: event) }
    }

    override func mouseDragged(with event: NSEvent) {
        onOrbit?(Float(event.deltaX), Float(event.deltaY))
    }

    override func scrollWheel(with event: NSEvent) {
        onZoom?(Float(-event.scrollingDeltaY))
    }

    override func magnify(with event: NSEvent) {
        onZoom?(Float(-event.magnification * 40))
    }
}

/// The scene in SwiftUI, driven by a display link on the main actor: every frame the model's
/// clock advances and the scene is told the time, then SceneKit draws it.
struct ReplaySceneHost: NSViewRepresentable {
    let model: ReplayModel

    func makeNSView(context: Context) -> ReplaySceneView {
        let view = ReplaySceneView(
            frame: .zero, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = false
        view.rendersContinuously = true
        view.preferredFramesPerSecond = 60
        view.backgroundColor = .black
        view.setAccessibilityLabel("3D lap replay")
        view.setAccessibilityRole(.group)
        view.setAccessibilityIdentifier("replay.scene")
        let model = model
        view.onKey = { key in
            switch key {
            case " ": model.togglePlaying()
            case "left": model.step(by: -1)
            case "right": model.step(by: 1)
            case "1": model.camera = .chase
            case "2": model.camera = .trackside
            case "3": model.camera = .above
            case "4": model.camera = .inCar
            case "5": model.camera = .free
            default: return false
            }
            return true
        }
        view.onOrbit = { dx, dy in model.orbit(byX: dx, y: dy) }
        view.onZoom = { delta in model.zoom(by: delta) }
        context.coordinator.start(view: view, model: model)
        attach(view)
        return view
    }

    func updateNSView(_ view: ReplaySceneView, context: Context) {
        attach(view)
    }

    static func dismantleNSView(_ view: ReplaySceneView, coordinator: Coordinator) {
        coordinator.stop()
    }

    private func attach(_ view: ReplaySceneView) {
        guard let scene = model.scene else {
            view.scene = nil
            return
        }
        if view.scene !== scene.scene {
            view.scene = scene.scene
            view.pointOfView = scene.cameraNode
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Owns the display link; a frame is one `tick` on the model.
    @MainActor final class Coordinator {
        private var link: CADisplayLink?
        private var model: ReplayModel?
        private var last: CFTimeInterval?

        func start(view: NSView, model: ReplayModel) {
            self.model = model
            let link = view.displayLink(target: self, selector: #selector(frame(_:)))
            link.add(to: .main, forMode: .common)
            self.link = link
        }

        func stop() {
            link?.invalidate()
            link = nil
            model = nil
        }

        @objc private func frame(_ link: CADisplayLink) {
            let now = link.timestamp
            let dt = last.map { min(max(now - $0, 0), 0.25) } ?? 1 / 60
            last = now
            model?.tick(dt: dt)
        }
    }
}
