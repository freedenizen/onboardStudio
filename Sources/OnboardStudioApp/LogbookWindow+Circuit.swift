import ProjectModel
import SwiftUI
import TelemetryKit

// MARK: - Plans, kept for the circuit (#330, #460)

extension LogbookModel {
    func reloadPlans() {
        plans = Dictionary(
            TrackLibrary.app.all().compactMap { definition in definition.plan.map { (definition.id, $0) } },
            uniquingKeysWith: { first, _ in first })
    }

    /// A plan is kept on the circuit's track definition, so only for a circuit the catalogue knows.
    static func canPlan(_ circuitKey: String) -> Bool { CircuitCatalog.circuit(id: circuitKey) != nil }

    /// Writes the circuit's plan — none takes it away — as one step of the Logbook window's Undo.
    func savePlan(_ plan: NextSessionPlan?, for circuitKey: String, name: String, undo: UndoManager?) {
        guard let circuit = CircuitCatalog.circuit(id: circuitKey) else { return }
        let before = plans[circuitKey]
        let kept = plan.flatMap { $0.experiments.isEmpty ? nil : $0 }
        guard kept != before else { return }
        if let kept {
            try? TrackLibrary.app.remember(kept, id: circuit.id) {
                TrackDefinition(
                    circuitID: circuit.id, name: circuit.name, latitude: circuit.latitude,
                    longitude: circuit.longitude)
            }
        } else {
            try? TrackLibrary.app.forgetPlan(id: circuit.id)
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
                model.newDayCircuit = key
                model.newDayRequested = true
            },
            makePlan: lastVisitSession(at: key).map { entry in { coach(entry) } },
            savePlan: { model.savePlan($0, for: key, name: $1, undo: undoManager) }
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
