import Testing

@testable import ProjectModel

@Test func schemaVersionIsPositive() {
    #expect(ProjectModelInfo.schemaVersion >= 1)
}

@Test func marketingVersionLooksSemantic() {
    let parts = OverlayGenVersion.marketing.split(separator: ".")
    #expect(parts.count == 3)
    #expect(parts.allSatisfy { Int($0) != nil })
}
