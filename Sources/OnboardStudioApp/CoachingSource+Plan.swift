import ProjectModel
import TelemetryKit

/// Where a plan made in the Coaching window is kept (#458): with the circuit, from a project or a
/// logbook session alike, so it is there when the driver prepares to go back (#460) and on the
/// Season page; and in the project too when there is one.
extension ProjectCoachingSource {
    var planCircuitName: String? { input.flatMap { editor?.planCircuitName(for: $0) } }

    var circuitPlan: NextSessionPlan? {
        guard let editor else { return nil }
        guard let input, let match = editor.circuit(for: input.id) else { return editor.project.plan }
        return editor.trackLibrary.definition(id: match.circuit.id)?.plan ?? editor.project.plan
    }

    func savePlan(_ plan: NextSessionPlan) -> Bool {
        guard let editor else { return false }
        editor.edit("Make Plan") { $0.plan = plan }
        if let input { editor.rememberPlan(for: input) }
        return true
    }
}

extension LogbookCoachingSource {
    /// The session's circuit, when the logbook knows which it is.
    private var circuit: Circuit? { entry.circuitID.flatMap(CircuitCatalog.circuit(id:)) }

    var planCircuitName: String? { circuit.map { TrackLibrary.app.definition(id: $0.id)?.name ?? $0.name } }

    var circuitPlan: NextSessionPlan? { circuit.flatMap { TrackLibrary.app.definition(id: $0.id)?.plan } }

    func savePlan(_ plan: NextSessionPlan) -> Bool {
        guard let circuit else { return false }
        // Through the Logbook, so the circuit's card shows it at once and its Undo takes it back
        // (#543): the Coaching window has no Undo of its own for a session.
        let logbook = LogbookModel.shared
        do {
            try logbook.savePlan(plan, for: circuit.id, name: "Make Plan", undo: logbook.windowUndo)
            return true
        } catch {
            message = "The plan could not be kept for \(circuit.name): \(error.localizedDescription)"
            return false
        }
    }
}
