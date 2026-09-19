import Foundation
import Testing

@testable import ProjectModel

@Suite("Adding videos to a project")
struct InputPlanningTests {
    static let dir = URL(fileURLWithPath: "/cam")
    static func url(_ name: String) -> URL { dir.appending(path: name) }
    static func resolve(_ reference: MediaReference) -> URL { URL(fileURLWithPath: reference.path) }

    static func video(_ name: String, clips: [String] = []) -> Input {
        var settings = VideoInputSettings()
        settings.clips = clips.map { VideoClip(source: MediaReference(path: url($0).path)) }
        return Input(label: name, source: MediaReference(path: url(name).path), kind: .video(settings))
    }

    @Test func firstRecordingOpensALane() {
        let plan = InputPlanning.plan(
            adding: [Self.url("GX010029.MP4"), Self.url("GX020029.MP4")], to: Project(), resolve: Self.resolve)
        #expect(plan == [.newInput([Self.url("GX010029.MP4"), Self.url("GX020029.MP4")])])
    }

    @Test func filesAlreadyInTheProjectAreNotAddedTwice() {
        let camera = Self.video("GX010029.MP4", clips: ["GX020029.MP4"])
        let project = Project(inputs: [camera])
        let plan = InputPlanning.plan(adding: [Self.url("GX020029.MP4")], to: project, resolve: Self.resolve)
        #expect(plan == [.alreadyPresent(Self.url("GX020029.MP4"), in: camera.id)])
    }

    @Test func aSecondRecordingFollowsTheFirstOnASingleLane() {
        let camera = Self.video("GX010029.MP4", clips: ["GX020029.MP4"])
        let object = DisplayObject(label: "Camera", inputID: camera.id, frame: .full, kind: .video(VideoObjectParams()))
        let project = Project(inputs: [camera], displayObjects: [object])
        let files = [Self.url("GX010030.MP4"), Self.url("GX020030.MP4")]
        #expect(
            InputPlanning.plan(adding: files, to: project, resolve: Self.resolve) == [
                .appendClips(to: camera.id, files)
            ])
        // Add Camera opens a new lane instead.
        #expect(
            InputPlanning.plan(adding: files, to: project, asCamera: true, resolve: Self.resolve) == [.newInput(files)])
    }

    @Test func multiCameraProjectsKeepGettingLanes() {
        let a = Self.video("front.mp4")
        let b = Self.video("rear.mp4")
        let project = Project(inputs: [a, b])
        #expect(
            InputPlanning.plan(adding: [Self.url("roof.mp4")], to: project, resolve: Self.resolve)
                == [.newInput([Self.url("roof.mp4")])])
    }

    @Test func orphanObjectsBindToTheInputsThatArrive() {
        var project = ProjectTemplate.classicDash.makeProject()
        // Nothing to bind to yet: the template's objects are all unbound, none dropped.
        #expect(project.displayObjects.count == 8)
        #expect(project.displayObjects.allSatisfy { $0.inputID == nil })
        let camera = Self.video("GX010029.MP4")
        project.inputs.append(camera)
        project.bindOrphanObjects()
        #expect(project.displayObjects.first?.inputID == camera.id)
        #expect(project.displayObjects.dropFirst().allSatisfy { $0.inputID == nil })
        let data = Input(label: "log", source: MediaReference(path: "/log.csv"), kind: .data(DataInputSettings()))
        project.inputs.append(data)
        project.bindOrphanObjects()
        #expect(project.displayObjects.dropFirst().allSatisfy { $0.inputID == data.id })
        // A second camera only binds to an unbound video object.
        let second = Self.video("rear.mp4")
        project.inputs.append(second)
        project.bindOrphanObjects()
        #expect(project.displayObjects.first?.inputID == camera.id)
        // Removing the data input orphans the data objects again; the next data input takes over.
        project.inputs.removeAll { $0.id == data.id }
        let other = Input(label: "log2", source: MediaReference(path: "/log2.csv"), kind: .data(DataInputSettings()))
        project.inputs.append(other)
        project.bindOrphanObjects()
        #expect(project.displayObjects.dropFirst().allSatisfy { $0.inputID == other.id })
    }
}
