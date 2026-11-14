import ProjectModel
import SwiftUI
import TelemetryKit

/// Which of its two faces the Coaching window shows (#458).
enum CoachingMode: String, CaseIterable, Identifiable {
    case walkthrough, allCorners

    var id: String { rawValue }

    var title: String {
        switch self {
        case .walkthrough: "Walkthrough"
        case .allCorners: "All Corners"
        }
    }
}

/// The guided debrief (#458): the lap in a sentence, then its three biggest losses one corner at a
/// time — what happened, what to try, where it was — then the plan made of what the driver chose
/// to try, kept with the circuit.
struct CoachingWalkthroughView<Change: View>: View {
    let analysis: CoachingAnalysis
    let lapNumber: Int
    let units: CoachingUnits
    /// Every other complete lap of the session, for the spread of lines through a corner.
    let others: [LapProfile]
    let source: any CoachingSource
    /// The lap, what it is compared with and how the two are lined up, in a popover.
    let change: () -> Change
    /// What Watch plays for a corner (#516).
    let watch: (CornerComparison) async -> [WatchClip]
    /// Marks a corner as held up by traffic or a flag (#571); the reading then leaves it out.
    var markTraffic: ((CornerComparison, TrafficSpan.Kind) -> Void)?
    /// Answers the telemetry's traffic suggestion for a corner (#572): traffic, or not.
    var answerSuggestion: ((TrafficSuggestion, Bool) -> Void)?

    @State private var step: CoachingWalkthrough.Step = .lap
    /// The corners the driver means to try next time, by index: all of them to begin with.
    @State private var chosen: Set<Int>
    @State private var draft: NextSessionPlan?
    @State private var showingChange = false
    /// The circuit the plan was kept for, once it has been; empty when kept in the project alone.
    @State private var savedFor: String?

    init(
        analysis: CoachingAnalysis, lapNumber: Int, units: CoachingUnits, others: [LapProfile],
        source: any CoachingSource, watch: @escaping (CornerComparison) async -> [WatchClip],
        markTraffic: ((CornerComparison, TrafficSpan.Kind) -> Void)? = nil,
        answerSuggestion: ((TrafficSuggestion, Bool) -> Void)? = nil,
        @ViewBuilder change: @escaping () -> Change
    ) {
        self.markTraffic = markTraffic
        self.answerSuggestion = answerSuggestion
        self.analysis = analysis
        self.lapNumber = lapNumber
        self.units = units
        self.others = others
        self.source = source
        self.change = change
        self.watch = watch
        _chosen = State(initialValue: Set(analysis.top.map(\.corner.index)))
    }

    private var walkthrough: CoachingWalkthrough { CoachingWalkthrough(analysis: analysis) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                Group {
                    switch step {
                    case .lap: lapStep
                    case .corner(let index):
                        if let opportunity = analysis.top.first(where: { $0.corner.index == index }) {
                            cornerStep(opportunity)
                        }
                    case .plan: planStep
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            navigation
        }
    }

    // MARK: - The lap

    private var lapStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Lap \(lapNumber)").font(.largeTitle.weight(.semibold))
            Text(analysis.headline(lapNumber: lapNumber, units: units))
                .font(.title3)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("coaching.walkthrough.headline")
            let detail = [analysis.splicedFrom, analysis.alignmentLine].compactMap { $0 }.joined(separator: ". ")
            if !detail.isEmpty {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Button("Change…") { showingChange = true }
                .popover(isPresented: $showingChange, arrowEdge: .bottom) { change() }
                .help("Choose the lap, what it is compared with, and how the two are lined up")
                .accessibilityIdentifier("coaching.walkthrough.change")
            if analysis.top.isEmpty {
                Text("Nothing was lost against \(analysis.referencePhrase), so there is no corner to go through.")
                    .foregroundStyle(.secondary)
            } else {
                Text(
                    analysis.top.count == 1
                        ? "One corner to go through:"
                        : "\(analysis.top.count) corners to go through, biggest loss first:"
                )
                .font(.headline)
                .padding(.top, 6)
                ForEach(analysis.top) { opportunity in
                    Label(opportunity.note.headline, systemImage: "\(opportunity.rank).circle")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            LeftOutCorners(analysis: analysis)
            SuggestedCorners(analysis: analysis)
        }
    }

    // MARK: - A corner

    private func cornerStep(_ opportunity: Opportunity) -> some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text(opportunity.note.headline)
                    .font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("coaching.walkthrough.corner")
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(opportunity.note.evidence, id: \.self) { line in
                        Label(line, systemImage: "circle.fill")
                            .labelStyle(EvidenceLabelStyle())
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text("What to try").font(.headline).padding(.top, 4)
                // In full: cut to a line on a card, it was the part that could not be read (#458).
                Text(opportunity.note.suggestion)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("coaching.walkthrough.suggestion")
                Toggle("Try this next time", isOn: tryBinding(opportunity.corner.index))
                    .accessibilityIdentifier("coaching.walkthrough.try")
                CornerTrafficControls(
                    corner: opportunity.corner, units: units, markTraffic: markTraffic,
                    answerSuggestion: answerSuggestion)
            }
            .frame(minWidth: 280, maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 16) {
                CornerWatchView { await watch(opportunity.corner) }
                    .id(opportunity.corner.index)
                CornerLinesView(analysis: analysis, comparison: opportunity.corner, units: units, others: others)
                PhaseLossBars(comparison: opportunity.corner, units: units)
            }
            .frame(width: 320)
        }
    }

    private func tryBinding(_ corner: Int) -> Binding<Bool> {
        Binding(
            get: { chosen.contains(corner) },
            set: { isOn in
                if isOn { chosen.insert(corner) } else { chosen.remove(corner) }
            })
    }

    // MARK: - The plan

    private var planStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your Plan").font(.largeTitle.weight(.semibold))
            Text(keptWhere).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let draft, !draft.experiments.isEmpty {
                ForEach(Array(draft.experiments.enumerated()), id: \.element.id) { index, experiment in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(experiment.title).font(.headline)
                        TextField(experiment.title, text: experimentText(index), axis: .vertical)
                            .lineLimit(2...6)
                            .accessibilityIdentifier("coaching.walkthrough.experiment.\(index)")
                    }
                }
            } else {
                Text("Nothing to try has been chosen. Go back to a corner and turn on Try this next time.")
                    .foregroundStyle(.secondary)
            }
            if let previous = source.circuitPlan, !previous.experiments.isEmpty,
                previous.experiments.map(\.text) != draft?.experiments.map(\.text)
            {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Planned last time").font(.headline)
                    ForEach(previous.experiments) { experiment in
                        Text("\(experiment.title): \(experiment.text)")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 6)
            }
            if let savedFor {
                Label(
                    savedFor.isEmpty ? "Saved in the project." : "Saved for \(savedFor).",
                    systemImage: "checkmark.circle"
                )
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("coaching.walkthrough.saved")
            }
        }
    }

    /// Where the plan will be kept, in a sentence.
    private var keptWhere: String {
        if let circuit = source.planCircuitName {
            return "Kept for \(circuit): it is there when you prepare to go back, and on the Season page."
        }
        if source.editor != nil { return "Kept in the project. Name the circuit to have it kept for the circuit too." }
        return "The Logbook does not know this session's circuit, so the plan cannot be kept for it. "
            + "Choose the circuit for its track day in the Logbook."
    }

    private var canSave: Bool {
        guard let draft, !draft.experiments.isEmpty else { return false }
        return source.planCircuitName != nil || source.editor != nil
    }

    /// The plan from the corners chosen, in the order they were gone through; text already edited
    /// for a corner is kept when the driver goes back and comes here again.
    private func makeDraft() {
        let edited = Dictionary(
            (draft?.experiments ?? []).map { ($0.cornerLabel, $0.text) }, uniquingKeysWith: { first, _ in first })
        var plan = NextSessionPlan.chosen(
            analysis.top.filter { chosen.contains($0.corner.index) }, from: analysis, lapNumber: lapNumber)
        for index in plan.experiments.indices {
            if let text = edited[plan.experiments[index].cornerLabel] { plan.experiments[index].text = text }
        }
        draft = plan
    }

    private func experimentText(_ index: Int) -> Binding<String> {
        Binding(
            get: { draft?.experiments.indices.contains(index) == true ? draft?.experiments[index].text ?? "" : "" },
            set: { text in
                guard draft?.experiments.indices.contains(index) == true else { return }
                draft?.experiments[index].text = text
                savedFor = nil
            })
    }

    private func save() {
        guard var plan = draft else { return }
        plan.experiments = plan.experiments.map { experiment in
            var trimmed = experiment
            trimmed.text = experiment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed
        }
        if source.savePlan(plan) { savedFor = source.planCircuitName ?? "" }
    }

    // MARK: - Moving through

    private var navigation: some View {
        HStack {
            Button("Back") { go(walkthrough.previous(before: step)) }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(walkthrough.previous(before: step) == nil)
                .help("The step before (⌘[)")
                .accessibilityIdentifier("coaching.walkthrough.back")
            Spacer()
            Text(stepTitle)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("coaching.walkthrough.step")
            Spacer()
            if step == .plan {
                Button("Save Plan", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
                    .accessibilityIdentifier("coaching.walkthrough.savePlan")
            } else {
                Button("Next") { go(walkthrough.next(after: step)) }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("coaching.walkthrough.next")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var stepTitle: String {
        switch step {
        case .lap: return "The Lap"
        case .corner(let index):
            let label = analysis.top.first { $0.corner.index == index }?.corner.label ?? "\(index)"
            guard let position = walkthrough.position(of: step) else { return "Turn \(label)" }
            return "Turn \(label) · \(position.number) of \(position.count)"
        case .plan: return "Your Plan"
        }
    }

    private func go(_ destination: CoachingWalkthrough.Step?) {
        guard let destination else { return }
        if destination == .plan { makeDraft() }
        step = destination
    }
}
