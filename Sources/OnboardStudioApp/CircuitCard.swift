import ProjectModel
import SwiftUI

/// Before going back to a circuit (#460): the personal best there, the last visit, the plan to try
/// — written and changed right here — and the corners where the last visit lost the most against
/// the best. The plan was made only in the Coaching window and shown again only there and on the
/// Season page, and a new day at the circuit showed nothing of the visits before it.
struct CircuitCard: View {
    let title: String
    let brief: CircuitBrief
    let plan: NextSessionPlan?
    /// The circuit is one the catalogue knows, which a plan is kept for.
    let canPlan: Bool
    var showsNewDay = true
    let newDay: () -> Void
    /// Opens Coaching on the last visit, to make a plan from its laps; `nil` with no lap to read.
    let makePlan: (() -> Void)?
    /// Names the circuit's turns on its best lap (#550); `nil` with no lap to name them on.
    var nameTurns: (() -> Void)?
    /// The plan as changed, and the name of the change for Edit ▸ Undo.
    let savePlan: (NextSessionPlan?, String) -> Void
    /// The goals at the circuit and how far each has come (#461), and what setting one offers.
    var goals: [GoalProgress] = []
    var speed: SpeedDisplayUnit = .kph
    var corners: [String] = []
    var cars: [String] = []
    var addGoal: (Goal) -> Void = { _ in }
    var removeGoal: (Goal) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.title3.weight(.semibold))
                        .accessibilityIdentifier("circuit.card.title")
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                        .accessibilityIdentifier("circuit.card.subtitle")
                }
                Spacer()
                if let nameTurns {
                    Button("Name Turns…", systemImage: "signpost.right", action: nameTurns)
                        .help("Say what the circuit calls each of its turns, on your best lap here")
                        .accessibilityIdentifier("circuit.card.nameTurns")
                }
                if showsNewDay {
                    Button("New Track Day Here…", systemImage: "calendar.badge.plus", action: newDay)
                        .help("Begin a day at \(title), before any file exists")
                        .accessibilityIdentifier("circuit.card.newDay")
                }
            }
            if let line = lastVisitLine {
                Text(line).font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("circuit.card.lastVisit")
            }
            planSection
            if !brief.isEmpty {
                CircuitGoalsSection(
                    progress: goals, speed: speed, circuitKey: brief.circuitKey, corners: corners, cars: cars,
                    best: brief.personalBest?.seconds, add: addGoal, remove: removeGoal)
            }
            if !brief.cornersToWorkOn.isEmpty { cornersSection }
        }
        .padding()
    }

    /// "3 visits · personal best 1:42.31 on 12 Oct 2026 in a Miata".
    private var subtitle: String {
        var parts = ["\(brief.visits) visit\(brief.visits == 1 ? "" : "s")"]
        if let best = brief.personalBest {
            var text = "personal best \(LogbookTrends.lapTime(best.seconds))"
            if let date = best.date { text += " on \(date.formatted(date: .abbreviated, time: .omitted))" }
            if !best.car.isEmpty { text += " in \(best.car)" }
            parts.append(text)
        }
        return brief.isEmpty ? "No sessions here yet." : parts.joined(separator: " · ")
    }

    /// "Last visit, 8 Nov 2026: best 1:43.10 over 4 sessions, 0.79 s off your best."
    private var lastVisitLine: String? {
        guard let last = brief.lastVisit else { return nil }
        let when = "Last visit, \(last.date.formatted(date: .abbreviated, time: .omitted))"
        let sessions = "\(last.sessions) session\(last.sessions == 1 ? "" : "s")"
        guard let best = last.best else { return "\(when): \(sessions), no complete lap." }
        var line = "\(when): best \(LogbookTrends.lapTime(best)) over \(sessions)"
        if let record = brief.personalBest?.seconds {
            let gap = best - record
            line += gap < 0.005 ? " — your personal best." : String(format: ", %.2f s off your best.", gap)
        } else {
            line += "."
        }
        return line
    }

    // MARK: - The plan

    @ViewBuilder private var planSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Plan for Next Time").font(.subheadline.weight(.semibold))
            if !canPlan {
                Text(
                    "A plan is kept for a circuit the app recognises; this one was named by hand. Choose it from "
                        + "the catalogue on a day's Circuit row to keep a plan for it."
                )
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            } else if let plan {
                ForEach(Array(plan.experiments.enumerated()), id: \.element.id) { index, experiment in
                    ExperimentRow(experiment: experiment, number: index + 1) { text in
                        savePlan(changing(plan, experiment.id) { $0.text = text }, "Change Experiment")
                    } remove: {
                        var changed = plan
                        changed.experiments.removeAll { $0.id == experiment.id }
                        savePlan(changed, "Remove Experiment")
                    }
                }
                HStack {
                    Button("Add Experiment") {
                        var changed = plan
                        changed.experiments.append(PlannedExperiment(cornerLabel: "", text: ""))
                        savePlan(changed, "Add Experiment")
                    }
                    .accessibilityIdentifier("circuit.plan.add")
                    if let makePlan {
                        Button("Make a Plan in Coaching…", action: makePlan)
                            .help("Coaching on the last visit's best session, to write a plan from its laps")
                    }
                    Spacer()
                    Text("Made \(plan.made.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text(
                    brief.cornersToWorkOn.isEmpty
                        ? "No plan yet: write down what to try next time."
                        : "No plan yet: begin one from the corners below, or write your own."
                )
                .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button("Start a Plan") { savePlan(brief.startingPlan(), "Start Plan") }
                        .help(
                            brief.cornersToWorkOn.isEmpty
                                ? "A plan with one line to write in"
                                : "A plan with a line for each corner below, to change as you like"
                        )
                        .accessibilityIdentifier("circuit.plan.start")
                    if let makePlan {
                        Button("Make a Plan in Coaching…", action: makePlan)
                            .help("Coaching on the last visit's best session, to write a plan from its laps")
                            .accessibilityIdentifier("circuit.plan.coach")
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("circuit.plan")
    }

    private func changing(_ plan: NextSessionPlan, _ id: UUID, _ change: (inout PlannedExperiment) -> Void)
        -> NextSessionPlan
    {
        var changed = plan
        if let index = changed.experiments.firstIndex(where: { $0.id == id }) { change(&changed.experiments[index]) }
        return changed
    }

    // MARK: - Where the last visit lost time

    private var cornersSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Where the Last Visit Lost Time").font(.subheadline.weight(.semibold))
            ForEach(brief.cornersToWorkOn) { corner in
                VStack(alignment: .leading, spacing: 1) {
                    Text(String(format: "%@: %.2f s slower than your best lap", corner.title, corner.timeLost))
                        .font(.callout)
                    if let detail = Self.detail(corner) {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("circuit.corner.\(corner.label)")
            }
        }
    }

    /// "Braked 15 m earlier; slower at the apex."
    static func detail(_ corner: CircuitBrief.Corner) -> String? {
        var parts: [String] = []
        if let earlier = corner.brakedEarlierBy, abs(earlier) > 2 {
            let metres = Int(abs(earlier).rounded())
            parts.append(earlier > 0 ? "braked \(metres) m earlier" : "braked \(metres) m later")
        }
        if let slower = corner.slowerAtApexBy, slower > 0.3 { parts.append("slower at the apex") }
        guard !parts.isEmpty else { return nil }
        let text = parts.joined(separator: "; ") + "."
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}
