import Foundation
import Testing

@testable import Importers

@Test func fixturesAreBundled() throws {
    let url = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
    let contents = try FileManager.default.contentsOfDirectory(atPath: url.path)
    #expect(contents.contains("README.md"))
}
