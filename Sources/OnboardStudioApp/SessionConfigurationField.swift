import ProjectModel
import SwiftUI

/// Which of the circuit's configurations a session drove (#549): the club course, the long
/// course. A session is filed under one from where its turns are when it is added, if the circuit
/// has configurations with named turns; this is where the driver says so, or corrects it. Moving a
/// session moves its laps to that configuration's personal best, Trends, goals and plan.
/// Belongs inside a `Grid`: its body is one row.
struct SessionConfigurationField: View {
    let entry: LogbookEntry
    /// The configurations already named at this circuit, to choose without retyping.
    let known: [String]
    let save: (LogbookEntry) -> Void
    @State private var name = ""
    @FocusState private var focused: Bool

    /// A route between two points: a layout of the circuit.
    static let symbol = "point.topleft.down.to.point.bottomright.curvepath"

    private var others: [String] { known.filter { $0 != (entry.configuration ?? "") } }

    var body: some View {
        // Only at a circuit: a configuration is a layout of one.
        if !LogbookFilter.baseCircuitKey(of: entry).isEmpty { row }
    }

    private var row: some View {
        GridRow {
            Text("Configuration").foregroundStyle(.secondary)
            HStack(spacing: 4) {
                TextField("Configuration", text: $name, prompt: Text("The usual layout")).labelsHidden()
                    .focused($focused)
                    .onSubmit(commit)
                    .onAppear(perform: load)
                    .onChange(of: entry.id) { load() }
                    .onChange(of: entry.configuration) { load() }
                    .onChange(of: focused) { old, new in if old, !new { commit() } }
                    .help("Which layout of the circuit was driven, such as Club Course. Empty for its usual layout.")
                    .accessibilityIdentifier("logbook.detail.configuration")
                if !others.isEmpty || entry.configuration != nil {
                    Menu {
                        ForEach(others, id: \.self) { known in
                            Button(known) { choose(known) }
                        }
                        if entry.configuration != nil {
                            if !others.isEmpty { Divider() }
                            Button("The Usual Layout") { choose("") }
                        }
                    } label: {
                        Label(
                            "Configurations at This Circuit",
                            systemImage: Self.symbol)
                    }
                    .labelStyle(.iconOnly).fixedSize()
                    .accessibilityLabel("Configurations at This Circuit")
                    .help("A configuration already named at this circuit")
                    .accessibilityIdentifier("logbook.detail.configuration.known")
                }
            }
        }
    }

    private func load() { name = entry.configuration ?? "" }

    private func choose(_ known: String) {
        name = known
        commit()
    }

    private func commit() {
        var changed = entry
        let cleaned = CircuitKey.cleaned(name)
        changed.configuration = cleaned.isEmpty ? nil : cleaned
        if changed != entry { save(changed) }
    }
}
