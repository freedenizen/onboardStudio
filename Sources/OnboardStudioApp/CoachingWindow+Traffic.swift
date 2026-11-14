import ProjectModel
import SwiftUI
import TelemetryKit

// Marking a corner as held up by traffic or a flag (#571).
extension CoachingContent {
    /// Marks the stretch the corner was read over on this lap as `kind`, or clears any mark there
    /// when `kind` is `nil`: one undo step, and the reading leaves the corner out from then on.
    func setTraffic(
        _ kind: TrafficSpan.Kind?, corner index: Int, analysis: CoachingAnalysis, selection: CoachingSelection
    ) {
        guard let comparison = analysis.corners.first(where: { $0.index == index }) else { return }
        let times = analysis.sessionTimes(of: comparison)
        var settings = selection.settings
        settings.traffic = settings.traffic.marking(times.lowerBound, times.upperBound, as: kind)
        guard settings.traffic != selection.traffic else { return }
        source.setSettings(settings, undoName: Self.undoName(for: kind))
    }

    static func undoName(for kind: TrafficSpan.Kind?) -> String {
        switch kind {
        case .traffic: "Mark Traffic"
        case .flag: "Mark Flag"
        case nil: "Clear Traffic Mark"
        }
    }
}

/// What a corner was marked as on the lap being read, as the detail's picker offers it.
enum CornerMark: Hashable, CaseIterable {
    case none
    case traffic
    case flag

    init(_ traffic: CornerTraffic?) {
        switch traffic {
        case let traffic? where traffic.onLap: self = traffic.kind == .flag ? .flag : .traffic
        default: self = .none
        }
    }

    var kind: TrafficSpan.Kind? {
        switch self {
        case .none: nil
        case .traffic: .traffic
        case .flag: .flag
        }
    }

    var title: String {
        switch self {
        case .none: "Driven Freely"
        case .traffic: "Held Up by Traffic"
        case .flag: "Under a Flag"
        }
    }
}

/// The detail's control for marking the corner, and what a mark means for the reading.
struct CornerMarkPicker: View {
    let comparison: CornerComparison
    let referencePhrase: String
    let lapNumber: Int
    let mark: (TrafficSpan.Kind?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker(
                "On lap \(lapNumber):",
                selection: Binding(get: { CornerMark(comparison.traffic) }, set: { mark($0.kind) })
            ) {
                ForEach(CornerMark.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            .fixedSize()
            .help("Mark this corner as held up by traffic or a flag, so the coaching leaves it out")
            .accessibilityIdentifier("coaching.trafficMark")
            if let traffic = comparison.traffic {
                Text(explanation(traffic))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("coaching.trafficNote")
            }
        }
    }

    private func explanation(_ traffic: CornerTraffic) -> String {
        let leftOut = "It is not an opportunity and does not count towards consistency."
        if traffic.onLap { return "Lap \(lapNumber) was \(traffic.kind.phrase) here. " + leftOut }
        return "\(referencePhrase.prefix(1).uppercased() + referencePhrase.dropFirst()) was \(traffic.kind.phrase) "
            + "here, so the two are not compared. " + leftOut
    }
}

/// The walkthrough's way to leave a corner out: it was traffic or a flag, not the driving.
struct LeaveCornerOutMenu: View {
    let mark: (TrafficSpan.Kind) -> Void

    var body: some View {
        Menu("Leave This Corner Out") {
            Button("Held Up by Traffic") { mark(.traffic) }
            Button("Under a Flag") { mark(.flag) }
        }
        .fixedSize()
        .help("This corner was not driven as you chose: mark it, and the coaching leaves it out")
        .accessibilityIdentifier("coaching.walkthrough.leaveOut")
    }
}

/// The corners a mark leaves out of the reading, said under the lap's sentence.
struct LeftOutCorners: View {
    let analysis: CoachingAnalysis

    var body: some View {
        let leftOut = analysis.corners.filter { $0.traffic != nil }
        if !leftOut.isEmpty {
            Text(
                "Left out, marked as traffic or a flag: "
                    + leftOut.map { "Turn \($0.label)" }.formatted(.list(type: .and)) + "."
            )
            .font(.callout).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("coaching.walkthrough.leftOut")
        }
    }
}
