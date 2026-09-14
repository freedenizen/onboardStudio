import Testing
@testable import Scripting

@Test func moduleLoads() {
    #expect(ScriptingInfo.name == "Scripting")
}
