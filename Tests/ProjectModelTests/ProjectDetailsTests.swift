import Foundation
import Testing

@testable import ProjectModel

@Suite("Project details (#74)")
struct ProjectDetailsTests {
    static let sonoma = ProjectDetails(
        track: "Sonoma Raceway", car: "M2 Competition", driver: "Alex", date: "2026-08-23",
        extras: [ProjectDetail(name: "Tyres", value: "Cup 2")])

    @Test func textNamesDetailsInBraces() {
        let details = Self.sonoma
        #expect(details.fill("{track} · {car}") == "Sonoma Raceway · M2 Competition")
        // Keys match without regard to case or padding, extras included.
        #expect(details.fill("{ Track } on {TYRES}") == "Sonoma Raceway on Cup 2")
        #expect(details.fill("{date}") == ProjectDetails.displayDate("2026-08-23"))
        #expect(details.fill("{date}").contains("2026"))
    }

    @Test func aDetailWithNoValueStaysAsTyped() {
        let details = Self.sonoma
        // Nothing entered for the event: the text keeps asking for it rather than dropping it.
        #expect(details.fill("{event}: {track}") == "{event}: Sonoma Raceway")
        #expect(details.fill("{nonsense}") == "{nonsense}")
        // Braces that are not a key are just text.
        #expect(details.fill("a { b") == "a { b")
        #expect(details.fill("{{track}}") == "{Sonoma Raceway}")
        #expect(details.fill("}{") == "}{")
        #expect(details.fill("no braces") == "no braces")
    }

    @Test func aProjectSavedBeforeDetailsDrawsItsTextAsItDid() throws {
        // No details key at all: none, and text with braces in it reaches the renderer unchanged.
        let json = #"{"schemaVersion": 1}"#
        let project = try JSONDecoder().decode(Project.self, from: Data(json.utf8))
        #expect(project.details.isEmpty)
        let text = DisplayObjectKind.text(TextParams(text: "{track}"))
        #expect(text.filling(project.details) == text)
        #expect(text.filling(Self.sonoma) == .text(TextParams(text: "Sonoma Raceway")))
        // Only a text object's own text is filled.
        let readout = DisplayObjectKind.textData(TextDataParams(channel: "rpm", label: "{track}"))
        #expect(readout.filling(Self.sonoma) == readout)
    }

    @Test func detailsAreSavedWithTheProjectButNotWithATemplate() throws {
        var project = Project()
        project.details = Self.sonoma
        let decoded = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(project))
        #expect(decoded.details == Self.sonoma)
        let template = ProjectTemplate(name: "Mine", project: project)
        let json = try #require(String(data: template.data(), encoding: .utf8))
        #expect(!json.contains("Sonoma"))
    }

    @Test func fillingBlanksNeverOverwrites() {
        let typed = ProjectDetails(track: "Sears Point")
        let (details, filled) = typed.fillingBlanks(
            from: ProjectDetails(track: "Sonoma Raceway", driver: "Alex", date: "2026-08-23"))
        #expect(details.track == "Sears Point")
        #expect(details.driver == "Alex")
        #expect(details.date == "2026-08-23")
        #expect(filled == ["driver", "date"])
        #expect(details.fillingBlanks(from: ProjectDetails()).filled.isEmpty)
    }

    @Test func aDayIsADayInAnyTimeZone() throws {
        let day = try #require(ProjectDetails.day("2026-08-23"))
        #expect(ProjectDetails.iso(day) == "2026-08-23")
        #expect(ProjectDetails.day("23/08/2026") == nil)
        #expect(ProjectDetails.displayDate("") == nil)
    }

    @Test func theTitleCardShowsTheTrackAndDay() throws {
        let card = try #require(DisplayObject.templates.first { $0.name == "Title Card" })
        let day = ProjectDetails.displayDate("2026-08-23") ?? ""
        #expect(card.kind.filling(Self.sonoma) == .text(TextParams(text: "Sonoma Raceway · \(day)")))
    }
}
