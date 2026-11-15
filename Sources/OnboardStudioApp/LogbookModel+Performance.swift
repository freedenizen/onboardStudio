import MediaKit
import ProjectModel
import SwiftUI
import TelemetryKit

extension LogbookModel {
    /// Measures a session's standing starts and stops (#553), or stops measuring them, as one step
    /// of Undo. Turning them on reads the file again, off the main thread. `false` when the file
    /// could not be read; the session is left as it was.
    func measurePerformance(_ on: Bool, of entry: LogbookEntry, undo: UndoManager?) async -> Bool {
        var asked = entry
        asked.measuresPerformance = on
        var performance: PerformanceRuns.Result?
        if asked.measuresPerformanceInForce {
            let reading = asked
            let session = await Task.detached(priority: .userInitiated) { LogbookReferences.load(reading) }.value
            guard let session else { return false }
            asked.readPerformance(of: session)
            performance = asked.performance
        }
        // What the session is now, which the driver may have edited while the file was read.
        guard var latest = AppLogbook.shared.entry(id: entry.id) else { return false }
        latest.measuresPerformance = on
        latest.performance = performance
        edit(on ? "Turn On Performance Runs" : "Turn Off Performance Runs", undo: undo) { try $0.save(latest) }
        return true
    }
}
