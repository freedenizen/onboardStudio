import Foundation
import MediaKit
import ProjectModel
import TelemetryKit

// MARK: - Project details (#74)

extension EditorModel {
    /// Called after every compile: fills the project's blank details — track, driver, day — from a
    /// data file the user has just added.
    ///
    /// **Only for a file just added**, as `applyPendingTrackDefinition` is: opening a saved project
    /// never fills anything in, because a filled-in detail changes every title card showing it.
    func applyPendingDetails() {
        guard let id = pendingDetails, sessions[id] != nil else { return }
        pendingDetails = nil
        fillDetails(from: id)
    }

    /// Fills the blank details from data input `id`, never overwriting one already entered, and
    /// returns the names of those it filled.
    @discardableResult
    func fillDetails(from id: InputID) -> [String] {
        guard let session = sessions[id] else { return [] }
        let circuitName = project.input(id)?.dataSettings?.circuitID.flatMap { circuitID in
            trackLibrary.definition(id: circuitID)?.name ?? CircuitCatalog.circuit(id: circuitID)?.name
        }
        let suggested = ProjectDetails.suggested(by: session, circuitName: circuitName)
        let (details, filled) = project.details.fillingBlanks(from: suggested)
        guard !filled.isEmpty else { return [] }
        edit("Fill In Project Details") { $0.details = details }
        return filled
    }

    /// The Details section's **Fill In from Data**: every data file in turn, first come first
    /// served, with the status line saying what it found.
    func fillDetailsFromData() {
        let filled = project.dataInputs.flatMap { fillDetails(from: $0.id) }
        statusMessage =
            filled.isEmpty
            ? "The data files name nothing that is not already filled in."
            : "Filled in the \(ListFormatter.localizedString(byJoining: filled)) from the data."
    }

    /// Clears the selection, which is what shows the project's own inspector: its details, font,
    /// output and units.
    func showProjectInspector() {
        selectedObjectID = nil
        selectedInputID = nil
        selectedSegmentID = nil
        selectedMarkerID = nil
    }

    /// Changes one detail, as one undo step named for it.
    func setDetail(_ name: String, _ change: (inout ProjectDetails) -> Void) {
        edit(name) { change(&$0.details) }
    }
}
