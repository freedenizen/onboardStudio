import Foundation
import Testing

@testable import GPMFKit
@testable import TelemetryKit

@Suite("Camera orientation (#262)")
struct OrientationTests {
    /// A CORI or IORI stream: one quaternion (w, x, y, z) per frame, scaled by 32767 as a HERO13 does.
    static func quaternionStream(_ key: String, _ rows: [Quaternion], startMicros: UInt64) -> Data {
        var payload = Data()
        for q in rows {
            for value in [q.w, q.x, q.y, q.z] { payload += GPMFFixture.be(Int16((value * 32767).rounded())) }
        }
        return GPMFFixture.nested(
            "STRM",
            [
                GPMFFixture.item("STMP", type: "J", size: 8, repeatCount: 1, payload: GPMFFixture.be(startMicros)),
                GPMFFixture.string("STNM", key == "CORI" ? "CameraOrientation" : "ImageOrientation"),
                GPMFFixture.item("SCAL", type: "s", size: 2, repeatCount: 1, payload: GPMFFixture.be(Int16(32767))),
                GPMFFixture.item(key, type: "s", size: 8, repeatCount: rows.count, payload: payload),
            ])
    }

    static func float(_ value: Float) -> Data { GPMFFixture.be(value.bitPattern) }

    /// Settings like a HERO13's: HyperSmooth `eise`, and the lens polynomial and zoom it records.
    static func settings(eise: String) -> Data {
        let poly = [Float(0), 1.9775, 0.1045, -3.8497, 5.5279, -3.7862, 1.3133].reduce(Data()) { $0 + float($1) }
        return GPMFFixture.nested(
            "DEVC",
            [
                GPMFFixture.string("DVNM", "Global Settings"), GPMFFixture.string("EISE", eise),
                GPMFFixture.nested(
                    "DEVC",
                    [
                        GPMFFixture.string("DVNM", "Large FOV"),
                        GPMFFixture.item("POLY", type: "f", size: 28, repeatCount: 1, payload: poly),
                        GPMFFixture.item("ZMPL", type: "f", size: 4, repeatCount: 1, payload: float(0.7525)),
                    ]),
            ])
    }

    /// Ten frames a second for two seconds, turning steadily about y.
    static func turning(_ count: Int, from: Int = 0) -> [Quaternion] {
        (from..<(from + count)).map { i in
            let half = Double(i) * 0.01 / 2
            return Quaternion(w: cos(half), x: 0, y: sin(half), z: 0)
        }
    }

    @Test func readsTheCamerasOrientationAndWhatItsLensAndSettingsSay() throws {
        let payloads = [0, 1].map { second in
            GPMFFixture.payload(streams: [
                Self.quaternionStream(
                    "CORI", Self.turning(10, from: second * 10), startMicros: UInt64(second) * 1_000_000),
                Self.quaternionStream(
                    "IORI", Array(repeating: .identity, count: 10), startMicros: UInt64(second) * 1_000_000),
            ])
        }
        let url = try GPMFFixture.write(
            GPMFFixture.mp4(payloads: payloads, durationMs: 1000, userData: Self.settings(eise: "N")))
        defer { try? FileManager.default.removeItem(at: url) }
        let track = try #require(try GoProTelemetry.orientation(of: url))
        #expect(track.times.count == 20 && track.camera.count == 20 && track.image.count == 20)
        #expect(abs(track.times[1] - track.times[0] - 0.1) < 1e-6)
        #expect(abs(track.camera[10].angle - 0.1) < 1e-3)  // 10 frames of 0.01 rad
        #expect(track.image.allSatisfy { $0.angle < 1e-3 })
        // POLY's centre slope × ZMPL across half the frame height, in picture heights per radian.
        #expect(abs((track.focalLength ?? 0) - 1.9775 * 0.7525 / 2) < 1e-3)
        #expect(!track.stabilisedInCamera)
        // Two frames: the samples trail the picture by two frames on a HERO13.
        #expect(abs(track.lag - 0.2) < 1e-6)
    }

    @Test func hyperSmoothIsRecognisedAndAFileWithoutOrientationHasNone() throws {
        let with = try GPMFFixture.write(
            GPMFFixture.mp4(
                payloads: [
                    GPMFFixture.payload(streams: [Self.quaternionStream("CORI", Self.turning(5), startMicros: 0)])
                ],
                userData: Self.settings(eise: "Y")))
        defer { try? FileManager.default.removeItem(at: with) }
        #expect(try GoProTelemetry.orientation(of: with)?.stabilisedInCamera == true)
        let without = try GPMFFixture.write(
            GPMFFixture.mp4(payloads: [
                GPMFFixture.payload(streams: [
                    GPMFFixture.accelStream(samples: [.init(z: 9.8, x: 0, y: 0)], startMicros: 0)
                ])
            ]))
        defer { try? FileManager.default.removeItem(at: without) }
        #expect(try GoProTelemetry.orientation(of: without) == nil)
    }

    @Test func quaternionsComposeInvertAndInterpolate() {
        let quarter = Quaternion(w: cos(.pi / 8), x: 0, y: sin(.pi / 8), z: 0)  // 45° about y
        #expect(abs((quarter * quarter).angle - .pi / 2) < 1e-9)
        #expect((quarter * quarter.inverse).angle < 1e-9)
        #expect(abs(Quaternion.identity.slerp(to: quarter * quarter, 0.5).angle - .pi / 4) < 1e-9)
        #expect(Quaternion(w: 2, x: 0, y: 0, z: 0).normalized == .identity)
    }
}
