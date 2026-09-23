import Foundation
import Testing

@testable import ProjectModel

/// The attribute window remembers which level it was editing between launches (#200).
@Suite("Attribute mapping scope")
struct AttributeMappingScopeTests {
    @Test(arguments: [AttributeMappingScope.global, .project, .input(InputID())])
    func survivesARoundTripThroughStorage(scope: AttributeMappingScope) {
        #expect(AttributeMappingScope(storageValue: scope.storageValue) == scope)
    }

    /// Something this build does not recognise is no scope at all, so the window falls back to its
    /// default rather than editing a level nobody chose.
    @Test(arguments: ["", "Global", "input:", "input:not-a-uuid", "object:6F9619FF-8B86-D011-B42D-00C04FC964FF"])
    func anUnrecognisedValueIsNil(value: String) {
        #expect(AttributeMappingScope(storageValue: value) == nil)
    }

    @Test func eachScopeWritesToItsLevel() {
        let id = InputID()
        #expect(AttributeMappingScope.global.level == .global)
        #expect(AttributeMappingScope.project.level == .project)
        #expect(AttributeMappingScope.input(id).level == .input)
        #expect(AttributeMappingScope.input(id).inputID == id)
        #expect(AttributeMappingScope.project.inputID == nil)
    }
}
