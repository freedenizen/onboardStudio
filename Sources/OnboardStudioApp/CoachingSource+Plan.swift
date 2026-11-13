import ProjectModel
import TelemetryKit

/// Where a plan made in the Coaching window is kept (#458): with the circuit, from a project or a
/// logbook session alike, so it is there when the driver prepares to go back (#460) and on the
/// Season page; and in the project too when there is one.
extension ProjectCoachingSource {
    var planCircuitName: String? { input.flatMap { editor?.planCircuitName(for: $0) } }

    var circuitPlan: NextSessionPlan? {
        guard let editor else { return nil }
        guard let input, let key = editor.trackKey(for: input.id) else { return editor.project.plan }
        return editor.trackLibrary.definition(id: key)?.plan ?? editor.project.plan
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
        do {
            // A circuit planned for the first time keeps the plan alone: the logbook knows no
            // start/finish or sectors to give it, and a definition without them does not change
            // how the next file there is set up (`TrackDefinition.hasGeometry`).
            try TrackLibrary.app.remember(plan, id: circuit.id) {
                TrackDefinition(
                    circuitID: circuit.id, name: circuit.name, latitude: circuit.latitude,
                    longitude: circuit.longitude)
            }
            return true
        } catch {
            message = "The plan could not be kept for \(circuit.name): \(error.localizedDescription)"
            return false
        }
    }
}
