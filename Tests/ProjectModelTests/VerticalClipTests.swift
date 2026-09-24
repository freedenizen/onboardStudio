import Foundation
import Testing

@testable import ProjectModel

@Suite("A lap as a vertical clip (#151)")
struct VerticalClipTests {
    var project: Project {
        let video = Input(
            label: "Camera", source: MediaReference(path: "/tmp/camera.mp4"), kind: .video(VideoInputSettings()))
        let data = Input(
            label: "Log", source: MediaReference(path: "/tmp/log.csv"), kind: .data(DataInputSettings()))
        var project = Project(inputs: [video, data])
        project.settings.frameRate = 50
        project.settings.speedUnit = .kph
        project.settings.typeface = Typeface(family: "Futura", face: "Bold")
        project.settings.framing = CameraFraming(zoom: 2, centerX: 0.5, centerY: 0.5)
        project.details = ProjectDetails(track: "Sonoma")
        project.export.codec = .hevc
        return project
    }

    @Test func onlyTheLayoutAndSizeChange() {
        let project = self.project
        let clip = project.verticalClip(from: 12, to: 104.5)
        #expect(clip.settings.outputWidth == 1080 && clip.settings.outputHeight == 1920)
        #expect(clip.export.width == 1080 && clip.export.height == 1920)
        #expect(clip.export.range == .span(start: 12, end: 104.5))
        // Everything else stays the project's own.
        #expect(clip.inputs == project.inputs)
        #expect(clip.details == project.details)
        #expect(clip.settings.frameRate == 50 && clip.export.frameRate == 50)
        #expect(clip.settings.speedUnit == .kph)
        #expect(clip.settings.typeface == project.settings.typeface)
        #expect(clip.export.codec == .hevc)
        // The framing was for the 16:9 picture.
        #expect(clip.settings.framing == .none)
    }

    @Test func theSocialLayoutIsBoundToThisProjectsInputs() throws {
        let project = self.project
        let clip = project.verticalClip(from: 0, to: 10)
        #expect(clip.displayObjects.map(\.label) == ProjectTemplate.social.displayObjects.map(\.label))
        let camera = try #require(clip.displayObjects.first { if case .video = $0.kind { true } else { false } })
        #expect(camera.inputID == project.videoInputs.first?.id)
        let card = try #require(clip.displayObjects.first { $0.label == "Stats" })
        #expect(card.inputID == project.dataInputs.first?.id)
    }
}
