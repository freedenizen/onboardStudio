import ProjectModel
import SwiftUI

// MARK: - Goals (#461)

extension LogbookModel {
    /// The goals at a circuit, in the order they were set.
    func goals(at circuitKey: String) -> [Goal] { goals.filter { $0.circuitKey == circuitKey } }

    /// Writes the goals as one step of the Logbook window's Undo.
    func saveGoals(_ new: [Goal], name: String, undo: UndoManager?) {
        let before = goals
        guard new != before else { return }
        try? AppLogbook.shared.saveGoals(new)
        goals = new
        undo?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated { model.saveGoals(before, name: name, undo: undo) }
        }
        undo?.setActionName(name)
    }

    func addGoal(_ goal: Goal, undo: UndoManager?) { saveGoals(goals + [goal], name: "Add Goal", undo: undo) }

    func removeGoal(_ goal: Goal, undo: UndoManager?) {
        saveGoals(goals.filter { $0.id != goal.id }, name: "Remove Goal", undo: undo)
    }
}

extension LogbookWindow {
    /// Settings ▸ Units ▸ Speed; with nothing chosen there, the region's (#464).
    static var speedUnit: SpeedDisplayUnit {
        let setting = SpeedUnitSetting(rawValue: UserDefaults.standard.value(for: Preferences.speedUnit))
        return (setting ?? .automatic).shown()
    }

    /// The corners read at the circuit, as the latest session with any names them.
    func cornerLabels(at key: String) -> [String] {
        model.entries.filter { LogbookFilter.circuitKey(of: $0) == key && !$0.corners.isEmpty }
            .max { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }?.corners.map(\.label) ?? []
    }

    func carsDriven(at key: String) -> [String] {
        Array(Set(model.entries.filter { LogbookFilter.circuitKey(of: $0) == key }.map(\.car).filter { !$0.isEmpty }))
            .sorted()
    }
}
