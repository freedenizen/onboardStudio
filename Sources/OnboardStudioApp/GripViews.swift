import ProjectModel
import SwiftUI
import TelemetryKit

// MARK: - The car's grip (#558)

extension LogbookModel {
    /// The limit `entry` is read against: its car's, in its conditions, as the driver adjusted it.
    func gripLimit(for entry: LogbookEntry) -> CarGripLimit? {
        CarGrip.limit(
            for: entry, among: entries, adjustment: Garage.car(named: entry.car, in: cars)?.gripAdjustment ?? 1)
    }

    func setGripAdjustment(_ factor: Double, forCar car: String, undo: UndoManager? = nil) {
        edit("Adjust Grip", undo: undo) { try $0.setGripAdjustment(factor, forCar: car) }
    }

    /// The car's limits on a dry and on a wet surface, for its card.
    func gripLimits(ofCar car: String) -> (dry: CarGripLimit?, wet: CarGripLimit?) {
        let adjustment = Garage.car(named: car, in: cars)?.gripAdjustment ?? 1
        func limit(_ surface: SessionConditions.Track) -> CarGripLimit? {
            var probe = LogbookEntry(file: .init(path: "", contentHash: "", byteCount: 0, importerID: ""))
            probe.car = car
            probe.conditions.track = surface
            return CarGrip.limit(for: probe, among: entries, adjustment: adjustment)
        }
        return (limit(.dry), limit(.wet))
    }
}

/// The Grip row of a session's details (#558): how much of the car's grip its best lap used,
/// what that grip is, and where braking stopped before turning.
struct GripGridRow: View {
    let use: GripUse
    let limit: CarGripLimit

    var body: some View {
        GridRow(alignment: .firstTextBaseline) {
            Text("Grip").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(GripWording.measurements(use)).fixedSize(horizontal: false, vertical: true)
                Text(GripWording.against(limit)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let gaps = GripWording.gaps(use) {
                    Text(gaps).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("logbook.detail.grip")
        }
        .help("The session's best lap, against the most grip the car has shown in conditions like these")
    }
}

/// The Grip row of a car's card (#558): what the car has shown on a dry and a wet surface, and the
/// driver's own scale on it.
struct CarGripRow: View {
    let dry: CarGripLimit?
    let wet: CarGripLimit?
    let adjustment: Double
    let adjust: (Double) -> Void

    var body: some View {
        GridRow(alignment: .firstTextBaseline) {
            Text("Grip").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                if let dry { Text("Dry: \(dry.summary)") }
                if let wet { Text("Wet: \(wet.summary)") }
                Stepper(
                    value: Binding(get: { (adjustment * 100).rounded() }, set: { adjust($0 / 100) }), in: 50...200,
                    step: 1
                ) {
                    Text("Adjusted to \(Int((adjustment * 100).rounded()))% of what it has shown")
                        .foregroundStyle(.secondary)
                }
                .help("Raise it when the car has more grip than its sessions have shown; grip use is read against this")
                .accessibilityIdentifier("car.header.gripAdjustment")
            }
            .accessibilityIdentifier("car.header.grip")
        }
    }
}
