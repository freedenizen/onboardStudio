import ProjectModel
import SwiftUI

/// The car and the driver of a session (#453). A session took them from its day or its file when
/// it was added and they could not be corrected afterwards: one filed under the wrong car, or
/// under none, stayed there. Committed on Return or when the field is left, as the day's are.
/// Belongs inside a `Grid`: its body is two rows.
struct SessionCarFields: View {
    let entry: LogbookEntry
    /// The cars the logbook's days and sessions name, for a correction without retyping.
    let knownCars: [String]
    let save: (LogbookEntry) -> Void
    @State private var car = ""
    @State private var driver = ""
    @FocusState private var focus: Field?

    enum Field: Hashable { case car, driver }

    /// The cars to offer: every one but the session's own.
    private var others: [String] { knownCars.filter { $0 != entry.car } }

    /// Two rows of the detail's grid, so the labels and the fields stand in its columns.
    var body: some View {
        GridRow {
            Text("Car").foregroundStyle(.secondary)
            HStack(spacing: 4) {
                // The row is labelled already; the prompt is the hint inside the field (#457).
                TextField("Car", text: $car, prompt: Text("What was driven")).labelsHidden()
                    .focused($focus, equals: .car)
                    .onSubmit(commit)
                    .accessibilityIdentifier("logbook.detail.car")
                    // The view is two rows, so what belongs to the whole of it hangs here, once.
                    .onAppear(perform: load)
                    .onChange(of: entry.id) { load() }
                    // The day's car, changed in its header, reaches the session while it is shown.
                    .onChange(of: entry.car) { load() }
                    .onChange(of: entry.driver) { load() }
                    .onChange(of: focus) { old, new in if old != nil, new != old { commit() } }
                if !others.isEmpty {
                    Menu {
                        ForEach(others, id: \.self) { known in
                            Button(known) {
                                car = known
                                commit()
                            }
                        }
                    } label: {
                        Label("Cars in the Logbook", systemImage: "car")
                    }
                    .labelStyle(.iconOnly).fixedSize()
                    .accessibilityLabel("Cars in the Logbook")
                    .help("A car the logbook already knows")
                    .accessibilityIdentifier("logbook.detail.car.known")
                }
            }
        }
        GridRow {
            Text("Driver").foregroundStyle(.secondary)
            TextField("Driver", text: $driver, prompt: Text("Who drove")).labelsHidden()
                .focused($focus, equals: .driver)
                .onSubmit(commit)
                .accessibilityIdentifier("logbook.detail.driver")
        }
    }

    private func load() {
        car = entry.car
        driver = entry.driver
    }

    private func commit() {
        var changed = entry
        changed.car = car.trimmingCharacters(in: .whitespaces)
        changed.driver = driver.trimmingCharacters(in: .whitespaces)
        if changed != entry { save(changed) }
    }
}
