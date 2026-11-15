import Foundation

/// One picture of the onboard video read for traffic (#573): whether a car was close ahead in it,
/// at a moment of the session.
public struct PictureSample: Sendable, Hashable, Codable {
    /// Session time.
    public var time: Double
    public var carAhead: Bool

    public init(time: Double, carAhead: Bool) {
        self.time = time
        self.carAhead = carAhead
    }
}
