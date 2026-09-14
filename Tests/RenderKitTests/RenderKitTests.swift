import Testing

@testable import RenderKit

@Test func moduleLoads() {
    #expect(RenderKitInfo.name == "RenderKit")
}
