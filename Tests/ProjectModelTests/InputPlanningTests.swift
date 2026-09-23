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

    /// A distinct recording is its own input, so it gets its own timeline bar and sidebar row and
    /// can be moved, trimmed and relabelled on its own. It used to be folded onto the first lane
    /// as extra clips, which left one bar for any number of recordings.
    @Test func aSecondRecordingOpensItsOwnLane() {
        let camera = Self.video("GX010029.MP4", clips: ["GX020029.MP4"])
        let object = DisplayObject(label: "Camera", inputID: camera.id, frame: .full, kind: .video(VideoObjectParams()))
        let project = Project(inputs: [camera], displayObjects: [object])
        let files = [Self.url("GX010030.MP4"), Self.url("GX020030.MP4")]
        #expect(InputPlanning.plan(adding: files, to: project, resolve: Self.resolve) == [.newInput(files)])
        #expect(
            InputPlanning.plan(adding: files, to: project, asCamera: true, resolve: Self.resolve) == [.newInput(files)])
    }

    /// Chapters are the one thing that still merges: they are one recording the camera split.
    @Test func laterChaptersJoinTheRecordingTheyContinue() {
        let camera = Self.video("GX010029.MP4", clips: ["GX020029.MP4"])
        let project = Project(inputs: [camera])
        let third = [Self.url("GX030029.MP4")]
        #expect(
            InputPlanning.plan(adding: third, to: project, resolve: Self.resolve) == [
                .appendClips(to: camera.id, third)
            ]
        )
        // ...but only onto the recording they actually belong to.
        let other = Self.video("GX010031.MP4")
        let two = Project(inputs: [other, camera])
        #expect(
            InputPlanning.plan(adding: third, to: two, resolve: Self.resolve) == [.appendClips(to: camera.id, third)])
    }

    /// Several recordings chosen at once each open a lane; their chapters stay with them.
    @Test func multiSelectKeepsOneLanePerRecording() {
        let files = [
            Self.url("GX010029.MP4"), Self.url("GX020029.MP4"), Self.url("GX010030.MP4"), Self.url("roof.mp4"),
        ]
        #expect(
            InputPlanning.plan(adding: files, to: Project(), resolve: Self.resolve) == [
                .newInput([Self.url("GX010029.MP4"), Self.url("GX020029.MP4")]),
                .newInput([Self.url("GX010030.MP4")]),
                .newInput([Self.url("roof.mp4")]),
            ])
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

    static func data(_ name: String) -> Input {
        Input(label: name, source: MediaReference(path: "/\(name).csv"), kind: .data(DataInputSettings()))
    }

    /// #213: removing the data file keeps the overlay. The gauges are the user's work; the file is
    /// only what they read.
    @Test func removingTheOnlyDataFileKeepsItsObjectsUnbound() {
        var project = ProjectTemplate.classicDash.makeProject()
        let data = Self.data("log")
        project.inputs.append(data)
        project.bindOrphanObjects()
        let dataObjects = project.displayObjects.filter(\.kind.needsData).map(\.id)
        #expect(!dataObjects.isEmpty)

        project.removeInput(data.id)
        #expect(project.inputs.isEmpty)
        #expect(project.displayObjects.map(\.id).contains(dataObjects[0]), "an object was deleted with its file")
        #expect(project.displayObjects.filter { dataObjects.contains($0.id) }.count == dataObjects.count)
        #expect(project.displayObjects.allSatisfy { $0.inputID == nil })
    }

    /// With another data file in the project the objects move to it at once, so the overlay keeps
    /// drawing; the next one added takes them otherwise.
    @Test func removingADataFileMovesItsObjectsToAnotherOrTheNextOne() {
        var project = ProjectTemplate.classicDash.makeProject()
        let first = Self.data("first")
        let second = Self.data("second")
        project.inputs += [first, second]
        project.bindOrphanObjects()
        #expect(project.displayObjects.filter(\.kind.needsData).allSatisfy { $0.inputID == first.id })

        project.removeInput(first.id)
        #expect(project.displayObjects.filter(\.kind.needsData).allSatisfy { $0.inputID == second.id })

        project.removeInput(second.id)
        let later = Self.data("later")
        project.inputs.append(later)
        project.bindOrphanObjects()
        #expect(project.displayObjects.filter(\.kind.needsData).allSatisfy { $0.inputID == later.id })
    }

    /// A camera's video object stays too, ready for the next recording.
    @Test func removingAVideoKeepsItsVideoObject() {
        var project = Project()
        let camera = Self.video("GX010029.MP4")
        project.inputs.append(camera)
        project.displayObjects.append(
            DisplayObject(label: "Camera", inputID: camera.id, frame: .full, kind: .video(VideoObjectParams())))

        project.removeInput(camera.id)
        #expect(project.displayObjects.count == 1)
        #expect(project.displayObjects.first?.inputID == nil)
    }
}
