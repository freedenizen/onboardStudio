import Foundation
import Testing

@testable import ProjectModel

/// Graphs gained a movable playhead in #156, and new ones put it in the middle. A graph saved before
/// then drew it at the right edge with no line, and must go on doing so wherever it comes from: a
/// project, a template or a style.
@Suite("Graph playhead migration (#156)")
struct GraphPlayheadMigrationTests {
    let graph = DisplayObject(
        label: "Speed", inputID: nil, frame: .full,
        kind: .graph(GraphParams(series: [GraphSeries(channel: "speed")], axis: .time)))

    /// `data` as the build before #156 wrote it: at `version`, without the two new keys.
    func saved(before data: Data, versionKey: String, version: Int) throws -> Data {
        func strip(_ value: Any) -> Any {
            if var dictionary = value as? [String: Any] {
                dictionary["playheadPosition"] = nil
                dictionary["showPlayheadLine"] = nil
                return dictionary.mapValues(strip)
            }
            if let array = value as? [Any] { return array.map(strip) }
            return value
        }
        var root = try #require(strip(try JSONSerialization.jsonObject(with: data)) as? [String: Any])
        root[versionKey] = version
        return try JSONSerialization.data(withJSONObject: root)
    }

    func graphParams(_ kind: DisplayObjectKind?) -> GraphParams? {
        guard case .graph(let params) = kind else { return nil }
        return params
    }

    @Test func aNewGraphSitsInTheMiddleWithALine() {
        let params = GraphParams(series: [])
        #expect(params.playheadPosition == 0.5)
        #expect(params.showPlayheadLine)
    }

    @Test func anOldProjectKeepsItsGraphsAtTheRightEdge() throws {
        let project = Project(displayObjects: [graph])
        let old = try saved(before: try project.encoded(), versionKey: "schemaVersion", version: 1)
        let opened = try Project.decode(old)
        #expect(opened.schemaVersion == Project.currentSchemaVersion)
        let params = try #require(graphParams(opened.displayObjects.first?.kind))
        #expect(params.playheadPosition == 1)
        #expect(!params.showPlayheadLine)
        // A project saved since keeps whatever it was set to.
        let current = try Project.decode(try project.encoded())
        #expect(graphParams(current.displayObjects.first?.kind)?.playheadPosition == 0.5)
    }

    @Test func anOldTemplateAndStyleDoToo() throws {
        let template = ProjectTemplate(name: "Mine", project: Project(displayObjects: [graph]))
        let oldTemplate = try saved(before: try template.data(), versionKey: "formatVersion", version: 1)
        let openedTemplate = try ProjectTemplate(data: oldTemplate)
        #expect(graphParams(openedTemplate.displayObjects.first?.kind)?.playheadPosition == 1)
        #expect(graphParams(openedTemplate.displayObjects.first?.kind)?.showPlayheadLine == false)

        let style = ObjectStyle(object: graph)
        let openedStyle = try ObjectStyle(
            data: try saved(before: try style.data(), versionKey: "formatVersion", version: 1))
        #expect(graphParams(openedStyle.kind)?.playheadPosition == 1)
        #expect(graphParams(openedStyle.kind)?.showPlayheadLine == false)
        #expect(graphParams(try ObjectStyle(data: try style.data()).kind)?.playheadPosition == 0.5)
    }

    @Test func onlyGraphsAreTouched() throws {
        var bar = DisplayObjectKind.bar(BarParams(channel: "speed"))
        let before = bar
        bar.pinGraphPlayheadToTheRightEdge()
        #expect(bar == before)
    }
}
