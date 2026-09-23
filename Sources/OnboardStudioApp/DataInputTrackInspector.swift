import ProjectModel
import SwiftUI
import TelemetryKit

/// Which circuit the file was recorded at, naming its corners, and passing the definition on.
///
/// Its own file so `DataInputInspector` stays inside SwiftLint's type-body and file-length limits:
/// sectors, circuits and track sharing each arrived from a separate branch and together took the
/// struct over both.
extension DataInputInspector {
    /// Which circuit this file was recorded at, and what the app remembers about it.
    ///
    /// The match is only ever shown, never insisted on: the driver can correct it or clear it,
    /// and nothing is applied to a project that is merely opened.
    @ViewBuilder var trackSection: some View {
        Section("Track") {
            if let match = editor.circuit(for: input.id) {
                LabeledContent("Circuit") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(match.circuit.displayName)
                        Text(confidence(match)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !match.isConfident {
                    Text("Another circuit is about as close, so this is a guess. Correct it below if it is wrong.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("Save Start/Finish, Sectors and Corner Names for This Track") {
                    editor.saveTrackDefinition(for: input.id)
                }
                if editor.trackLibrary.definition(id: match.circuit.id) != nil {
                    Button("Forget Saved Settings") { editor.forgetTrackDefinition(for: input.id) }
                    Text("A file added at this circuit starts with these — a project already saved is untouched.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("Not This Circuit") { setCircuit(nil) }
            } else {
                Text("No circuit recognised. The bundled list holds 1,290 venues; search for yours.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            TextField("Search circuits", text: $circuitSearch)
            ForEach(CircuitCatalog.search(circuitSearch, limit: 6)) { circuit in
                Button(circuit.displayName) {
                    setCircuit(circuit.id)
                    circuitSearch = ""
                }
            }
            sharingRow
        }
        cornerSection
    }

    /// Handing a track definition to another driver, and taking one.
    ///
    /// The point of a file rather than a private library: no licence anywhere covers sector
    /// geometry or corner numbering, so what one driver works out is the only source there is.
    @ViewBuilder var sharingRow: some View {
        Button("Export Track Definition…") { editor.exportTrackDefinition(for: input.id) }
            .accessibilityIdentifier("data.exportTrack")
            .disabled(editor.trackDefinition(for: input.id) == nil)
        Button("Import Track Definition…") { editor.importTrackDefinition(for: input.id) }
            .accessibilityIdentifier("data.importTrack")
        Text("The start/finish line, the sectors and the corner names, in one file to pass on.")
            .font(.caption).foregroundStyle(.secondary)
    }

    /// Names for the corners the detector found, in driving order.
    ///
    /// Circuits number their own corners and rarely do it 1…N — Sonoma runs 3, 3a, 4, 4a — and no
    /// source publishes the numbering, so the driver supplies it once and the track definition
    /// keeps it. Names attach to the corners *found*, which are the ones numbered on the map, so
    /// it does not matter that a curvature detector and a circuit's official count disagree.
    @ViewBuilder var cornerSection: some View {
        Section("Corners") {
            let corners = editor.corners(for: input.id)
            if corners.isEmpty {
                Text("Naming corners needs laps and a GPS trace to find them in.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                DisclosureGroup("\(corners.count) found", isExpanded: $showCorners) {
                    ForEach(Array(corners.enumerated()), id: \.offset) { index, corner in
                        LabeledContent("Corner \(index + 1)") {
                            HStack {
                                Text(corner.turnsRight ? "right" : "left").foregroundStyle(.secondary)
                                CommittingTextField(
                                    "\(index + 1)",
                                    text: Binding(
                                        get: { label(at: index) },
                                        set: { editor.setCornerLabel($0, at: index, for: input.id) })
                                )
                                .frame(width: 70)
                            }
                        }
                    }
                }
                Text(
                    "The map numbers these 1…\(corners.count), which is a count and not what the circuit calls "
                        + "them. Type the real names — 3a and the like — and they are kept with the track."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    func label(at index: Int) -> String {
        index < settings.cornerLabels.count ? settings.cornerLabels[index] : ""
    }

    func confidence(_ match: CircuitCatalog.Match) -> String {
        let distance = String(format: "%.2f km from the session centre", match.distanceKm)
        let runnerUp = match.runnerUpKm.map { String(format: ", next %.0f km", $0) } ?? ""
        return distance + runnerUp + (match.nameAgrees ? ", and the file agrees" : "")
    }

    func setCircuit(_ id: String?) {
        update(id == nil ? "Clear Circuit" : "Set Circuit") { $0.circuitID = id }
    }

}
