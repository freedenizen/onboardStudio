import Foundation
import Testing

@testable import ProjectModel

@Suite("Fonts in the document (#118)")
struct TypefaceModelTests {
    static let futura = Typeface(family: "Futura", face: "Medium")

    static func fixture(_ path: String) throws -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Tests/Fixtures/\(path)")
    }

    @Test func filesSavedBeforeFontsCouldBeChosenKeepTheirBuiltInFonts() throws {
        let project = try ProjectPackage.read(FileWrapper(url: Self.fixture("slice.onboardproj")))
        #expect(project.settings.typeface == nil)
        #expect(project.displayObjects.allSatisfy { $0.typeface == nil && $0.textScale == nil })
        let style = try ObjectStyle(data: Data(contentsOf: Self.fixture("fixture.onboardstyle")))
        #expect(style.typeface == nil && style.textScale == nil)
        let template = try ProjectTemplate(data: Data(contentsOf: Self.fixture("fixture.onboardtemplate")))
        #expect(template.settings.typeface == nil)
    }

    @Test func aChosenFontIsSavedWithTheProject() throws {
        var project = Project()
        project.settings.typeface = Self.futura
        project.displayObjects = [
            DisplayObject(
                label: "Lap", inputID: nil, frame: .full, kind: .timer(TimerParams()),
                typeface: Typeface(family: "Helvetica Neue", face: "Light"), textScale: 1.25)
        ]
        let decoded = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(project))
        #expect(decoded == project)
        let json = try #require(String(data: JSONEncoder().encode(project.settings), encoding: .utf8))
        #expect(json.contains(#""family":"Futura""#))
    }

    @Test func aStyleCarriesTheFont() throws {
        var source = DisplayObject(label: "A", inputID: nil, frame: .full, kind: .timer(TimerParams()))
        source.typeface = Self.futura
        source.textScale = 1.5
        let style = try ObjectStyle(data: ObjectStyle(object: source).data())
        var target = DisplayObject(label: "B", inputID: nil, frame: .full, kind: .gear(GearParams()))
        style.apply(to: &target)
        #expect(target.typeface == Self.futura)
        #expect(target.textScale == 1.5)
    }

    @Test func onlyObjectsThatDrawTextOfferAFont() {
        #expect(DisplayObjectKind.timer(TimerParams()).drawsText)
        #expect(DisplayObjectKind.text(TextParams()).drawsText)
        #expect(!DisplayObjectKind.shape(ShapeParams()).drawsText)
        #expect(!DisplayObjectKind.image(ImageObjectParams()).drawsText)
        #expect(DisplayObjectKind.text(TextParams()).sizesOwnText)
        #expect(!DisplayObjectKind.timer(TimerParams()).sizesOwnText)
        #expect(Self.futura.displayName == "Futura Medium")
        #expect(Typeface(family: "Futura", face: "Regular").displayName == "Futura")
    }
}
