import Foundation
import Testing

@testable import ProjectModel

@Suite("Stabilisation settings (#262)")
struct StabilisationSettingsTests {
    @Test func aVideoSavedBeforeStabilisationOpensAsRecorded() throws {
        let old = try JSONDecoder().decode(VideoInputSettings.self, from: Data(#"{"includeAudio": true}"#.utf8))
        #expect(old.stabilisation == .off && !old.stabilisation.isActive)
        var steadied = VideoInputSettings()
        steadied.stabilisation = StabilisationSettings(method: .motionData, smoothing: 1.2, zoom: 1.3)
        let again = try JSONDecoder().decode(VideoInputSettings.self, from: try JSONEncoder().encode(steadied))
        #expect(again.stabilisation == steadied.stabilisation)
    }

    @Test func theZoomBoundsHowFarAFrameMoves() {
        #expect(StabilisationSettings(zoom: 1).maxShift == 0)
        #expect(abs(StabilisationSettings(zoom: 1.5).maxShift - 0.5 / 3) < 1e-12)
    }
}
