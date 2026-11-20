import ProjectModel
import SwiftUI

/// Laps as data in a window of their own (#556): Window ▸ Analysis, or Analyse Laps… on a logbook
/// session, beside the document or the logbook as Coaching and Replay are.
struct AnalysisWindow: View {
    static let windowID = "analysis"

    private var model = LapAnalysisModel.shared
    private var active = ActiveEditor.shared

    /// The front project's laps.
    static func open(_ openWindow: OpenWindowAction) {
        LapAnalysisModel.shared.showFrontProject(editor: ActiveEditor.shared.editor)
        openWindow(id: windowID)
    }

    /// A logbook session's laps.
    static func open(_ openWindow: OpenWindowAction, entry: LogbookEntry) {
        LapAnalysisModel.shared.show(entry: entry)
        openWindow(id: windowID)
    }

    var body: some View {
        LapAnalysisView(model: model)
            .frame(minWidth: 900, minHeight: 520)
            // Window ▸ Analysis opens the scene with nothing asked for: the front project's laps,
            // when there is one, are what the user means.
            .onAppear {
                if !model.hasSource, let editor = active.editor { model.showFrontProject(editor: editor) }
            }
    }
}
