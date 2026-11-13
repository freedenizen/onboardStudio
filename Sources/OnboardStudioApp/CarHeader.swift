import ProjectModel
import SwiftUI

/// A car above its sessions (#490): the garage's card for it — what the logbook holds of it, the
/// owner's notes, and the corrections its name may need. Edits go straight to the logbook's
/// files, as a day's do.
struct CarHeader: View {
    let name: String
    let summary: Garage.Summary
    let notes: String
    let saveNotes: (String) -> Void
    let rename: () -> Void
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.title3.weight(.semibold))
                        .accessibilityIdentifier("car.header.title")
                    Text(Self.subtitle(summary)).font(.callout).foregroundStyle(.secondary)
                        .accessibilityIdentifier("car.header.subtitle")
                }
                Spacer()
                Button("Rename…", systemImage: "pencil", action: rename)
                    .help("Rename the car on every day and session; another car's name makes the two one car")
                    .accessibilityIdentifier("car.header.rename")
                Button("Remove from Garage…", systemImage: "trash", role: .destructive, action: remove)
                    .labelStyle(.iconOnly)
                    .disabled(!summary.isUnused)
                    .help(
                        summary.isUnused
                            ? "Take the car and its notes out of the garage"
                            : "A car can be removed once no day or session names it; to put a misspelt "
                                + "name right, rename it to the car it should be"
                    )
                    .accessibilityIdentifier("car.header.remove")
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow(alignment: .firstTextBaseline) {
                    Text("Notes").foregroundStyle(.secondary)
                    CommittingTextField(
                        "Notes", text: Binding(get: { notes }, set: saveNotes),
                        prompt: Text("Setup, tyres, what was changed — anything about the car"), axis: .vertical
                    )
                    .labelsHidden()
                    .lineLimit(2...6)
                    .accessibilityIdentifier("car.header.notes")
                }
            }
            .font(.callout)
        }
        .padding()
    }

    /// "12 sessions on 4 days at 2 circuits, Mar – Nov 2026", or what a car with none is.
    static func subtitle(_ summary: Garage.Summary) -> String {
        if summary.isUnused { return "In the garage; no day or session names it." }
        func count(_ number: Int, _ noun: String) -> String { "\(number) \(noun)\(number == 1 ? "" : "s")" }
        var text =
            summary.sessions == 0
            ? "Named on \(count(summary.days, "day")), with no sessions yet"
            : "\(count(summary.sessions, "session")) on \(count(summary.days, "day"))"
        if summary.circuits > 0 { text += " at \(count(summary.circuits, "circuit"))" }
        if let first = summary.first, let last = summary.last {
            let calendar = Calendar.current
            let month = Date.FormatStyle.dateTime.month(.abbreviated).year()
            text +=
                calendar.isDate(first, equalTo: last, toGranularity: .month)
                ? ", \(first.formatted(month))"
                : ", \((first..<last).formatted(.interval.month(.abbreviated).year()))"
        }
        return text
    }
}

/// The car whose Rename… sheet is up.
struct CarRename: Identifiable {
    let name: String
    var id: String { name }
}

/// Renames a car everywhere (#490): its days, its sessions, the garage. Typing another car's name
/// makes the two one, which is how a misspelling is folded into the car it should have been.
struct CarRenameSheet: View {
    let name: String
    let summary: Garage.Summary
    /// Every car the logbook knows, to say when the new name is another's.
    let knownCars: [String]
    let rename: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""

    private var trimmed: String { newName.trimmingCharacters(in: .whitespaces) }
    /// The car the new name is already, if it is another.
    private var existing: String? {
        Garage.same(trimmed, name) ? nil : knownCars.first { Garage.same($0, trimmed) }
    }
    private var canRename: Bool { !trimmed.isEmpty && trimmed != name }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename “\(name)”").font(.headline)
            TextField("Name", text: $newName, prompt: Text("Car"))
                .labelsHidden()
                .onSubmit(commit)
                .accessibilityIdentifier("car.rename.name")
            Text(explanation)
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("car.rename.explanation")
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(existing == nil ? "Rename" : "Make One Car", action: commit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canRename)
                    .accessibilityIdentifier("car.rename.confirm")
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear { newName = name }
    }

    private var explanation: String {
        let days = "\(summary.days) day\(summary.days == 1 ? "" : "s")"
        let sessions = "\(summary.sessions) session\(summary.sessions == 1 ? "" : "s")"
        if let existing {
            return "“\(existing)” is a car the logbook has already. The two become one car under that name, "
                + "with both cars’ notes; this one’s \(days) and \(sessions) go with it."
        }
        return summary.isUnused
            ? "The name changes in the garage."
            : "The name changes on its \(days) and \(sessions), and in the garage."
    }

    /// Reads the field as it is now: Return can arrive before the redraw for the last letter.
    private func commit() {
        guard canRename else { return }
        rename(trimmed)
        dismiss()
    }
}

/// The car header's Rename… sheet and the question before Remove from Garage… (#490).
struct CarSheets: ViewModifier {
    @Binding var renaming: CarRename?
    @Binding var removing: String?
    let model: LogbookModel
    /// The car's name after a rename, for the sidebar to follow it.
    let renamed: (String) -> Void
    let removed: () -> Void

    func body(content: Content) -> some View {
        content
            .sheet(item: $renaming) { car in
                CarRenameSheet(
                    name: car.name, summary: Garage.summary(of: car.name, entries: model.entries, days: model.days),
                    knownCars: model.knownCars
                ) { renamed(model.renameCar(car.name, to: $0)) }
            }
            .confirmationDialog(
                "Remove “\(removing ?? "")” from the garage?",
                isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                presenting: removing
            ) { car in
                Button("Remove from Garage", role: .destructive) {
                    model.removeCar(car)
                    removed()
                }
            } message: { _ in
                Text("No day or session names it. Its notes are removed with it.")
            }
    }
}
