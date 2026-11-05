import Foundation
import SceneKit
import TelemetryKit
import Testing
import simd

@testable import RenderKit

@Suite("Track scene (#414)")
struct TrackSceneTests {
    /// Two laps of the square-ish loop at different speeds, as a replay field.
    static func field() throws -> ReplayField {
        let track = ReplayMeshTests.track(elevated: true)
        let profiles = try [30.0, 24.0].map { speed in try Self.profile(on: track, speed: speed) }
        let laps = profiles.enumerated().compactMap { index, profile in
            ReplayLap(profile: profile, on: track, label: index == 0 ? "Fast" : "Steady")
        }
        return ReplayField(track: track, laps: laps)
    }

    /// A lap driven round the model's own centreline at a steady speed, 2 m apart.
    static func profile(on track: TrackModel, speed: Double) throws -> LapProfile {
        let step = 2.0
        let count = Int(track.lengthMeters / step)
        var latitudes: [Double] = []
        var longitudes: [Double] = []
        var times: [Double] = []
        var distances: [Double] = []
        for index in 0...count {
            let distance = Double(index) * step
            let sample = track.sample(atDistance: distance)
            let coordinate = track.plane.coordinate(at: sample.point)
            latitudes.append(coordinate.latitude)
            longitudes.append(coordinate.longitude)
            times.append(distance / speed)
            distances.append(distance)
        }
        let channels = [
            Channel(
                role: .latitude, name: "Latitude", unit: .degrees, times: times, values: latitudes,
                interpolation: .linear),
            Channel(
                role: .longitude, name: "Longitude", unit: .degrees, times: times, values: longitudes,
                interpolation: .linear),
            Channel(
                role: .distance, name: "Distance", unit: .meters, times: times, values: distances,
                interpolation: .linear),
        ]
        let session = TelemetrySession(info: SessionInfo(sourceFormat: "test"), channels: channels, laps: [])
        let window = LapProfile.Window(start: 0, end: times.last ?? 1)
        return try #require(LapProfile(window: window, in: session, label: "Lap", stepMeters: step))
    }

    @MainActor @Test func theSceneHoldsTheRoadTheLapsAndTheCars() throws {
        let field = try Self.field()
        let scene = TrackScene(field: field)
        let root = scene.scene.rootNode
        #expect(root.childNode(withName: "road", recursively: false) != nil)
        #expect(root.childNode(withName: "kerbs", recursively: false) != nil)
        #expect(root.childNode(withName: "ground", recursively: false) != nil)
        #expect(root.childNodes.filter { $0.name?.hasPrefix("car.") == true }.count == 2)
        #expect(root.childNodes.filter { $0.name?.hasPrefix("line.") == true }.count == 2)
        let road = try #require(root.childNode(withName: "road", recursively: false)?.geometry)
        #expect(road.sources(for: .vertex).first?.vectorCount == (field.track.samples.count + 1) * 2)
        #expect(road.sources(for: .normal).count == 1 && road.sources(for: .texcoord).count == 1)
        #expect(road.elements.first?.primitiveCount == field.track.samples.count * 2)
        #expect(scene.cameraNode.camera != nil && scene.camera == .chase)
        #expect(scene.followed == field.laps[0].id, "the quicker lap is followed to begin with")
        #expect(scene.cornerCount == 0, "the toy loop names no corners")
    }

    @MainActor @Test func carsMoveWithTimeAndTheCameraFollows() throws {
        let field = try Self.field()
        let scene = TrackScene(field: field)
        let fast = field.laps[0]
        let before = try #require(scene.position(of: fast.id))
        scene.apply(time: 2, dt: 1 / 60)
        let after = try #require(scene.position(of: fast.id))
        #expect(
            simd_length(after - before) > 40, "30 m/s for two seconds round a 25 m bend: a 60 m arc, a shorter chord")
        #expect(
            abs(
                after.y - 0.05
                    - Float(
                        field.track.elevation(
                            at: SIMD2(fast.position(atElapsed: 2).point.x, fast.position(atElapsed: 2).point.y)))) < 0.2
        )
        // Chase: behind the car, above it, easing towards it over a few frames.
        for _ in 0..<120 { scene.apply(time: 2, dt: 1 / 60) }
        let camera = SIMD3<Float>(scene.cameraNode.position)
        #expect(camera.y > after.y + 3 && camera.y < after.y + 7)
        #expect(simd_length(SIMD2(camera.x - after.x, camera.z - after.z)) > 10)
        // Above: straight down over the car, orthographic.
        scene.set(camera: .above, following: fast.id)
        for _ in 0..<60 { scene.apply(time: 2, dt: 1 / 60) }
        #expect(scene.cameraNode.camera?.usesOrthographicProjection == true)
        #expect(SIMD3<Float>(scene.cameraNode.position).y > after.y + 200)
        // In car: at the car, looking its way.
        scene.set(camera: .inCar, following: fast.id)
        for _ in 0..<60 { scene.apply(time: 2, dt: 1 / 60) }
        #expect(simd_length(SIMD3<Float>(scene.cameraNode.position) - after) < 2)
        #expect(scene.cameraNode.camera?.usesOrthographicProjection == false)
        // Free: an orbit about the car at the asked distance.
        scene.set(camera: .free, following: fast.id)
        scene.orbit.distance = 40
        for _ in 0..<60 { scene.apply(time: 2, dt: 1 / 60) }
        #expect(abs(simd_length(SIMD3<Float>(scene.cameraNode.position) - after) - 40) < 0.5)
        // Nobody followed from above: the whole circuit from the centre.
        scene.set(camera: .above, following: nil)
        for _ in 0..<60 { scene.apply(time: 2, dt: 1 / 60) }
        #expect(SIMD3<Float>(scene.cameraNode.position).y > 400)
        #expect(scene.time(toCorner: 0) == nil)
    }
}
