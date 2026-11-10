import ProjectModel
import SwiftUI
import TelemetryKit

/// Where a day was driven (#393): a circuit of the catalogue, or a name as typed for one the
/// catalogue does not know. Shown as chosen, with Change; else a search field with what the
/// catalogue offers, the names typed into the logbook before (#455) and the typed text itself.
/// The New Track Day sheet and a day's header share it.
struct CircuitChooser: View {
    @Binding var circuit: Circuit?
    @Binding var typedName: String
    /// The names typed for circuits before, so the second visit is spelt like the first.
    var knownNames: [String] = []
    /// `trackday.new` in the sheet, `trackday.header` on a day: the root of the identifiers.
    let identifier: String
    /// The search field's width where it stands among other fields of that width; the matches
    /// under it are not held to it, so a long circuit name is not cut short.
    var fieldWidth: CGFloat?
    @State private var search = ""

    private var trimmed: String { search.trimmingCharacters(in: .whitespaces) }

    /// The typed names that match what is being typed; the most used few before anything is.
    private var offeredNames: [String] {
        guard !trimmed.isEmpty else { return Array(knownNames.prefix(3)) }
        return Array(knownNames.filter { $0.localizedCaseInsensitiveContains(trimmed) }.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let circuit {
                HStack {
                    Text(circuit.displayName).accessibilityIdentifier("\(identifier).circuit.chosen")
                    Button("Change") { self.circuit = nil }.buttonStyle(.link)
                        .accessibilityIdentifier("\(identifier).circuit.change")
                }
            } else if !typedName.isEmpty {
                HStack {
                    Text("“\(typedName)”, as typed").accessibilityIdentifier("\(identifier).circuit.chosen")
                    Button("Change") { typedName = "" }.buttonStyle(.link)
                        .accessibilityIdentifier("\(identifier).circuit.change")
                }
            } else {
                // The row is labelled already; the prompt is the hint inside the field (#457).
                TextField("Circuit", text: $search, prompt: Text("Search circuits")).labelsHidden()
                    .frame(maxWidth: fieldWidth)
                    .accessibilityIdentifier("\(identifier).circuit")
                ForEach(CircuitCatalog.search(search, limit: 5)) { match in
                    Button(match.displayName) {
                        circuit = match
                        search = ""
                    }
                    .buttonStyle(.link)
                    .accessibilityIdentifier("\(identifier).match.\(match.name)")
                }
                ForEach(offeredNames, id: \.self) { name in
                    Button("“\(name)”, as Typed Before") {
                        typedName = name
                        search = ""
                    }
                    .buttonStyle(.link)
                    .accessibilityIdentifier("\(identifier).known.\(name)")
                }
                if !trimmed.isEmpty,
                    !offeredNames.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame })
                {
                    Button("Use “\(trimmed)” as Typed") {
                        typedName = trimmed
                        search = ""
                    }
                    .buttonStyle(.link)
                    .accessibilityIdentifier("\(identifier).useTyped")
                }
            }
        }
    }
}
