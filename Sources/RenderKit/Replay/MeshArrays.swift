import Foundation
import TelemetryKit
import simd

/// Triangles ready for a GPU, with nothing of SceneKit in them (#414): positions, normals,
/// texture coordinates and indices, built from a `TrackModel` and tested as arithmetic. The
/// SceneKit side turns them into geometry; a Metal side could too.
public struct MeshArrays: Sendable, Equatable {
    public var positions: [SIMD3<Float>] = []
    public var normals: [SIMD3<Float>] = []
    /// u across the strip (0 left, 1 right), v along it in metres ÷ `vScale`.
    public var uvs: [SIMD2<Float>] = []
    public var indices: [UInt32] = []

    public init() {}

    public var vertexCount: Int { positions.count }
    public var triangleCount: Int { indices.count / 3 }

    /// Appends a quad between the last pair of vertices and this pair: `left` and `right` are
    /// the new pair's indices; the previous pair is the two before them.
    mutating func join(previousLeft: UInt32, previousRight: UInt32, left: UInt32, right: UInt32) {
        // Counter-clockwise seen from above (SceneKit's front face): round the quad
        // previous-left → previous-right → right → left, split along the previous-right–left diagonal.
        indices += [previousLeft, previousRight, left, left, previousRight, right]
    }

    mutating func append(_ other: MeshArrays) {
        let base = UInt32(positions.count)
        positions += other.positions
        normals += other.normals
        uvs += other.uvs
        indices += other.indices.map { $0 + base }
    }
}

/// East/north/up metres into SceneKit's right-handed, Y-up world: x east, y up, z south.
public enum SceneCoordinates {
    public static func vector(_ enu: SIMD3<Double>) -> SIMD3<Float> {
        SIMD3(Float(enu.x), Float(enu.z), Float(-enu.y))
    }

    /// A heading in degrees clockwise from north as a rotation about the up axis, radians, for a
    /// node whose own forward is −z (north when unrotated).
    public static func yaw(fromHeading degrees: Double) -> Float { Float(-degrees * .pi / 180) }

    /// The way a node yawed by `yaw(fromHeading:)` faces.
    public static func forward(ofHeading degrees: Double) -> SIMD3<Float> {
        let radians = degrees * .pi / 180
        return SIMD3(Float(sin(radians)), 0, Float(-cos(radians)))
    }
}

/// The tarmac: a strip along the centreline, each sample's left and right edge, closed round the
/// loop, its normal leaning with the slope.
public enum RoadMesh {
    public static func make(track: TrackModel, vScale: Float = 10) -> MeshArrays {
        strip(track: track, band: Band(side: nil, inset: 0, outset: 0), vScale: vScale, where: { _ in true })
    }

    enum Side { case left, right }

    /// Which strip of the road: `side` nil is the tarmac, edge to edge; `.left`/`.right` is a
    /// strip just outside that edge, from `halfWidth + inset` to `halfWidth + outset` (a kerb).
    struct Band {
        var side: Side?
        var inset: Double
        var outset: Double
    }

    static func strip(track: TrackModel, band: Band, vScale: Float, where included: (Int) -> Bool) -> MeshArrays {
        var mesh = MeshArrays()
        let samples = track.samples
        let count = samples.count
        guard count >= 2 else { return mesh }
        var previous: (left: UInt32, right: UInt32)?
        var runStart: (left: UInt32, right: UInt32)?
        // One pass round the loop and back to the first sample, so the seam closes.
        for step in 0...count {
            let index = step % count
            guard included(index) else {
                previous = nil
                continue
            }
            let sample = samples[index]
            let (left, right) = edges(of: sample, band: band)
            let normal = slopeNormal(at: index, in: samples)
            let v = Float(Double(step) * track.stepMeters) / vScale
            let leftIndex = UInt32(mesh.positions.count)
            mesh.positions += [SceneCoordinates.vector(left), SceneCoordinates.vector(right)]
            mesh.normals += [normal, normal]
            mesh.uvs += [SIMD2(0, v), SIMD2(1, v)]
            let pair = (left: leftIndex, right: leftIndex + 1)
            if let previous {
                mesh.join(
                    previousLeft: previous.left, previousRight: previous.right, left: pair.left, right: pair.right)
            }
            previous = pair
            if runStart == nil { runStart = pair }
        }
        return mesh
    }

    /// The left and right edge points of a sample's band, from its heading.
    static func edges(of sample: TrackModel.Sample, band: Band) -> (left: SIMD3<Double>, right: SIMD3<Double>) {
        let heading = sample.heading * .pi / 180
        // Travelling along heading θ (clockwise from north), right is (cos θ, −sin θ) east/north.
        let right = SIMD3(cos(heading), -sin(heading), 0)
        let half = sample.halfWidth
        switch band.side {
        case nil: return (sample.position - right * half, sample.position + right * half)
        case .right:
            return (sample.position + right * (half + band.inset), sample.position + right * (half + band.outset))
        case .left:
            return (sample.position - right * (half + band.outset), sample.position - right * (half + band.inset))
        }
    }

    /// Up, tilted by the climb between the neighbouring samples.
    static func slopeNormal(at index: Int, in samples: [TrackModel.Sample]) -> SIMD3<Float> {
        let count = samples.count
        let before = samples[(index - 1 + count) % count].position
        let after = samples[(index + 1) % count].position
        let along = SceneCoordinates.vector(after - before)
        let heading = samples[index].heading * .pi / 180
        let right = SceneCoordinates.vector(SIMD3(cos(heading), -sin(heading), 0))
        var normal = simd_cross(right, along)
        if normal.y < 0 { normal = -normal }
        let length = simd_length(normal)
        return length > 0 ? normal / length : SIMD3(0, 1, 0)
    }
}

/// Red-and-white strips just outside the edges the track model flags, 1 m wide, lifted a little.
public enum KerbMesh {
    public static let width = 1.0
    public static let lift = 0.02
    /// One red-or-white stripe per this many metres: the texture repeats every `stripeMeters`.
    public static let stripeMeters: Float = 2

    public static func make(track: TrackModel) -> MeshArrays {
        var lifted = track
        lifted = TrackModel(
            plane: track.plane, stepMeters: track.stepMeters, lengthMeters: track.lengthMeters,
            samples: track.samples.map { sample in
                var raised = sample
                raised.position.z += lift
                return raised
            }, corners: track.corners, hasElevation: track.hasElevation)
        var mesh = RoadMesh.strip(
            track: lifted, band: .init(side: .left, inset: 0, outset: width), vScale: stripeMeters,
            where: { lifted.samples[$0].kerbLeft })
        mesh.append(
            RoadMesh.strip(
                track: lifted, band: .init(side: .right, inset: 0, outset: width), vScale: stripeMeters,
                where: { lifted.samples[$0].kerbRight }))
        return mesh
    }
}

/// A lap's line as a thin ribbon on the road: SceneKit on Metal ignores line width, so a line is
/// a strip of quads a few centimetres above the tarmac.
public enum LapRibbon {
    public static func make(points: [SIMD3<Double>], width: Double = 0.25, lift: Double = 0.05) -> MeshArrays {
        var mesh = MeshArrays()
        let count = points.count
        guard count >= 2 else { return mesh }
        var previous: (left: UInt32, right: UInt32)?
        for index in 0..<count {
            let before = points[max(index - 1, 0)]
            let after = points[min(index + 1, count - 1)]
            var along = SIMD2(after.x - before.x, after.y - before.y)
            let length = simd_length(along)
            along = length > 0 ? along / length : SIMD2(0, 1)
            let right = SIMD3(along.y, -along.x, 0) * (width / 2)
            let centre = points[index] + SIMD3(0, 0, lift)
            let leftIndex = UInt32(mesh.positions.count)
            mesh.positions += [SceneCoordinates.vector(centre - right), SceneCoordinates.vector(centre + right)]
            mesh.normals += [SIMD3(0, 1, 0), SIMD3(0, 1, 0)]
            let v = Float(index) / Float(count - 1)
            mesh.uvs += [SIMD2(0, v), SIMD2(1, v)]
            if let previous {
                mesh.join(
                    previousLeft: previous.left, previousRight: previous.right, left: leftIndex, right: leftIndex + 1)
            }
            previous = (leftIndex, leftIndex + 1)
        }
        return mesh
    }
}
