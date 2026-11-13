import ProjectModel
import SwiftUI

/// The car of the days an import left with none (#489), asked in its report. Files added with no
/// day chosen go on the day their date and circuit say, and a session takes the car of an earlier
/// one at the circuit — on a first import there is none, so every day came in with no car and the
/// report did not say so. The field sets the car on all of them and their sessions; a day can
/// still be given another in its header.
struct ImportCarField: View {
    /// The days, oldest first.
    let days: [TrackDay]
    let knownCars: [String]
    @Binding var car: String
    /// The car once it is set; the field gives way to a line saying so.
    let carSet: String?
    let set: () -> Void

    var body: some View {
        if let carSet {
            Label(
                "\(carSet) is the car of \(which) and \(days.count == 1 ? "its" : "their") sessions.",
                systemImage: "car"
            )
            .accessibilityIdentifier("trackday.car.set")
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Label("No car is set for \(which). What was driven?", systemImage: "car")
                    .help(days.map(\.label).joined(separator: "\n"))
                    .accessibilityIdentifier("trackday.car.question")
                HStack(spacing: 6) {
                    TextField("Car", text: $car, prompt: Text("What was driven"))
                        .labelsHidden()
                        .onSubmit(set)
                        .frame(maxWidth: 240)
                        .accessibilityIdentifier("trackday.car")
                    if !knownCars.isEmpty {
                        Menu {
                            ForEach(knownCars, id: \.self) { known in
                                Button(known) {
                                    car = known
                                    set()
                                }
                            }
                        } label: {
                            Label("Cars in the Logbook", systemImage: "car")
                        }
                        .labelStyle(.iconOnly).fixedSize()
                        .accessibilityLabel("Cars in the Logbook")
                        .help("A car the logbook already knows")
                        .accessibilityIdentifier("trackday.car.known")
                    }
                    Button("Set Car", action: set)
                        .disabled(car.trimmingCharacters(in: .whitespaces).isEmpty)
                        .help(
                            days.count == 1
                                ? "Set the car of the day and its sessions"
                                : "Set the car of the \(days.count) days and their sessions"
                        )
                        .accessibilityIdentifier("trackday.car.setButton")
                }
            }
        }
    }

    /// "23 Aug 2026 · Sonoma", or "the 3 new days".
    private var which: String { days.count == 1 ? days[0].label : "the \(days.count) new days" }
}
