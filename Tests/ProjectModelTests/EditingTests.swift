import CoreGraphics
import Foundation
import Testing

@testable import ProjectModel

@Suite("ProjectPackage")
struct ProjectPackageTests {
    @Test func writesAndReadsAPackageWrapper() throws {
        let project = ProjectTests.sampleProject()
        let wrapper = try ProjectPackage.write(project)
        #expect(wrapper.isDirectory)
        #expect(wrapper.fileWrappers?["project.json"] != nil)
        #expect(try ProjectPackage.read(wrapper) == project)
        // Rewriting into an existing wrapper replaces project.json and keeps other entries.
        let extra = FileWrapper(regularFileWithContents: Data("x".utf8))
        extra.preferredFilename = "assets.txt"
        wrapper.addFileWrapper(extra)
        var changed = project
        changed.settings.frameRate = 60
        let rewritten = try ProjectPackage.write(changed, existing: wrapper)
        #expect(try ProjectPackage.read(rewritten).settings.frameRate == 60)
        #expect(rewritten.fileWrappers?["assets.txt"] != nil)
    }

    @Test func readsABareJSONWrapper() throws {
        let project = ProjectTests.sampleProject()
        #expect(try ProjectPackage.read(FileWrapper(regularFileWithContents: try project.encoded())) == project)
        #expect(throws: ProjectError.self) { try ProjectPackage.read(FileWrapper(directoryWithFileWrappers: [:])) }
    }

    @Test func mediaReferencesAreRelativeInsideTheBase() {
        let base = URL(fileURLWithPath: "/Users/me/Race.onboardproj", isDirectory: true)
        #expect(
            MediaReference.make(for: URL(fileURLWithPath: "/Users/me/Race.onboardproj/clip.mp4"), relativeTo: base).path
                == "clip.mp4")
        #expect(
            MediaReference.make(for: URL(fileURLWithPath: "/Users/me/other/clip.mp4"), relativeTo: base).path
                == "/Users/me/other/clip.mp4")
        #expect(MediaReference.make(for: URL(fileURLWithPath: "/tmp/a.mp4"), relativeTo: nil).path == "/tmp/a.mp4")
    }
}

@Suite("Sync wizard")
struct SyncWizardTests {
    @Test func solvesStartPosition() {
        // Video moment at project 10 s corresponds to data time 1000 s with identity sync → start 990.
        #expect(SyncWizard.startPosition(projectTime: 10, dataTime: 1000, sync: .identity) == 990)
        // With an offset of 2 s and double speed: (10 - 2) * 2 = 16 → 984.
        let sync = SyncSettings(startPositionInInput: 0, offsetInProject: 2, playSpeed: 2)
        let start = SyncWizard.startPosition(projectTime: 10, dataTime: 1000, sync: sync)
        #expect(start == 984)
        var solved = sync
        solved.startPositionInInput = start
        #expect(solved.inputTime(forProjectTime: 10) == 1000)
    }
}

@Suite("Object geometry")
struct ObjectGeometryTests {
    let frame = UnitRect(x: 0.2, y: 0.2, width: 0.4, height: 0.3)

    @Test func hitTestsHandlesAndBody() {
        #expect(ObjectGeometry.handle(at: CGPoint(x: 0.2, y: 0.2), in: frame, handleSize: 0.01) == .topLeft)
        #expect(ObjectGeometry.handle(at: CGPoint(x: 0.6, y: 0.5), in: frame, handleSize: 0.01) == .bottomRight)
        #expect(ObjectGeometry.handle(at: CGPoint(x: 0.4, y: 0.2), in: frame, handleSize: 0.01) == .top)
        #expect(ObjectGeometry.handle(at: CGPoint(x: 0.4, y: 0.35), in: frame, handleSize: 0.01) == .body)
        #expect(ObjectGeometry.handle(at: CGPoint(x: 0.9, y: 0.9), in: frame, handleSize: 0.01) == nil)
    }

    @Test func draggingBodyMovesAndKeepsAGrabbableEdgeOnScreen() {
        let moved = ObjectGeometry.drag(frame, handle: .body, delta: CGSize(width: 0.1, height: -0.1))
        #expect(abs(moved.x - 0.3) < 1e-9 && abs(moved.y - 0.1) < 1e-9 && moved.width == 0.4 && moved.height == 0.3)

        // Dragged far off the bottom-right: a sliver stays on screen, the rest hangs off.
        let far = ObjectGeometry.drag(frame, handle: .body, delta: CGSize(width: 1, height: 1))
        #expect(abs(far.x - (1 - ObjectGeometry.minimumVisible)) < 1e-9)
        #expect(abs(far.y - (1 - ObjectGeometry.minimumVisible)) < 1e-9)
        #expect(far.width == 0.4 && far.height == 0.3, "the size survives a drag past the edge")

        // And off the top-left the same way, so nothing can be lost entirely.
        let back = ObjectGeometry.drag(frame, handle: .body, delta: CGSize(width: -1, height: -1))
        #expect(abs(back.x - (ObjectGeometry.minimumVisible - 0.4)) < 1e-9)
        #expect(abs(back.y - (ObjectGeometry.minimumVisible - 0.3)) < 1e-9)
    }

    /// The bug behind the Glass Cockpit wheel snapping into view: it is placed taller than the
    /// frame with only its upper arc showing, and any move or resize used to pull it fully inside.
    @Test func aWheelTallerThanTheFrameSurvivesMovingAndResizing() {
        let wheel = UnitRect(x: 0.2, y: 0.5, width: 0.6, height: 0.6 * 16 / 9)
        #expect(wheel.height > 1, "the template wheel is taller than the picture")

        let nudged = ObjectGeometry.drag(wheel, handle: .body, delta: CGSize(width: 0, height: 0.05))
        #expect(abs(nudged.height - wheel.height) < 1e-9, "moving must not shrink it to fit")
        #expect(abs(nudged.y - 0.55) < 1e-9, "and it must actually move down")

        let grown = ObjectGeometry.drag(wheel, handle: .bottomRight, delta: CGSize(width: 0.2, height: 0.2))
        #expect(grown.height > 1, "resizing must not cap the height at the frame")
        #expect(abs(grown.width - 0.8) < 1e-9)

        // It can be pushed down until only a sliver of the rim is left in shot.
        let down = ObjectGeometry.drag(wheel, handle: .body, delta: CGSize(width: 0, height: 5))
        #expect(abs(down.y - (1 - ObjectGeometry.minimumVisible)) < 1e-9)
        #expect(abs(down.height - wheel.height) < 1e-9)
    }

    /// A nudge is specified in output pixels so one arrow press means the same distance on screen
    /// whatever the project's size — a fraction-based step moves twice as far in 4K as in 1080p.
    @Test func nudgingMovesByOutputPixels() {
        let hd = ProjectSettings(outputWidth: 1920, outputHeight: 1080)
        let right = ObjectGeometry.nudged(frame, byPixels: 1, 0, in: hd)
        #expect(abs(right.x - (frame.x + 1.0 / 1920)) < 1e-12)
        #expect(right.y == frame.y, "a horizontal nudge leaves y alone")
        #expect(right.width == frame.width && right.height == frame.height)

        let down = ObjectGeometry.nudged(frame, byPixels: 0, 10, in: hd)
        #expect(abs(down.y - (frame.y + 10.0 / 1080)) < 1e-12)

        // The same ten pixels in a 4K project is a smaller fraction of the frame, so the object
        // ends up in the same place on screen.
        let uhd = ProjectSettings(outputWidth: 3840, outputHeight: 2160)
        let downUHD = ObjectGeometry.nudged(frame, byPixels: 0, 10, in: uhd)
        #expect(abs((downUHD.y - frame.y) - (down.y - frame.y) / 2) < 1e-12)
    }

    /// Nudging clamps like a drag: an object can hang off the edge but never be pushed away
    /// entirely, and a degenerate project size must not divide by zero.
    @Test func nudgingClampsAndSurvivesAZeroSizedProject() {
        let hd = ProjectSettings(outputWidth: 1920, outputHeight: 1080)
        var far = frame
        for _ in 0..<5000 { far = ObjectGeometry.nudged(far, byPixels: 100, 0, in: hd) }
        #expect(abs(far.x - (1 - ObjectGeometry.minimumVisible)) < 1e-9)
        #expect(far.width == frame.width, "the size survives being nudged past the edge")

        let zero = ProjectSettings(outputWidth: 0, outputHeight: 0)
        let unmoved = ObjectGeometry.nudged(frame, byPixels: 5, 5, in: zero)
        #expect(unmoved.x == frame.x && unmoved.y == frame.y)
    }

    @Test func draggingHandlesResizes() {
        let right = ObjectGeometry.drag(frame, handle: .right, delta: CGSize(width: 0.1, height: 0))
        #expect(abs(right.width - 0.5) < 1e-9 && right.x == 0.2)
        let topLeft = ObjectGeometry.drag(frame, handle: .topLeft, delta: CGSize(width: 0.1, height: 0.1))
        #expect(abs(topLeft.x - 0.3) < 1e-9 && abs(topLeft.width - 0.3) < 1e-9 && abs(topLeft.height - 0.2) < 1e-9)
        let tiny = ObjectGeometry.drag(frame, handle: .left, delta: CGSize(width: 5, height: 0))
        #expect(abs(tiny.width - ObjectGeometry.minimumSize) < 1e-9)
    }

    @Test func aspectLockKeepsRatio() {
        let resized = ObjectGeometry.drag(
            frame, handle: .bottomRight, delta: CGSize(width: 0.2, height: 0), keepAspect: true)
        #expect(abs(resized.width / resized.height - 0.4 / 0.3) < 1e-9)
    }

    @Test func defaultObjectsHaveSensibleFrames() {
        for (index, template) in DisplayObject.templates.enumerated() {
            let object = DisplayObject.makeDefault(kind: template.kind, inputID: nil, index: index)
            #expect(object.frame.width > 0 && object.frame.height > 0)
            #expect(object.frame.x + object.frame.width <= 1.0001)
            if case .steeringWheel = template.kind {
                // The wheel deliberately hangs below the picture so only its upper arc shows.
                #expect(object.frame.y < 1 && object.frame.y + object.frame.height > 1)
            } else {
                #expect(object.frame.y + object.frame.height <= 1.0001)
            }
            #expect(object.label == template.kind.typeName)
        }
    }
}
