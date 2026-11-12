import MediaKit
import ProjectModel
import SwiftUI
import TelemetryKit

/// Where the time went (#321): one lap of the front project's data read against a reference —
/// the best lap, the fastest rolling lap, the optimal lap spliced from the best sectors, another
/// lap, or a lap of another data file — as the top opportunities with what to try, and every
/// corner in a table. Selecting a corner, or Show Me, moves the playhead there.
///
/// A window beside the document rather than an inspector section: a corner table needs width,
/// and the inspector is a column. It follows the front document the way the attribute window
/// does, through `ActiveEditor`.
struct CoachingWindow: View {
    static let windowID = "coaching"

    private var active = ActiveEditor.shared
    private var target = CoachingTarget.shared
    @Environment(\.openWindow) private var openWindow
    /// The walkthrough or every corner (#458), as `CoachingContent` reads it.
    @AppStorage("coaching.mode", store: UITestSupport.paneDefaults) private var mode = CoachingMode.walkthrough

    /// The front project's coaching.
    static func open(_ openWindow: OpenWindowAction) {
        CoachingTarget.shared.showFrontProject()
        openWindow(id: windowID)
    }

    /// A logbook session's coaching, with no project needed (#396).
    static func open(_ openWindow: OpenWindowAction, entry: LogbookEntry) {
        CoachingTarget.shared.show(entry)
        openWindow(id: windowID)
    }

    var body: some View {
        Group {
            if case .logbook = target.kind, let source = target.logbookSource {
                CoachingContent(source: source)
                    .id(source.id)
            } else if let editor = active.editor {
                CoachingContent(source: ProjectCoachingSource(editor: editor))
                    .id(ObjectIdentifier(editor))
                    // The menu bar reaches this document from here too: Edit ▸ Undo names and takes
                    // back the last edit, and the Project menu's items apply to it.
                    .focusedSceneValue(\.editor, editor)
                    .background(DocumentWindowTag())
            } else {
                ContentUnavailableView(
                    "No Project Open", systemImage: "flag.checkered",
                    description: Text(
                        "Open a project with a data file and choose Project ▸ Coaching…, or select a session in "
                            + "the Logbook and choose Coach…, to see where its laps lost time."))
            }
        }
        .frame(minWidth: 880, minHeight: 480)
        .toolbar {
            // In the window's own toolbar from the start: an item that came with the analysis
            // changed the toolbar under the view that registers the window for Undo (#458).
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $mode) {
                    ForEach(CoachingMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help("Be taken through the lap's biggest losses, or see every corner at once")
                .disabled(active.editor == nil && target.logbookSource == nil)
                .accessibilityIdentifier("coaching.mode")
            }
            ToolbarItem(placement: .primaryAction) {
                // The same laps, raced round the circuit (#415).
                Button("Replay", systemImage: "car.side") {
                    if case .logbook = target.kind, let source = target.logbookSource {
                        ReplayWindow.open(openWindow, entry: source.entry)
                    } else {
                        ReplayWindow.open(openWindow)
                    }
                }
                .help("Race this session's laps round the circuit in 3D")
                .accessibilityIdentifier("coaching.replay")
            }
        }
    }
}

/// What the window reads for the front document: which input, lap and reference, resolved from
/// the project's coaching settings with the defaults filled in.
struct CoachingSelection: Hashable, Sendable {
    var input: Input
    var lapNumber: Int
    var reference: CoachingSettings.Reference
    var alignByPosition: Bool
    /// A cheap fingerprint of the session, so a re-import re-reads the analysis.
    var sessionStamp: Int

    var settings: CoachingSettings {
        CoachingSettings(
            dataInputID: input.id, lap: lapNumber, reference: reference, alignByPosition: alignByPosition)
    }

    /// The analysis options the choices amount to.
    var options: CoachingOptions {
        var options = CoachingOptions()
        if alignByPosition { options.alignment = .byPosition }
        return options
    }
}

/// A lap of another data file, as a reference.
struct OtherReference: Sendable {
    let session: TelemetrySession
    let label: String
    let lap: Int
}
