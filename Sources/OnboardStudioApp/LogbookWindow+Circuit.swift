import MediaKit
import ProjectModel
import SwiftUI
import TelemetryKit

// MARK: - Plans, kept for the circuit (#330, #460)

extension LogbookModel {
    func reloadPlans() {
        trackDefinitions = TrackLibrary.app.all()
        plans = Dictionary(
            trackDefinitions.compactMap { definition in definition.plan.map { (definition.id, $0) } },
            uniquingKeysWith: { first, _ in first })
    }

    /// A plan is kept on the circuit's track definition, so only for a circuit the catalogue knows.
    static func canPlan(_ circuitKey: String) -> Bool {
        CircuitCatalog.circuit(id: CircuitKey.base(of: circuitKey)) != nil
    }

    /// Writes the circuit's plan — none takes it away — as one step of the Logbook window's Undo.
    func savePlan(_ plan: NextSessionPlan?, for circuitKey: String, name: String, undo: UndoManager?) {
        guard let circuit = CircuitCatalog.circuit(id: CircuitKey.base(of: circuitKey)) else { return }
        let configuration = CircuitKey.configuration(of: circuitKey)
        let before = plans[circuitKey]
        let kept = plan.flatMap { $0.experiments.isEmpty ? nil : $0 }
        guard kept != before else { return }
        if let kept {
            try? TrackLibrary.app.remember(kept, id: circuitKey) {
                TrackDefinition(
                    circuitID: circuit.id, configuration: configuration, name: circuit.name,
                    latitude: circuit.latitude, longitude: circuit.longitude)
            }
        } else {
            try? TrackLibrary.app.forgetPlan(id: circuitKey)
        }
        reloadPlans()
        undo?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated { model.savePlan(before, for: circuitKey, name: name, undo: undo) }
        }
        undo?.setActionName(name)
    }
}

// MARK: - The circuit's card (#460)

extension LogbookWindow {
    /// The circuit the sidebar has chosen, when it is one: "No circuit" is not a place to go back to.
    var selectedCircuit: (key: String, title: String)? {
        guard case .circuit(let key, let title) = scope, !key.isEmpty else { return nil }
        return (key, title)
    }

    /// Above a circuit's sessions; above an empty day at a circuit, until its first session arrives.
    @ViewBuilder var circuitCard: some View {
        if let circuit = selectedCircuit {
            card(for: circuit.key, title: circuit.title, showsNewDay: true)
            Divider()
        } else if let day = selectedDay, !day.circuitKey.isEmpty,
            !model.entries.contains(where: { $0.trackDayID == day.id }),
            model.plans[day.circuitKey] != nil
                || !CircuitBrief.make(entries: model.entries, circuitKey: day.circuitKey).isEmpty
        {
            card(for: day.circuitKey, title: day.title, showsNewDay: false)
            Divider()
        }
    }

    private func card(for key: String, title: String, showsNewDay: Bool) -> some View {
        let brief = CircuitBrief.make(entries: model.entries, circuitKey: key)
        return CircuitCard(
            title: title, brief: brief, plan: model.plans[key], canPlan: LogbookModel.canPlan(key),
            showsNewDay: showsNewDay,
            newDay: {
                // A day is at the circuit; which configuration each session drove is the session's.
                model.newDayCircuit = CircuitKey.base(of: key)
                model.newDayRequested = true
            },
            makePlan: lastVisitSession(at: key).map { entry in { coach(entry) } },
            nameTurns: namingSource(at: key).map { entry in
                { model.turnNaming = TurnNamingRequest(key: key, title: title, entry: entry) }
            },
            savePlan: { model.savePlan($0, for: key, name: $1, undo: undoManager) },
            goals: model.goals(at: key).map { GoalProgress.make($0, entries: model.entries) },
            speed: LogbookWindow.speedUnit, corners: cornerLabels(at: key), cars: carsDriven(at: key),
            addGoal: { model.addGoal($0, undo: undoManager) }, removeGoal: { model.removeGoal($0, undo: undoManager) }
        )
        .id(key)
    }

    /// The quickest session of the latest day at the circuit: what Make a Plan in Coaching… reads.
    func lastVisitSession(at key: String) -> LogbookEntry? {
        let here = model.entries.filter { LogbookFilter.circuitKey(of: $0) == key && $0.bestLap != nil }
        let calendar = Calendar.current
        guard let latest = here.compactMap({ $0.date.map(calendar.startOfDay) }).max() else { return nil }
        return here.filter { $0.date.map(calendar.startOfDay) == latest }.min { ($0.bestLap ?? 0) < ($1.bestLap ?? 0) }
    }
}

// MARK: - Naming the turns (#550)

extension LogbookWindow {
    /// The session whose best lap the turns at `key` are named on: the personal best there, the
    /// cleanest lap the logbook has of the circuit. `nil` for a circuit named by hand, as a plan is.
    func namingSource(at key: String) -> LogbookEntry? {
        guard LogbookModel.canPlan(key), let best = PersonalBests.best(in: model.entries, circuitKey: key) else {
            return nil
        }
        return model.entries.first { $0.id == best.entryID }
    }

    func turnNamingSheet(_ request: TurnNamingRequest) -> some View {
        let definition = TrackLibrary.app.definition(id: request.key)
        return TurnNamingSheet(
            request: request, load: { await model.session(for: request.entry) },
            pinned: definition?.turnNames ?? [], legacy: definition?.cornerLabels ?? [],
            save: { model.saveTurnNames($0, for: request.key, undo: undoManager) })
    }
}

extension LogbookModel {
    /// Keeps `names` as the turn names of the circuit and configuration keyed `key`, as one step of
    /// the Logbook window's Undo, and reads the corners of the sessions there again by them (#550).
    func saveTurnNames(_ names: [TurnName], for key: String, undo: UndoManager?) {
        guard let circuit = CircuitCatalog.circuit(id: CircuitKey.base(of: key)) else { return }
        let library = TrackLibrary.app
        let before = library.definition(id: key)
        var definition =
            before
            ?? TrackDefinition(
                circuitID: circuit.id, configuration: CircuitKey.configuration(of: key), name: circuit.name,
                latitude: circuit.latitude, longitude: circuit.longitude)
        guard definition.turnNames != names else { return }
        definition.turnNames = names
        // The pinned names are read from now on; the list from before would only mislead (#548).
        if !names.isEmpty { definition.cornerLabels = [] }
        try? library.save(definition)
        afterTurnNamesChanged(at: key)
        undo?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated { model.restoreTurnNames(before, for: key, names: names, undo: undo) }
        }
        undo?.setActionName("Name Turns")
    }

    /// Undo of `saveTurnNames`: the definition as it was, or none, and Redo back to `names`.
    private func restoreTurnNames(_ before: TrackDefinition?, for key: String, names: [TurnName], undo: UndoManager?) {
        let library = TrackLibrary.app
        if let before { try? library.save(before) } else { try? library.remove(id: key) }
        afterTurnNamesChanged(at: key)
        undo?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated { model.saveTurnNames(names, for: key, undo: undo) }
        }
        undo?.setActionName("Name Turns")
    }

    /// The sessions at `key` read their corners again with the circuit's names, off the main
    /// thread, so Trends, goals and the card call the turns what the driver just called them.
    private func afterTurnNamesChanged(at key: String) {
        reloadPlans()
        let ids = entries.filter { LogbookFilter.circuitKey(of: $0) == key }.map(\.id)
        for id in ids { sessions[id] = nil }
        let logbook = AppLogbook.shared
        let tracks = TrackLibrary.app
        Task {
            await Task.detached(priority: .utility) {
                for id in ids {
                    guard var entry = logbook.entry(id: id), let session = LogbookReferences.load(entry, tracks: tracks)
                    else { continue }
                    entry.readCorners(of: session)
                    try? logbook.save(entry)
                }
            }.value
            reload()
        }
    }
}
