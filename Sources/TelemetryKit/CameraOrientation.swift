import Foundation

/// A unit quaternion (w, x, y, z): a rotation in 3-D.
public struct Quaternion: Hashable, Sendable {
    public var w: Double
    public var x: Double
    public var y: Double
    public var z: Double

    public init(w: Double, x: Double, y: Double, z: Double) {
        self.w = w
        self.x = x
        self.y = y
        self.z = z
    }

    public static let identity = Quaternion(w: 1, x: 0, y: 0, z: 0)

    public var normalized: Quaternion {
        let length = (w * w + x * x + y * y + z * z).squareRoot()
        guard length > 0 else { return .identity }
        return Quaternion(w: w / length, x: x / length, y: y / length, z: z / length)
    }

    /// The opposite rotation (for a unit quaternion, its conjugate).
    public var inverse: Quaternion { Quaternion(w: w, x: -x, y: -y, z: -z) }

    /// `self` then `other` applied after it, as rotations compose: `(a * b)` rotates by `b`, then `a`.
    public static func * (a: Quaternion, b: Quaternion) -> Quaternion {
        Quaternion(
            w: a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
            x: a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
            y: a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
            z: a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w)
    }

    /// The angle of the rotation, in radians (0…π).
    public var angle: Double { 2 * acos(min(1, abs(w))) }

    /// Spherical interpolation from `self` (t = 0) to `other` (t = 1), the short way round.
    public func slerp(to other: Quaternion, _ t: Double) -> Quaternion {
        var b = other
        var dot = w * b.w + x * b.x + y * b.y + z * b.z
        if dot < 0 {
            b = Quaternion(w: -b.w, x: -b.x, y: -b.y, z: -b.z)
            dot = -dot
        }
        if dot > 0.9995 {
            return Quaternion(
                w: w + (b.w - w) * t, x: x + (b.x - x) * t, y: y + (b.y - y) * t, z: z + (b.z - z) * t
            ).normalized
        }
        let theta = acos(dot)
        let s = sin(theta)
        let wa = sin((1 - t) * theta) / s
        let wb = sin(t * theta) / s
        return Quaternion(w: wa * w + wb * b.w, x: wa * x + wb * b.x, y: wa * y + wb * b.y, z: wa * z + wb * b.z)
    }
}

/// How a camera was pointing through a recording, one sample per video frame or so (#262): GoPro's
/// CORI (the camera body) and, when in-camera stabilisation ran, IORI (the picture it kept, relative
/// to the body). Times are seconds of the video file, as its frames are.
public struct CameraOrientationTrack: Sendable, Equatable {
    public var times: [Double]
    public var camera: [Quaternion]
    /// Same count as `camera`, or empty when the file has no IORI.
    public var image: [Quaternion]

    /// The lens's magnification at the centre of the picture, in picture heights per radian: how far
    /// the picture moves when the camera turns. `nil` when the file does not say.
    public var focalLength: Double?
    /// Whether the camera stabilised the picture itself while recording (HyperSmooth).
    public var stabilisedInCamera: Bool
    /// Seconds from the orientation samples to the frames they describe; positive when the samples
    /// come later. Measured at two frames on a HERO13 (#262).
    public var lag: Double

    public init(
        times: [Double], camera: [Quaternion], image: [Quaternion] = [], focalLength: Double? = nil,
        stabilisedInCamera: Bool = false, lag: Double = 0
    ) {
        self.times = times
        self.camera = camera
        self.image = image
        self.focalLength = focalLength
        self.stabilisedInCamera = stabilisedInCamera
        self.lag = lag
    }

    public var isEmpty: Bool { times.isEmpty }
}
