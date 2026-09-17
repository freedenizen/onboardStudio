import Foundation
import Testing

@testable import ProjectModel

@Suite("M5 model")
struct ProcessingModelTests {
    @Test func videoSettingsRoundTripAndDecodeLegacy() throws {
        var settings = VideoInputSettings(
            rotation: 180, mirror: Mirror(vertical: true), crop: CropInsets(top: 0.1, right: 0.2))
        settings.color = ColorAdjustments(brightness: 1.2, hue: -30)
        settings.chromaKey = ChromaKey(color: .red, tolerance: 0.25, softness: 0.05)
        settings.audio = AudioSettings(volume: 1.5, balance: -0.5, channels: .left)
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(VideoInputSettings.self, from: data) == settings)
        // A pre-M5 document has only trim/includeAudio.
        let legacy = Data(#"{"trim":{"start":null,"end":null},"includeAudio":false}"#.utf8)
        let decoded = try JSONDecoder().decode(VideoInputSettings.self, from: legacy)
        #expect(decoded == VideoInputSettings(includeAudio: false))
        #expect(decoded.color.isNeutral && decoded.audio.isNeutral && decoded.chromaKey == nil)
    }

    @Test func videoObjectParamsDecodeLegacy() throws {
        let legacy = Data("{}".utf8)
        #expect(try JSONDecoder().decode(VideoObjectParams.self, from: legacy) == VideoObjectParams())
        let kind = DisplayObjectKind.video(VideoObjectParams(channelMask: RGBMask(green: false)))
        let round = try JSONDecoder().decode(DisplayObjectKind.self, from: try JSONEncoder().encode(kind))
        #expect(round == kind)
    }

    @Test func newObjectKindsRoundTrip() throws {
        let kinds: [DisplayObjectKind] = [
            .shape(ShapeParams(shape: .ellipse, strokeWidth: 0.02)),
            .text(TextParams(text: "Hello", outlineWidth: 0.1)),
            .image(ImageObjectParams(rotationChannel: "heading", flashChannel: "rpm", flashThreshold: 6000)),
        ]
        for kind in kinds {
            let data = try JSONEncoder().encode(kind)
            #expect(try JSONDecoder().decode(DisplayObjectKind.self, from: data) == kind)
            #expect(!kind.needsData)
            #expect(kind.isOverlay)
        }
        #expect(DisplayObjectKind.image(ImageObjectParams()).needsImage)
        #expect(!DisplayObjectKind.video(VideoObjectParams()).isOverlay)
        #expect(
            DisplayObject.templates.map(\.name).contains("Shape")
                && DisplayObject.templates.map(\.name).contains("Text"))
    }

    @Test func audioSettingsHelpers() {
        #expect(AudioSettings(volume: 1.5, isMuted: true).effectiveVolume == 0)
        #expect(AudioSettings(volume: 1.5).effectiveVolume == 1.5)
        #expect(AudioSettings.neutral.isNeutral)
        #expect(!AudioSettings(balance: 0.1).isNeutral)
    }
}
