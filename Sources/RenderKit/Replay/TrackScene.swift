import CoreGraphics
import Foundation
import ProjectModel
import SceneKit
import TelemetryKit
import simd

/// How the replay is looked at.
public enum ReplayCamera: String, CaseIterable, Sendable, Codable {
    /// Behind and above the followed car, easing after it.
    case chase
    /// From a fixed post beside the track, the nearest one, turning to follow the car.
    case trackside
    /// Straight down, the followed car centred — or the whole circuit with nobody followed.
    case above
    /// From the driver's seat of the followed car.
    case inCar
    /// Wherever the user drags it: an orbit about the followed car or the circuit's centre.
    case free

    public var displayName: String {
        switch self {
        case .chase: "Chase"
        case .trackside: "Trackside"
        case .above: "Above"
        case .inCar: "In Car"
        case .free: "Free"
        }
    }
}

/// What the scene looks like: colours and sizes, with a palette for the laps.
public struct ReplayStyle: Sendable {
    public var sky = RGBAColor(red: 0.62, green: 0.74, blue: 0.86)
    public var ground = RGBAColor(red: 0.36, green: 0.45, blue: 0.27)
    public var road = RGBAColor(red: 0.2, green: 0.2, blue: 0.21)
    public var lineWidth = 0.25
    public var carLength = 4.3
    public var carWidth = 1.9
    /// The laps' colours, in the order they were chosen.
    public var palette: [RGBAColor] = [
        RGBAColor(red: 0.2, green: 0.5, blue: 1.0), RGBAColor(red: 0.95, green: 0.3, blue: 0.25),
        RGBAColor(red: 0.3, green: 0.8, blue: 0.4), RGBAColor(red: 1.0, green: 0.75, blue: 0.2),
        RGBAColor(red: 0.75, green: 0.45, blue: 1.0), RGBAColor(red: 0.2, green: 0.85, blue: 0.85),
        RGBAColor(red: 1.0, green: 0.5, blue: 0.75), RGBAColor(red: 0.85, green: 0.85, blue: 0.85),
    ]

    public init() {}

    public func color(forLap index: Int) -> RGBAColor { palette[index % max(palette.count, 1)] }
}

/// The road, the laps and the cars as a SceneKit scene (#414), and a camera that follows them.
/// Everything happens on the main actor: the window's display link and the exporter both call
/// `apply(time:dt:)` and then draw, so no node is touched from a render thread.
@MainActor public final class TrackScene {
    public let scene = SCNScene()
    public let field: ReplayField
    public let style: ReplayStyle
    public let cameraNode = SCNNode()
    public private(set) var camera: ReplayCamera = .chase
    /// The lap the camera follows; `nil` follows the leader (or shows the whole circuit from above).
    public var followed: UUID?
    /// The free camera's orbit about its target: yaw and pitch in radians, distance in metres.
    public var orbit = Orbit()

    public struct Orbit: Sendable, Equatable {
        public var yaw: Float = 0.6
        public var pitch: Float = 0.5
        public var distance: Float = 60
        public init() {}
    }

    private struct Car {
        let node: SCNNode
        let label: SCNNode
    }

    private var cars: [UUID: Car] = [:]
    private var posts: [SIMD3<Float>] = []
    private let centre: SIMD3<Float>
    private let extent: Float
    private var eased = SIMD3<Float>(0, 50, 100)
    private var easedTarget = SIMD3<Float>(0, 0, 0)
    private var blendFrom: (position: SIMD3<Float>, target: SIMD3<Float>)?
    private var blend: Float = 1
    private let lens = SCNCamera()
    private let labelImages: [UUID: CGImage]

    public init(field: ReplayField, style: ReplayStyle = ReplayStyle()) {
        self.field = field
        self.style = style
        let track = field.track
        let points = track.samples.map { SceneCoordinates.vector($0.position) }
        let low = points.reduce(SIMD3<Float>(repeating: .infinity), simd_min)
        let high = points.reduce(SIMD3<Float>(repeating: -.infinity), simd_max)
        centre = (low + high) / 2
        extent = max(high.x - low.x, high.z - low.z)
        var images: [UUID: CGImage] = [:]
        for (index, lap) in field.laps.enumerated() {
            images[lap.id] = SceneImages.label(lap.label, color: style.color(forLap: index))
        }
        labelImages = images

        scene.background.contents = style.sky.cgColor
        scene.fogColor = style.sky.cgColor
        scene.fogStartDistance = 800
        scene.fogEndDistance = 4_000
        addGround(low: low.y)
        addRoad(track)
        addCorners(track)
        addLaps()
        addLights()
        lens.zNear = 0.5
        lens.zFar = 6_000
        lens.fieldOfView = 60
        cameraNode.camera = lens
        cameraNode.position = SCNVector3(eased)
        scene.rootNode.addChildNode(cameraNode)
        posts = Self.tracksidePosts(track)
        set(camera: .chase, following: field.laps.min { $0.lapTime < $1.lapTime }?.id)
        apply(time: 0, dt: 1)
        blend = 1
    }

    // MARK: - Building

    private func addGround(low: Float) {
        let plane = SCNPlane(width: 20_000, height: 20_000)
        plane.firstMaterial?.diffuse.contents = style.ground.cgColor
        plane.firstMaterial?.lightingModel = .lambert
        let node = SCNNode(geometry: plane)
        node.eulerAngles.x = -.pi / 2
        node.position = SCNVector3(centre.x, low - 0.2, centre.z)
        node.name = "ground"
        scene.rootNode.addChildNode(node)
    }

    private func addRoad(_ track: TrackModel) {
        let road = RoadMesh.make(track: track).geometry()
        let asphalt = SCNMaterial()
        asphalt.diffuse.contents = style.road.cgColor
        asphalt.lightingModel = .lambert
        asphalt.isDoubleSided = true
        road.materials = [asphalt]
        let roadNode = SCNNode(geometry: road)
        roadNode.name = "road"
        scene.rootNode.addChildNode(roadNode)

        let kerbs = KerbMesh.make(track: track)
        guard kerbs.vertexCount > 0 else { return }
        let kerbGeometry = kerbs.geometry()
        let paint = SCNMaterial()
        paint.diffuse.contents = SceneImages.kerbStripes()
        paint.diffuse.wrapT = .repeat
        paint.diffuse.magnificationFilter = .nearest
        paint.lightingModel = .lambert
        paint.isDoubleSided = true
        kerbGeometry.materials = [paint]
        let kerbNode = SCNNode(geometry: kerbGeometry)
        kerbNode.name = "kerbs"
        scene.rootNode.addChildNode(kerbNode)
    }

    private func addCorners(_ track: TrackModel) {
        for (index, corner) in track.corners.enumerated() {
            let sample = track.sample(atDistance: corner.apexDistance)
            // Outside the corner: the left edge of a right-hander.
            let heading = sample.heading * .pi / 180
            let right = SIMD3(cos(heading), -sin(heading), 0)
            let outside = corner.turnsRight ? -right : right
            let foot = sample.position + outside * (sample.halfWidth + 3)
            guard let image = SceneImages.label("T\(index + 1)", color: RGBAColor(red: 1, green: 1, blue: 1)) else {
                continue
            }
            let marker = Self.billboard(image, height: 1.6)
            marker.position = SCNVector3(SceneCoordinates.vector(foot) + SIMD3(0, 2.5, 0))
            marker.name = "corner.\(index + 1)"
            let post = SCNNode(geometry: SCNCylinder(radius: 0.08, height: 2.5))
            post.geometry?.firstMaterial?.diffuse.contents = CGColor(gray: 0.9, alpha: 1)
            post.position = SCNVector3(SceneCoordinates.vector(foot) + SIMD3(0, 1.25, 0))
            scene.rootNode.addChildNode(post)
            scene.rootNode.addChildNode(marker)
        }
    }

    private func addLaps() {
        for (index, lap) in field.laps.enumerated() {
            let color = style.color(forLap: index)
            let ribbon = LapRibbon.make(points: lap.points, width: style.lineWidth, lift: 0.05).geometry()
            let paint = SCNMaterial()
            paint.diffuse.contents = color.cgColor
            paint.lightingModel = .constant
            paint.writesToDepthBuffer = false
            paint.isDoubleSided = true
            ribbon.materials = [paint]
            let line = SCNNode(geometry: ribbon)
            line.renderingOrder = 10
            line.name = "line.\(lap.id.uuidString)"
            scene.rootNode.addChildNode(line)

            let car = Self.car(color: color, length: style.carLength, width: style.carWidth)
            car.name = "car.\(lap.id.uuidString)"
            let label = Self.billboard(labelImages[lap.id], height: 1.2)
            label.position = SCNVector3(0, 2.4, 0)
            car.addChildNode(label)
            scene.rootNode.addChildNode(car)
            cars[lap.id] = Car(node: car, label: label)
        }
    }

    private func addLights() {
        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.intensity = 900
        sun.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 6, 0)
        scene.rootNode.addChildNode(sun)
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 350
        scene.rootNode.addChildNode(ambient)
    }

    // MARK: - Driving

    /// Which car the camera watches: the followed lap, else the leader.
    private func watched(at time: Double) -> ReplayLap? {
        if let followed, let lap = field.laps.first(where: { $0.id == followed }) { return lap }
        return field.standings(at: time).first?.lap
    }

    public func set(camera mode: ReplayCamera, following lapID: UUID?) {
        if mode != camera || lapID != followed {
            blendFrom = (eased, easedTarget)
            blend = 0
        }
        camera = mode
        followed = lapID
        lens.usesOrthographicProjection = mode == .above
        lens.zNear = mode == .inCar ? 0.1 : 0.5
        lens.fieldOfView = mode == .trackside ? 35 : 60
    }

    /// Moves every car to where it is `time` seconds into the replay, then the camera, `dt`
    /// seconds after the last call (for the easing).
    public func apply(time: Double, dt: Double) {
        var placements: [UUID: ReplayLap.Placement] = [:]
        for lap in field.laps {
            let placement = lap.position(atElapsed: time)
            placements[lap.id] = placement
            guard let car = cars[lap.id] else { continue }
            car.node.position = SCNVector3(SceneCoordinates.vector(placement.point))
            car.node.eulerAngles.y = CGFloat(SceneCoordinates.yaw(fromHeading: placement.heading))
        }
        let watchedLap = watched(at: time)
        let watchedPosition =
            watchedLap.flatMap { placements[$0.id] }.map { SceneCoordinates.vector($0.point) } ?? centre
        let heading = watchedLap.flatMap { placements[$0.id] }?.heading ?? 0
        let forward = SceneCoordinates.forward(ofHeading: heading)
        let up = SIMD3<Float>(0, 1, 0)
        let (wantedPosition, wantedTarget) = wanted(camera: camera, watched: watchedPosition, forward: forward)
        // Chase eases after the car; the others snap, except across a mode change, which blends.
        let step = Float(min(max(dt, 0), 0.5))
        if camera == .chase {
            let factor = 1 - exp(-step / 0.25)
            eased += (wantedPosition - eased) * factor
            easedTarget += (wantedTarget - easedTarget) * factor
        } else {
            eased = wantedPosition
            easedTarget = wantedTarget
        }
        var position = eased
        var target = easedTarget
        if blend < 1, let blendFrom {
            blend = min(1, blend + step / 0.6)
            let mix = blend * blend * (3 - 2 * blend)
            position = blendFrom.position + (eased - blendFrom.position) * mix
            target = blendFrom.target + (easedTarget - blendFrom.target) * mix
        }
        cameraNode.position = SCNVector3(position)
        cameraNode.look(at: SCNVector3(target), up: SCNVector3(up), localFront: SCNVector3(0, 0, -1))
        // Labels read the same size near and far.
        for car in cars.values {
            let distance = simd_length(SIMD3<Float>(car.node.position) - position)
            let scale = CGFloat(max(1, distance / 18))
            car.label.scale = SCNVector3(scale, scale, scale)
        }
    }

    /// Where a car is in the scene, for a view that wants to point at it.
    public func position(of lapID: UUID) -> SIMD3<Float>? { cars[lapID].map { SIMD3<Float>($0.node.position) } }

    /// The replay time a jump to turn `index` (0-based) lands on.
    public func time(toCorner index: Int) -> Double? { field.time(toCorner: index, following: followed) }

    public var cornerCount: Int { field.track.corners.count }

    /// Where the camera wants to be and look for `camera`, given the watched car's place and
    /// the way it faces.
    private func wanted(camera: ReplayCamera, watched watchedPosition: SIMD3<Float>, forward: SIMD3<Float>)
        -> (position: SIMD3<Float>, target: SIMD3<Float>)
    {
        let up = SIMD3<Float>(0, 1, 0)
        var wantedPosition: SIMD3<Float>
        var wantedTarget = watchedPosition + up * 1
        switch camera {
        case .chase:
            wantedPosition = watchedPosition - forward * 14 + up * 5
        case .trackside:
            let post = posts.min { simd_length($0 - watchedPosition) < simd_length($1 - watchedPosition) }
            wantedPosition = post ?? watchedPosition + up * 20
        case .above:
            if followed != nil || field.laps.count == 1 {
                wantedPosition = watchedPosition + up * 250
                wantedTarget = watchedPosition
                lens.orthographicScale = 110
            } else {
                wantedPosition = centre + up * 500
                wantedTarget = centre
                lens.orthographicScale = Double(extent) * 0.55 + 30
            }
            // A look straight down has no up; lean a hair to the south of vertical.
            wantedPosition.z += 0.5
        case .inCar:
            wantedPosition = watchedPosition + forward * 0.3 + up * 1.1
            wantedTarget = wantedPosition + forward * 30
        case .free:
            let about = followed != nil ? watchedPosition : centre
            let yaw = orbit.yaw
            let pitch = min(max(orbit.pitch, 0.05), Float.pi / 2 - 0.05)
            let offset = SIMD3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * orbit.distance
            wantedPosition = about + offset
            wantedTarget = about
        }
        return (wantedPosition, wantedTarget)
    }
}

// MARK: - Pieces of the scene

extension TrackScene {
    /// A wedge of boxes on four wheels, forward along −z, in `color`.
    static func car(color: RGBAColor, length: Double, width: Double) -> SCNNode {
        let node = SCNNode()
        let paint = SCNMaterial()
        paint.diffuse.contents = color.cgColor
        paint.lightingModel = .blinn
        let body = SCNBox(width: width, height: 0.5, length: length, chamferRadius: 0.1)
        body.materials = [paint]
        let bodyNode = SCNNode(geometry: body)
        bodyNode.position = SCNVector3(0, 0.55, 0)
        node.addChildNode(bodyNode)
        let cabin = SCNBox(width: width * 0.8, height: 0.45, length: length * 0.45, chamferRadius: 0.12)
        let glass = SCNMaterial()
        glass.diffuse.contents = CGColor(gray: 0.15, alpha: 1)
        glass.lightingModel = .blinn
        cabin.materials = [glass]
        let cabinNode = SCNNode(geometry: cabin)
        cabinNode.position = SCNVector3(0, 1.0, -length * 0.02)
        node.addChildNode(cabinNode)
        let rubber = SCNMaterial()
        rubber.diffuse.contents = CGColor(gray: 0.08, alpha: 1)
        for (x, z) in [(-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0), (1.0, 1.0)] {
            let wheel = SCNCylinder(radius: 0.32, height: 0.25)
            wheel.materials = [rubber]
            let wheelNode = SCNNode(geometry: wheel)
            wheelNode.eulerAngles.z = .pi / 2
            wheelNode.position = SCNVector3(x * width / 2, 0.32, z * length * 0.32)
            node.addChildNode(wheelNode)
        }
        return node.flattenedClone()
    }

    /// A picture that always faces the camera, `height` metres tall.
    static func billboard(_ image: CGImage?, height: Double) -> SCNNode {
        let aspect = image.map { Double($0.width) / Double(max($0.height, 1)) } ?? 3
        let plane = SCNPlane(width: height * aspect, height: height)
        let material = SCNMaterial()
        material.diffuse.contents = image
        material.lightingModel = .constant
        material.isDoubleSided = true
        material.readsFromDepthBuffer = false
        material.transparencyMode = .aOne
        plane.materials = [material]
        let node = SCNNode(geometry: plane)
        node.renderingOrder = 20
        let constraint = SCNBillboardConstraint()
        constraint.freeAxes = .Y
        node.constraints = [constraint]
        return node
    }

    /// Camera posts every 150 m, 25 m to the left of the road, 4 m up.
    static func tracksidePosts(_ track: TrackModel) -> [SIMD3<Float>] {
        stride(from: 0.0, to: track.lengthMeters, by: 150).map { distance in
            let sample = track.sample(atDistance: distance)
            let heading = sample.heading * .pi / 180
            let right = SIMD3(cos(heading), -sin(heading), 0)
            return SceneCoordinates.vector(sample.position - right * (sample.halfWidth + 25)) + SIMD3(0, 4, 0)
        }
    }
}
