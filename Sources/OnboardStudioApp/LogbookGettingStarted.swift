import ProjectModel
import SwiftUI

/// One step of the Logbook's Getting Started (#452).
struct LogbookStep: Identifiable {
    enum Action { case addFiles, showCarlessDay, chooseSession, coach, showTrends }

    let title: String
    let detail: String
    let done: Bool
    let action: Action
    /// The button can do nothing yet: there is no session to act on.
    var unavailable = false
    var id: String { title }

    var buttonTitle: String {
        switch action {
        case .addFiles: "Add Files…"
        case .showCarlessDay: "Show the Day"
        case .chooseSession: "Choose the Newest Session"
        case .coach: "Coach the Newest Session"
        case .showTrends: "Show Trends"
        }
    }
}

extension LogbookModel {
    /// From a day's files to a video, a coaching session and the progress across visits — the way a
    /// new driver goes, read from the logbook itself where it can be: a session with a project made
    /// from it has had its video started. Coaching and Trends leave no trace in it, so the window
    /// remembers them (`Preferences.logbookCoached`, `logbookSawProgress`).
    func gettingStartedSteps(coached: Bool, sawProgress: Bool) -> [LogbookStep] {
        let progress = LogbookChecklist(entries: entries, coached: coached, sawProgress: sawProgress)
        let empty = !progress.hasSessions
        return [
            LogbookStep(
                title: "Add a track day's files",
                detail: "Your logger's files and the camera's videos, or the "
                    + "folder holding them: each goes on the day its date and circuit say.",
                done: progress.hasSessions, action: .addFiles),
            LogbookStep(
                title: "Say what was driven",
                detail: "Type the car on the day; its sessions take it, and the car "
                    + "joins the garage under Cars in the sidebar.",
                done: progress.carsNamed, action: .showCarlessDay, unavailable: empty),
            LogbookStep(
                title: "Make a video of a session",
                detail: "Choose a session; New Project at the foot of its "
                    + "detail lays out its data and video with gauges, ready to export.",
                done: progress.madeVideo, action: .chooseSession, unavailable: empty),
            LogbookStep(
                title: "Be coached through a lap",
                detail: "Coach… reads the session's laps against your best and "
                    + "walks you through the corners where the time went.",
                done: progress.coached, action: .coach, unavailable: empty),
            LogbookStep(
                title: "See how you are getting on",
                detail: "Trends draws your lap times across visits to a "
                    + "circuit; the Season sums a year up.",
                done: progress.sawProgress, action: .showTrends, unavailable: empty),
        ]
    }

    /// The newest session, what the checklist's buttons act on.
    var newestSession: LogbookEntry? { entries.first }
}

/// Getting Started in the Logbook's detail column while no session is chosen (#452): where the app
/// opens, a new user was told what the logbook keeps and not what to do with it.
struct LogbookGettingStartedView: View {
    let steps: [LogbookStep]
    let perform: (LogbookStep.Action) -> Void
    let hide: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Getting Started").font(.title3.weight(.semibold))
                        .accessibilityIdentifier("logbook.gettingStarted.title")
                    Text("From a day's files to a video, a coaching session and your progress.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: step.done ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(step.done ? Color.green : Color.secondary)
                            .padding(.top, 2)
                            .accessibilityLabel(step.done ? "Done" : "To Do")
                            .help(step.done ? "Done" : "Still to do")
                            .accessibilityIdentifier("logbook.gettingStarted.check.\(index + 1)")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.title).fontWeight(step.done ? .regular : .semibold)
                                .foregroundStyle(step.done ? .secondary : .primary)
                            if !step.done {
                                Text(step.detail).font(.caption).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Button(step.buttonTitle) { perform(step.action) }
                                    .controlSize(.small).padding(.top, 2)
                                    .disabled(step.unavailable)
                                    .accessibilityIdentifier("logbook.gettingStarted.action.\(index + 1)")
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
                HStack {
                    Button("Open the User Guide") { HelpLinks.open(.userGuide) }.controlSize(.small)
                    Spacer()
                    Button("Hide", action: hide).controlSize(.small)
                        .help("Hide Getting Started; Help ▸ Show Getting Started brings it back")
                        .accessibilityIdentifier("logbook.gettingStarted.hide")
                }
            }
            .padding()
        }
    }
}

extension LogbookWindow {
    var gettingStarted: [LogbookStep] { model.gettingStartedSteps(coached: coached, sawProgress: sawProgress) }

    /// The Coaching window on the session; the checklist's step ticks (#452).
    func coach(_ entry: LogbookEntry) {
        coached = true
        CoachingWindow.open(openWindow, coaching: entry)
    }

    func performGettingStarted(_ action: LogbookStep.Action) {
        switch action {
        case .addFiles: addFiles()
        case .showCarlessDay:
            // The newest day with a session that names no car: its header has the Car field.
            let carless = LogbookChecklist.sessionWithoutCar(in: model.entries)
            if let day = carless?.trackDayID.flatMap({ id in model.days.first { $0.id == id } }) {
                scope = .day(id: day.id, title: day.label)
                view = .sessions
            }
        case .chooseSession:
            if let entry = model.newestSession {
                scope = .all
                selection = [entry.id]
                view = .sessions
            }
        case .coach: if let entry = model.newestSession { coach(entry) }
        case .showTrends: view = .trends
        }
    }

    /// Help ▸ Show Getting Started with the Logbook in front: the checklist, where nothing chosen
    /// stands in front of it.
    func showGettingStartedNow() {
        showGettingStarted = true
        selection = []
    }
}
