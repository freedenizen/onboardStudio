import ProjectModel
import SwiftUI

// MARK: - The garage (#489, #490)

extension LogbookModel {
    /// What a Car field offers: the cars the days and sessions name, most used first, then the
    /// garage's others.
    var knownCars: [String] { LogbookFilter.knownCars(in: entries, days: days, garage: cars) }

    /// Reads the logbook for a window that needs its cars before the Logbook has been shown: a
    /// project's Details.
    func loadIfNeeded() { if !hasLoaded { reload() } }

    /// The car of the days an import left with none, and of their sessions (#489).
    func setCar(_ car: String, onDays ids: [UUID], undo: UndoManager? = nil) {
        edit("Set Car", undo: undo) { try $0.setCar(car, onDays: ids) }
    }

    /// Renames the car everywhere; returns its name now — another car's, when the two became one.
    func renameCar(_ old: String, to new: String, undo: UndoManager? = nil) -> String {
        var name = old
        edit("Rename Car", undo: undo) { name = try $0.renameCar(old, to: new) }
        return name
    }

    func removeCar(_ name: String, undo: UndoManager? = nil) {
        edit("Remove from Garage", undo: undo) { try $0.removeCar(named: name) }
    }

    func saveNotes(_ notes: String, forCar name: String, undo: UndoManager? = nil) {
        edit("Change Car Notes", undo: undo) { try $0.saveNotes(notes, forCar: name) }
    }
}

extension LogbookWindow {
    /// The car the sidebar has chosen, if it is one; "No car" is not one.
    var selectedCar: String? {
        guard case .car(let name) = scope, !name.isEmpty else { return nil }
        return name
    }

    /// The sidebar's cars, by name.
    var carRows: [String] { LogbookFilter.cars(in: model.entries, garage: model.cars).map(\.scope.title) }

    /// The car chosen is no longer one — its sessions given another, its name taken out of the
    /// garage: the sidebar goes back to All Sessions rather than show a card for nothing.
    func followTheChosenCar() {
        if let car = selectedCar, !carRows.contains(car) { scope = .all }
    }

    /// The car above its sessions (#490), the garage's card for it.
    @ViewBuilder var carHeader: some View {
        if let car = selectedCar {
            CarHeader(
                name: car, summary: Garage.summary(of: car, entries: model.entries, days: model.days),
                notes: Garage.car(named: car, in: model.cars)?.notes ?? "",
                saveNotes: { model.saveNotes($0, forCar: car, undo: undoManager) },
                rename: { renamingCar = CarRename(name: car) }, remove: { removeCar(car) }
            )
            // Another car is another field, not this one's typing carried over.
            .id(car)
            Divider()
        }
    }

    /// A car no session names: the garage keeps it for its notes until it is removed.
    var noSessionsInTheCar: some View {
        ContentUnavailableView(
            "No Sessions in This Car", systemImage: "car",
            description: Text(
                "No day or session names this car now; the garage keeps it for its notes. Remove it from "
                    + "the garage when you no longer need them, or rename it to the car it should have been."))
    }

    /// Rename… of the car header; the sidebar follows the car.
    var carSheets: CarSheets {
        CarSheets(renaming: $renamingCar, model: model, undo: undoManager, renamed: { scope = .car($0) })
    }

    /// Remove from Garage: no question, as it can be undone (#454).
    func removeCar(_ car: String) {
        model.removeCar(car, undo: undoManager)
        scope = .all
    }
}
