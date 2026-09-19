import Foundation
import Testing

@testable import ProjectModel

@Suite("M9 model")
struct TemplateExportTests {
    @Test func exportSettingsDecodeLegacyAndRoundTrip() throws {
        let legacy = Data(
            (#"{"codec":"hevc","width":1280,"height":720,"frameRate":30,"videoBitrate":8000000,"#
                + #""audioBitrate":null,"audioSampleRate":48000,"audioChannels":2}"#).utf8)
        let decoded = try JSONDecoder().decode(ExportSettings.self, from: legacy)
        #expect(decoded.codec == .hevc && decoded.audioBitrate == nil)
        #expect(decoded.background == .video && decoded.range == .whole)
        var settings = ExportSettings.overlayAlpha
        settings.range = .laps(first: 2, last: 4)
        let round = try JSONDecoder().decode(ExportSettings.self, from: try JSONEncoder().encode(settings))
        #expect(round == settings)
        #expect(settings.fileExtension == "mov" && ExportSettings.hd1080.fileExtension == "mp4")
        #expect(!ExportSettings.VideoCodec.proRes4444.usesBitrate && ExportSettings.VideoCodec.hevcAlpha.supportsAlpha)
        // A transparent background forces an alpha codec.
        var bad = ExportSettings(codec: .h264, background: .transparent)
        bad = bad.reconciled
        #expect(bad.codec == .proRes4444)
        #expect(ExportSettings.presets["vertical"]?.height == 1920)
        #expect(ExportSettings.namedPresets.map(\.key).allSatisfy { ExportSettings.presets[$0] != nil })
    }

    @Test func templateRoundTripsAndRebinds() throws {
        let camA = Input(label: "A", source: MediaReference(path: "a.mp4"), kind: .video(VideoInputSettings()))
        let camB = Input(label: "B", source: MediaReference(path: "b.mp4"), kind: .video(VideoInputSettings()))
        let data = Input(label: "d", source: MediaReference(path: "d.csv"), kind: .data(DataInputSettings()))
        let image = Input(label: "logo", source: MediaReference(path: "logo.png"), kind: .image(ImageInputSettings()))
        var source = Project(
            inputs: [camA, data, camB, image],
            displayObjects: [
                DisplayObject(label: "Main", inputID: camA.id, frame: .full, kind: .video(VideoObjectParams())),
                DisplayObject(
                    label: "PiP", inputID: camB.id, frame: UnitRect(x: 0.7, y: 0.05, width: 0.25, height: 0.25),
                    kind: .video(VideoObjectParams())),
                DisplayObject(label: "Speed", inputID: data.id, frame: .full, kind: .speedometer(.speedometer())),
                DisplayObject(label: "Logo", inputID: image.id, frame: .full, kind: .image(ImageObjectParams())),
            ])
        source.settings.outputWidth = 1280
        source.settings.outputHeight = 720
        source.export = .hd720
        let segment = source.timeline.addSegment(at: 5)
        source.timeline.setOverride(ObjectOverride(isVisible: false), for: source.displayObjects[1].id, in: segment)

        let template = ProjectTemplate(name: "Two cams", project: source)
        #expect(template.displayObjects.allSatisfy { $0.inputID == nil })
        let data2 = try template.data()
        let decoded = try ProjectTemplate(data: data2)
        #expect(decoded == template)
        #expect(decoded.videoOrdinals.count == 2)

        // Applying to a project with one camera and one data file: PiP waits unbound, the rest rebinds.
        let newCam = Input(label: "X", source: MediaReference(path: "x.mp4"), kind: .video(VideoInputSettings()))
        let newData = Input(label: "Y", source: MediaReference(path: "y.csv"), kind: .data(DataInputSettings()))
        var target = Project(inputs: [newData, newCam])
        decoded.apply(to: &target)
        #expect(target.displayObjects.map(\.label) == ["Main", "PiP", "Speed", "Logo"])
        #expect(target.displayObjects[0].inputID == newCam.id)
        #expect(target.displayObjects[1].inputID == nil)
        #expect(target.displayObjects[2].inputID == newData.id)
        #expect(target.displayObjects[3].inputID == nil)
        #expect(target.settings.outputWidth == 1280 && target.export == .hd720)
        #expect(target.timeline.segments.count == 1 && target.timeline.segments[0].overrides.count == 1)
        // The PiP binds as soon as a second camera arrives.
        target.inputs.append(camB)
        target.bindOrphanObjects()
        #expect(target.displayObjects[1].inputID == camB.id)

        // With two cameras the PiP comes back on the second one.
        var two = Project(inputs: [newCam, newData, camB])
        decoded.apply(to: &two)
        #expect(two.displayObjects.map(\.label) == ["Main", "PiP", "Speed", "Logo"])
        #expect(two.displayObjects[1].inputID == camB.id)
        #expect(two.timeline.segments[0].overrides.count == 1)

        #expect(throws: ProjectTemplateError.self) {
            try ProjectTemplate(data: Data(#"{"formatVersion":9,"name":"x"}"#.utf8))
        }
    }

    @Test func builtInTemplatesApplyCleanly() {
        let cam = Input(label: "cam", source: MediaReference(path: "a.mp4"), kind: .video(VideoInputSettings()))
        let data = Input(label: "d", source: MediaReference(path: "d.csv"), kind: .data(DataInputSettings()))
        for template in ProjectTemplate.builtIn {
            var project = Project(inputs: [cam, data])
            template.apply(to: &project)
            #expect(!project.displayObjects.isEmpty, Comment(rawValue: template.name))
            #expect(
                project.videoObjects.count == 1 && project.videoObjects[0].inputID == cam.id,
                Comment(rawValue: template.name))
            for object in project.displayObjects where object.kind.needsData {
                #expect(object.inputID == data.id, "\(template.name): \(object.label)")
            }
            let unbound = template.makeProject().videoObjects  // no inputs to bind to yet
            #expect(unbound.count == 1 && unbound[0].inputID == nil, Comment(rawValue: template.name))
        }
        #expect(Set(ProjectTemplate.builtIn.map(\.name)).count == ProjectTemplate.builtIn.count)
    }
}
