import ProjectModel
import SwiftUI
import TelemetryKit

/// The goals at a circuit on its card (#461): each with how far there is to go, or when it was
/// reached; Add Goal… sets another.
struct CircuitGoalsSection: View {
    let progress: [GoalProgress]
    let speed: SpeedDisplayUnit
    /// What the editor offers: the circuit, its corners, the cars driven there, the best lap there.
    let circuitKey: String
    let corners: [String]
    let cars: [String]
    let best: Double?
    let add: (Goal) -> Void
    let remove: (Goal) -> Void
    @State private var adding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Goals").font(.subheadline.weight(.semibold))
            if progress.isEmpty {
                Text("No goals here yet: a lap time, how consistent your laps are, or a corner.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(Array(progress.enumerated()), id: \.element.id) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: item.isReached ? "checkmark.seal.fill" : "target")
                        .foregroundStyle(item.isReached ? Color.green : Color.secondary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(Self.heading(item.goal, speed: speed)).font(.callout.weight(.semibold))
                        Text(item.status(speed: speed)).font(.caption).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("circuit.goal.\(index + 1)")
                    Spacer()
                    Button {
                        remove(item.goal)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove Goal")
                    .help("Remove this goal")
                    .accessibilityIdentifier("circuit.goal.remove.\(index + 1)")
                }
            }
            Button("Add Goal…") { adding = true }
                .help("Set a lap time, a consistency or a corner to aim for here")
                .accessibilityIdentifier("circuit.goal.add")
                .popover(isPresented: $adding, arrowEdge: .bottom) {
                    GoalEditor(
                        circuitKey: circuitKey, corners: corners, cars: cars, best: best, speed: speed,
                        add: { add($0) })
                }
        }
    }

    /// "1:40.00 lap in the Miata, by 1 Oct 2026".
    static func heading(_ goal: Goal, speed: SpeedDisplayUnit) -> String {
        var text = goal.title(speed: speed)
        text = text.prefix(1).uppercased() + text.dropFirst()
        if !goal.car.isEmpty { text += " in the \(goal.car)" }
        if let by = goal.by { text += ", by \(by.formatted(date: .abbreviated, time: .omitted))" }
        return text
    }
}

/// Sets a goal at a circuit (#461).
struct GoalEditor: View {
    enum Kind: String, CaseIterable, Identifiable {
        case lapTime = "Lap Time"
        case consistency = "Consistency"
        case corner = "A Corner"
        var id: String { rawValue }
    }

    enum CornerMeasure: String, CaseIterable, Identifiable {
        case time = "Time Through It"
        case speed = "Speed at the Apex"
        var id: String { rawValue }
    }

    let circuitKey: String
    let corners: [String]
    let cars: [String]
    let best: Double?
    let speed: SpeedDisplayUnit
    let add: (Goal) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var kind = Kind.lapTime
    @State private var corner = ""
    @State private var measure = CornerMeasure.time
    @State private var text = ""
    @State private var car = ""
    @State private var hasDate = false
    @State private var date = Date()

    var body: some View {
        Form {
            Picker("Goal", selection: $kind) {
                ForEach(availableKinds) { Text($0.rawValue).tag($0) }
            }
            .accessibilityIdentifier("goal.kind")
            if kind == .corner {
                Picker("Corner", selection: $corner) {
                    ForEach(corners, id: \.self) { Text("Turn \($0)").tag($0) }
                }
                Picker("Measure", selection: $measure) {
                    ForEach(CornerMeasure.allCases) { Text($0.rawValue).tag($0) }
                }
            }
            TextField(fieldLabel, text: $text, prompt: Text(prompt))
                .onSubmit(commit)
                .accessibilityIdentifier("goal.target")
            Picker("Car", selection: $car) {
                Text("Any Car").tag("")
                ForEach(cars, id: \.self) { Text($0).tag($0) }
            }
            Toggle("By a date", isOn: $hasDate)
            if hasDate {
                DatePicker("By", selection: $date, displayedComponents: .date)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add Goal", action: commit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(target == nil)
                    .accessibilityIdentifier("goal.addButton")
            }
        }
        .padding()
        .frame(width: 340)
        .onAppear { corner = corners.first ?? "" }
    }

    /// A corner can only be aimed at once the circuit's corners have been read.
    private var availableKinds: [Kind] { corners.isEmpty ? [.lapTime, .consistency] : Kind.allCases }

    private var fieldLabel: String {
        switch kind {
        case .lapTime: "Lap time"
        case .consistency: "Laps within"
        case .corner: measure == .time ? "Time" : "Speed (\(speed == .kph ? "km/h" : speed.rawValue))"
        }
    }

    private var prompt: String {
        switch kind {
        case .lapTime: best.map { "Best here is \(LogbookTrends.lapTime($0))" } ?? "1:40.00"
        case .consistency: "0.80 s"
        case .corner: measure == .time ? "6.20 s" : "90"
        }
    }

    /// What was typed, read in the field's unit; `nil` while it is not a number above zero.
    var target: Goal.Target? {
        let typed = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: " s", with: "")
        switch kind {
        case .lapTime:
            guard let seconds = TimeParsing.seconds(from: typed), seconds > 0 else { return nil }
            return .lapTime(seconds: seconds)
        case .consistency:
            guard let seconds = Double(typed), seconds > 0 else { return nil }
            return .consistency(seconds: seconds)
        case .corner:
            guard !corner.isEmpty, let value = Double(typed), value > 0 else { return nil }
            return measure == .time
                ? .cornerTime(label: corner, seconds: value)
                : .cornerSpeed(label: corner, metersPerSecond: value / speed.factorFromMetersPerSecond)
        }
    }

    /// Reads the field as it is now: Return can arrive before the redraw for the last digit.
    private func commit() {
        guard let target else { return }
        add(Goal(circuitKey: circuitKey, target: target, car: car, by: hasDate ? date : nil))
        dismiss()
    }
}
