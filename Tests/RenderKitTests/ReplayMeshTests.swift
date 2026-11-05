import Foundation
import TelemetryKit
import Testing
import simd

@testable import RenderKit

@Suite("Replay meshes (#414)")
struct ReplayMeshTests {
    /// A square-ish loop of 40 samples, 4 m apart, 6 m wide, flat; kerbs on samples 10–14 left.
    static func track(elevated: Bool = false) -> TrackModel {
        let count = 40
        let step = 4.0
        let samples = (0..<count).map { index -> TrackModel.Sample in
            let angle = Double(index) / Double(count) * 2 * .pi
            let radius = Double(count) * step / (2 * .pi)
            // Clockwise round the loop, starting due east of the centre heading south.
            let position = SIMD3(radius * cos(angle), -radius * sin(angle), elevated ? 3 * sin(angle) + 3 : 0)
            let heading = (180 + angle * 180 / .pi).truncatingRemainder(dividingBy: 360)
            return TrackModel.Sample(
                position: position, heading: heading, halfWidth: 3, kerbLeft: (10...14).contains(index),
                kerbRight: index == 20)
        }
        return TrackModel(
            plane: .init(latitude0: 0, longitude0: 0), stepMeters: step, lengthMeters: Double(count) * step,
            samples: samples, corners: [], hasElevation: elevated)
    }

    @Test func theRoadIsAClosedStripTwoVerticesWide() {
        let track = Self.track()
        let mesh = RoadMesh.make(track: track)
        #expect(mesh.vertexCount == (track.samples.count + 1) * 2, "a pair per sample, and the seam pair")
        #expect(mesh.triangleCount == track.samples.count * 2)
        #expect(mesh.indices.allSatisfy { Int($0) < mesh.vertexCount })
        #expect(mesh.normals.allSatisfy { abs($0.y - 1) < 1e-5 }, "flat: every normal straight up")
        // The first pair straddles the first sample, 6 m apart, at road level.
        let left = mesh.positions[0]
        let right = mesh.positions[1]
        #expect(abs(simd_length(left - right) - 6) < 1e-4)
        #expect(left.y == 0 && right.y == 0)
        // Heading south at the first sample: right is west (−x).
        #expect(right.x < left.x)
        // Counter-clockwise from above: the first triangle's normal (y of the cross product) is up.
        let a = mesh.positions[Int(mesh.indices[0])]
        let b = mesh.positions[Int(mesh.indices[1])]
        let c = mesh.positions[Int(mesh.indices[2])]
        #expect(simd_cross(b - a, c - a).y > 0, "front face up")
        // The seam pair sits on the first pair.
        let seamLeft = mesh.positions[mesh.vertexCount - 2]
        #expect(simd_length(seamLeft - left) < 1e-4)
        // UVs run along the strip in metres ÷ 10.
        #expect(mesh.uvs[2].y == Float(track.stepMeters) / 10 && mesh.uvs[0].x == 0 && mesh.uvs[1].x == 1)
    }

    @Test func slopesTiltTheNormalsAndTheSceneIsYUp() {
        let mesh = RoadMesh.make(track: Self.track(elevated: true))
        #expect(mesh.positions.contains { $0.y > 5 }, "up is y")
        #expect(mesh.normals.allSatisfy { $0.y > 0.9 }, "a gentle hill still faces up")
        #expect(mesh.normals.contains { abs($0.x) > 1e-3 || abs($0.z) > 1e-3 }, "and leans with the slope")
        // The coordinate mapping: east → x, up → y, north → −z.
        #expect(SceneCoordinates.vector(SIMD3(1, 2, 3)) == SIMD3<Float>(1, 3, -2))
        // A heading of 90° (east): the node yaws −90° and faces +x.
        let east = SceneCoordinates.forward(ofHeading: 90)
        #expect(abs(east.x - 1) < 1e-6 && abs(east.z) < 1e-6)
        #expect(abs(SceneCoordinates.yaw(fromHeading: 90) + .pi / 2) < 1e-6)
        let north = SceneCoordinates.forward(ofHeading: 0)
        #expect(abs(north.z + 1) < 1e-6)
    }

    @Test func kerbsOnlyWhereFlaggedAndOutsideTheEdge() {
        let track = Self.track()
        let mesh = KerbMesh.make(track: track)
        // Left kerb on 5 samples (a run of 5 pairs, 4 quads) and a right kerb on one sample
        // (a single pair, no quad).
        #expect(mesh.vertexCount == 12)
        #expect(mesh.triangleCount == 8)
        let road = RoadMesh.make(track: track)
        // Every kerb vertex is outside the road's edge and a touch above it.
        let radius = Double(track.samples.count) * track.stepMeters / (2 * .pi)
        for position in mesh.positions {
            let fromCentre = sqrt(Double(position.x * position.x + position.z * position.z))
            #expect(fromCentre > radius + 3 - 0.01 || fromCentre < radius - 3 + 0.01, "outside an edge: \(fromCentre)")
            #expect(abs(Double(position.y) - KerbMesh.lift) < 1e-5)
        }
        #expect(road.positions.allSatisfy { $0.y == 0 })
        #expect(KerbMesh.make(track: Self.trackWithoutKerbs()).vertexCount == 0)
    }

    static func trackWithoutKerbs() -> TrackModel {
        let base = track()
        return TrackModel(
            plane: base.plane, stepMeters: base.stepMeters, lengthMeters: base.lengthMeters,
            samples: base.samples.map { sample in
                var plain = sample
                plain.kerbLeft = false
                plain.kerbRight = false
                return plain
            }, corners: [], hasElevation: false)
    }

    @Test func aLapLineIsAThinRibbonLiftedOffTheRoad() {
        let points: [SIMD3<Double>] = (0..<10).map { SIMD3(Double($0) * 2, 0, 0.05) }  // due east
        let mesh = LapRibbon.make(points: points, width: 0.3, lift: 0.05)
        #expect(mesh.vertexCount == 20 && mesh.triangleCount == 18)
        let left = mesh.positions[0]
        let right = mesh.positions[1]
        #expect(abs(simd_length(left - right) - 0.3) < 1e-5)
        #expect(abs(left.y - 0.1) < 1e-5, "its own 5 cm plus the lift")
        // Heading east, right is south (+z in the scene).
        #expect(right.z > left.z)
        #expect(LapRibbon.make(points: [SIMD3(0, 0, 0)]).vertexCount == 0)
    }
}
