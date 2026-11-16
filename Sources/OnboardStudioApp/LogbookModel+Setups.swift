import ProjectModel
import SwiftUI
import TelemetryKit

// MARK: - Setups kept with a car (#559)

extension LogbookModel {
    /// Keeps the setup with the car, each a step of the Logbook's Undo; returns it as kept.
    @discardableResult
    func saveSetup(_ setup: SavedSetup, forCar car: String, undo: UndoManager? = nil) -> SavedSetup {
        var kept = setup
        edit("Save Setup", undo: undo) { kept = try $0.saveSetup(setup, forCar: car) }
        return kept
    }

    func deleteSetup(_ setup: SavedSetup, forCar car: String, undo: UndoManager? = nil) {
        edit("Delete Setup", undo: undo) { try $0.deleteSetup(setup.id, forCar: car) }
    }

    func setStartingSetup(_ id: UUID?, forCar car: String, undo: UndoManager? = nil) {
        edit(id == nil ? "Clear Starting Setup" : "Make Starting Setup", undo: undo) {
            try $0.setStartingSetup(id, forCar: car)
        }
    }
}

extension SetupUnits {
    /// The units the app's settings imply: the pressure unit chosen on a setup sheet, else psi and
    /// inches with miles an hour and bar and millimetres otherwise.
    static var app: SetupUnits {
        var units = SetupUnits.following(imperial: CoachingUnits.app.distance == .feet)
        let chosen = UserDefaults.standard.value(for: Preferences.setupPressureUnit)
        if let pressure = SetupUnits.Pressure(rawValue: chosen) { units.pressure = pressure }
        return units
    }
}
