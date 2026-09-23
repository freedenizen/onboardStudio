import Foundation
import ProjectModel
import TelemetryKit
import Testing

@testable import MediaKit

/// #214: a mapping made for all projects reaches a project that is already open. The session
/// cache compared the input and the project's mapping, not the global one, so an open project
/// kept its old channels until it was reopened.
@Suite("Global mapping reloads")
struct GlobalMappingReloadTests {
    func project() throws -> (Project, ProjectLocation) {
        let fixture = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
            .appending(path: "racechrono-v3-noisy.csv")
        let input = Input(
            label: "noisy", source: MediaReference(path: fixture.path), kind: .data(DataInputSettings()))
        let location = ProjectLocation(fixture.deletingLastPathComponent().appending(path: "scratch.json"))
        return (Project(inputs: [input]), location)
    }

    @Test func changingTheGlobalMappingReimportsAnOpenProjectsData() async throws {
        let (project, location) = try project()
        let id = try #require(project.inputs.first?.id)
        let first = try await ProjectCompiler.load(
            project, location: location, globalAttributeMappings: AttributeMappingTable())
        #expect(first.sessions[id]?[.brakePressureFront] == nil)

        let global = AttributeMappingTable(["brakePressureFront": AttributeMapping(source: "brake_pressure_front")])
        let second = try await ProjectCompiler.load(
            project, location: location, reusing: first, globalAttributeMappings: global)
        #expect(second.sessions[id]?[.brakePressureFront] != nil, "the open project kept its old channels")
        #expect(second.sessions[id]?[.canbus("brake_pressure_front")] != nil, "the raw form was lost")
    }
}
