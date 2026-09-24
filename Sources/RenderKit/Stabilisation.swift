import CoreGraphics
import CoreImage
import Foundation
import ProjectModel
import TelemetryKit

/// How to move each frame of a video so the camera seems to follow a smooth path (#262): from the
/// camera's own orientation record, the rotation between where it pointed and where a smoothed
/// path says it should have, turned into a shift and a roll of the picture.
///
/// Conventions, measured on a HERO13 helmet clip against the picture's own frame-to-frame motion
/// (Vision homographies, three stretches of the clip agreeing): the turn between two orientations
/// `a` and `b` in the camera's frame is `a · b⁻¹`; its x component moves the recorded picture up
/// and down, y left and right, z rolls it, all at the lens's centre magnification.
public final class StabilisationPath: Sendable, Equatable {
    /// Seconds of the video file, as its frames are.
    let times: [Double]
    /// Per sample, the picture shift (x, y, in picture heights) and roll (radians) that brings the
    /// recorded frame onto the smooth path, in the recorded (unrotated) picture's coordinates.
    let corrections: [SIMD3<Double>]

    /// How strongly the picture follows the camera: `smoothing` seconds is the time constant of the
    /// path (0.1 barely smooths, 2 floats). `maxShift` caps each frame's move, in picture heights, so
    /// the zoom margin is never exceeded and no edge shows.
    public init?(track: CameraOrientationTrack, smoothing: Double, maxShift: Double, defaultFocalLength: Double = 0.74)
    {
        guard track.times.count >= 2 else { return nil }
        let focal = track.focalLength ?? defaultFocalLength
        let real = track.camera
        let smooth = Self.smoothed(real, times: track.times, timeConstant: max(smoothing, 0.01))
        times = track.times.map { $0 - track.lag }
        corrections = zip(real, smooth).map { real, smooth in
            let turn = Self.rotationVector(smooth * real.inverse)
            var shift = SIMD2(turn.y, turn.x) * focal
            let length = (shift * shift).sum().squareRoot()
            if length > maxShift, length > 0 { shift *= maxShift / length }
            return SIMD3(shift.x, shift.y, -turn.z)
        }
    }

    public static func == (a: StabilisationPath, b: StabilisationPath) -> Bool { a === b }

    /// The correction at a time in the video file, interpolated between samples.
    public func correction(at time: Double) -> SIMD3<Double> {
        guard let first = times.first, let last = times.last else { return .zero }
        if time <= first { return corrections[0] }
        if time >= last { return corrections[corrections.count - 1] }
        var low = 0
        var high = times.count - 1
        while high - low > 1 {
            let mid = (low + high) / 2
            if times[mid] <= time { low = mid } else { high = mid }
        }
        let fraction = (time - times[low]) / (times[high] - times[low])
        return corrections[low] + (corrections[high] - corrections[low]) * fraction
    }

    /// The transform that moves a recorded frame of `size` onto the smooth path at `time`, zoomed
    /// by `zoom` about its centre so the moved edges stay outside the picture. Core Image
    /// coordinates (origin at the bottom left) of the recorded, unrotated frame.
    public func transform(at time: Double, size: CGSize, zoom: Double) -> CGAffineTransform {
        let c = correction(at: time)
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        return CGAffineTransform(translationX: -centre.x, y: -centre.y)
            .concatenating(CGAffineTransform(rotationAngle: c.z))
            .concatenating(CGAffineTransform(scaleX: zoom, y: zoom))
            .concatenating(
                CGAffineTransform(translationX: centre.x + c.x * size.height, y: centre.y + c.y * size.height))
    }

    /// A forward then backward exponential average of the path: smooth, with no lag either way.
    static func smoothed(_ path: [Quaternion], times: [Double], timeConstant: Double) -> [Quaternion] {
        guard var previous = path.first else { return [] }
        var forward = [previous]
        forward.reserveCapacity(path.count)
        for index in 1..<path.count {
            let step = max(times[index] - times[index - 1], 0)
            previous = previous.slerp(to: path[index], 1 - exp(-step / timeConstant))
            forward.append(previous)
        }
        var result = forward
        for index in stride(from: path.count - 2, through: 0, by: -1) {
            let step = max(times[index + 1] - times[index], 0)
            result[index] = result[index + 1].slerp(to: forward[index], 1 - exp(-step / timeConstant))
        }
        return result
    }

    /// The axis times the angle of a rotation, in radians, the short way round.
    static func rotationVector(_ q: Quaternion) -> SIMD3<Double> {
        let q = q.w < 0 ? Quaternion(w: -q.w, x: -q.x, y: -q.y, z: -q.z) : q
        let s = (q.x * q.x + q.y * q.y + q.z * q.z).squareRoot()
        guard s > 1e-12 else { return .zero }
        let angle = 2 * atan2(s, q.w)
        return SIMD3(q.x, q.y, q.z) / s * angle
    }
}

/// A video layer's stabilisation: the path, the zoom that hides the moved edges, and how project
/// time maps to the file's own time — through the input's sync, and for the compared lap of a lap
/// comparison through the warp that keeps it level (#154).
public struct LayerStabilisation: Sendable, Equatable {
    public let path: StabilisationPath
    public let zoom: Double
    public let sync: SyncSettings
    public let warp: LapTimeWarp?

    public init(path: StabilisationPath, zoom: Double, sync: SyncSettings, warp: LapTimeWarp? = nil) {
        self.path = path
        self.zoom = zoom
        self.sync = sync
        self.warp = warp
    }

    /// The recorded frame moved onto the smooth path for project `time`, cut back to its own size.
    public func apply(to raw: CIImage, at time: Double) -> CIImage {
        let fileTime = sync.inputTime(forProjectTime: warp?.comparedTime(at: time) ?? time)
        let extent = raw.extent
        let moved = raw.transformed(
            by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY)
                .concatenating(path.transform(at: fileTime, size: extent.size, zoom: zoom))
                .concatenating(CGAffineTransform(translationX: extent.minX, y: extent.minY)))
        // Over a clear frame of the full size: where too little zoom leaves an edge uncovered, the
        // frame keeps its size (and its place in the layer) with nothing drawn there.
        return moved.composited(over: CIImage(color: .clear).cropped(to: extent)).cropped(to: extent)
    }
}
