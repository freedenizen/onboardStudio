import ProjectModel
import SwiftUI

/// The Logbook's edits, each one step of Edit ▸ Undo in the Logbook window, named for what it did
/// (#454). Logbook files are not a document, and every edit used to go straight to disk with no way
/// back: a session removed by mistake had to be added again, and a mistaken import put right one
/// session at a time. An edit is recorded as what it changed (`LogbookChange`), so taking it back
/// leaves alone what the Coaching window or an import wrote since.
///
/// The undo manager is the Logbook window's, passed by the window: an edit made from a project's
/// window or the Coaching window is not one of the Logbook's, and on a project's undo manager it
/// would mark the document edited.
extension LogbookModel {
    /// Does `body` to the logbook and shows the result, as one edit called `name` when there is an
    /// undo manager to record it with.
    func edit(_ name: String, undo: UndoManager?, _ body: (Logbook) throws -> Void) {
        let logbook = AppLogbook.shared
        let before = undo == nil ? nil : logbook.snapshot()
        try? body(logbook)
        reload()
        if let before { record(name, since: before, undo: undo) }
    }

    /// What changed since `before`, recorded as one edit: for work done in steps of its own, as an
    /// import is. The model must have been reloaded since.
    func record(_ name: String, since before: LogbookChange.Snapshot, undo: UndoManager?) {
        let change = LogbookChange(from: before, to: LogbookChange.Snapshot(entries: entries, days: days, cars: cars))
        register(change, name: name, undo: undo)
    }

    private func register(_ change: LogbookChange, name: String, undo: UndoManager?) {
        guard let undo, !change.isEmpty else { return }
        undo.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                try? AppLogbook.shared.apply(change.reversed)
                model.reload()
                // Registered while undoing, so it is Redo's.
                model.register(change.reversed, name: name, undo: undo)
            }
        }
        undo.setActionName(name)
    }

    // MARK: - The edits

    func remove(_ ids: [UUID], undo: UndoManager?) {
        edit(LogbookEditName.removing(ids.count), undo: undo) { logbook in
            for id in ids { try logbook.remove(id: id) }
        }
    }

    func removeDay(_ day: TrackDay, undo: UndoManager?) {
        edit("Remove Track Day", undo: undo) { try $0.removeDay(id: day.id, andSessions: true) }
    }

    func move(_ ids: [UUID], toDay day: UUID, undo: UndoManager?) {
        edit(LogbookEditName.moving(ids.count), undo: undo) { try $0.move(ids, toDay: day) }
    }

    /// Each session onto the day its own date and circuit say.
    func moveToOwnDays(_ ids: [UUID], undo: UndoManager?) {
        edit(LogbookEditName.moving(ids.count), undo: undo) { try $0.moveToOwnDays(ids) }
    }

    /// The car of several sessions at once, typed or chosen in the detail of a selection.
    func setCar(_ car: String, ofSessions ids: [UUID], undo: UndoManager?) {
        let name = car.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        edit("Change Car", undo: undo) { logbook in
            for var entry in logbook.entries() where ids.contains(entry.id) && entry.car != name {
                entry.car = name
                try logbook.save(entry)
            }
            try logbook.addToGarage(name)
        }
    }
}
