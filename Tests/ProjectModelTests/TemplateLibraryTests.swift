import Foundation
import Testing

@testable import ProjectModel

@Suite("Your templates (#44)")
struct TemplateLibraryTests {
    let library: TemplateLibrary
    let template = ProjectTemplate(
        name: "Anything",
        project: Project(displayObjects: [
            DisplayObject(label: "Title", inputID: nil, frame: .full, kind: .text(TextParams(text: "Hi")))
        ]))

    init() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "templates-\(UUID().uuidString)")
        library = TemplateLibrary(directory: folder, trashesRemovedFiles: false)
    }

    @Test func savedTemplatesAreListedByNameWithTheirNameInside() throws {
        try library.save(template, name: "Sonoma club day")
        try library.save(template, name: "  a/b: c ")
        #expect(library.entries().map(\.name) == ["a-b- c", "Sonoma club day"])
        let loaded = try library.load(try #require(library.entry(named: "sonoma CLUB day")))
        #expect(loaded.name == "Sonoma club day")
        #expect(loaded.displayObjects.count == 1)
        #expect(throws: TemplateLibraryError.emptyName) { try library.save(template, name: "  ") }
    }

    @Test func savingUnderATakenNameReplacesIt() throws {
        try library.save(template, name: "Club")
        var other = template
        other.displayObjects = []
        try library.save(other, name: "club")
        #expect(library.entries().count == 1)
        #expect(try library.load(try #require(library.entry(named: "Club"))).displayObjects.isEmpty)
    }

    @Test func renameMovesTheFileAndRefusesATakenName() throws {
        let entry = try library.save(template, name: "Old")
        try library.save(template, name: "Taken")
        #expect(throws: TemplateLibraryError.nameTaken("Taken")) { try library.rename(entry, to: "taken") }
        let renamed = try library.rename(entry, to: "New")
        #expect(library.entries().map(\.name) == ["New", "Taken"])
        #expect(try library.load(renamed).name == "New")
        // Only the case changes: still one template, now spelled the new way.
        let recased = try library.rename(renamed, to: "NEW")
        #expect(library.entries().count == 2)
        #expect(try library.load(recased).name == "NEW")
    }

    @Test func duplicatesAreNumberedAsFinderNumbersThem() throws {
        let entry = try library.save(template, name: "Club")
        #expect(try library.duplicate(entry).name == "Club copy")
        #expect(try library.duplicate(entry).name == "Club copy 2")
        #expect(library.entries().count == 3)
    }

    @Test func importAddsAFileAndRefusesOneThatIsNotATemplate() throws {
        // The name the file had in the Finder, not the one saved inside it on someone else's Mac.
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let outside = folder.appending(path: "From a friend.onboardtemplate")
        var shared = template
        shared.name = "Their old name"
        try shared.data().write(to: outside)
        #expect(try library.importTemplate(from: outside).name == "From a friend")
        #expect(try library.importTemplate(from: outside).name == "From a friend 2")
        let junk = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).onboardtemplate")
        try Data("not json".utf8).write(to: junk)
        #expect(throws: (any Error).self) { try library.importTemplate(from: junk) }
        #expect(library.entries().count == 2)
    }

    @Test func exportWritesACopyNamedForWhereItWent() throws {
        let entry = try library.save(template, name: "Club")
        let destination = FileManager.default.temporaryDirectory.appending(
            path: "Shared \(UUID().uuidString).onboardtemplate")
        try library.export(entry, to: destination)
        let exported = try ProjectTemplate(data: Data(contentsOf: destination))
        #expect(exported.name == destination.deletingPathExtension().lastPathComponent)
        #expect(library.entries().count == 1)
    }

    @Test func removeTakesItOutOfTheList() throws {
        let entry = try library.save(template, name: "Club")
        try library.remove(entry)
        #expect(library.entries().isEmpty)
    }
}
