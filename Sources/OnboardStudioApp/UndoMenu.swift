import AppKit
import SwiftUI

/// Edit ▸ Undo and Redo, named for what they will do (#209).
///
/// Every edit names itself — `EditorModel.edit("Change Sweep")` — and the undo manager has the
/// name: `undoMenuItemTitle` reads *Undo Change Sweep*. The menu SwiftUI provides never showed it,
/// though, and read a bare *Undo* whatever was about to be taken back. These items replace it,
/// with titles read from the undo manager of whatever has the keyboard, and send `undo:` and
/// `redo:` down the responder chain exactly as the standard items do — so a text field being
/// edited still undoes its own typing.
struct UndoCommands: Commands {
    private var state = UndoMenuState.shared
    /// Undo and Redo wait while a tool on the picture is open, whose session is one step (#275).
    @FocusedValue(\.editor) private var editor

    /// The responder-chain actions the standard items send, which take a sender: `undo:`, not
    /// `UndoManager.undo()`'s `undo`, which nothing in the chain answers.
    private static let undoAction = Selector(("undo:"))
    private static let redoAction = Selector(("redo:"))

    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button(state.undoTitle) {
                if let manager = state.documentUndoManagerForKeyWindow {
                    manager.undo()
                } else {
                    NSApp.sendAction(Self.undoAction, to: nil, from: nil)
                }
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!state.canUndo || editor?.pictureTool != nil)
            Button(state.redoTitle) {
                if let manager = state.documentUndoManagerForKeyWindow {
                    manager.redo()
                } else {
                    NSApp.sendAction(Self.redoAction, to: nil, from: nil)
                }
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(!state.canRedo || editor?.pictureTool != nil)
        }
    }
}

/// What Undo and Redo would do right now, kept current from the undo manager's notifications and
/// from the key window changing.
@MainActor @Observable final class UndoMenuState {
    static let shared = UndoMenuState()

    private(set) var undoTitle = "Undo"
    private(set) var redoTitle = "Redo"
    private(set) var canUndo = false
    private(set) var canRedo = false

    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var refreshPending = false

    private init() {
        // Not `NSUndoManagerCheckpoint`: it is posted whenever a group opens or closes, including
        // by the menu rebuilding itself, and listening to it froze the app in a refresh loop.
        let names: [Notification.Name] = [
            .NSUndoManagerDidCloseUndoGroup, .NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange,
            NSWindow.didBecomeKeyNotification,
        ]
        observers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { UndoMenuState.shared.scheduleRefresh() }
            }
        }
    }

    /// Windows that edit the front document without being it — the Coaching window — register
    /// here (`DocumentWindowTag`). Their own undo managers are empty; what the user means by Undo
    /// there is the document's last edit.
    /// Counted, not a set: when SwiftUI replaces the view holding a tag, the new tag registers the
    /// window before the old one leaves it, and a set forgot the window then (#458).
    @ObservationIgnored private var documentWindows: [ObjectIdentifier: Int] = [:]

    func register(_ window: NSWindow) {
        documentWindows[ObjectIdentifier(window), default: 0] += 1
        scheduleRefresh()
    }

    func unregister(_ window: NSWindow) {
        let id = ObjectIdentifier(window)
        guard let count = documentWindows[id] else { return }
        documentWindows[id] = count > 1 ? count - 1 : nil
    }

    /// The front document's undo manager when the key window is one that edits it from outside,
    /// else `nil` and the responder chain decides as usual.
    var documentUndoManagerForKeyWindow: UndoManager? {
        guard let window = NSApp.keyWindow, documentWindows[ObjectIdentifier(window)] != nil else { return nil }
        return ActiveEditor.shared.editor?.undoManager
    }

    /// The undo manager the standard items would use: the first responder's, which is the key
    /// window's unless a view keeps its own — or the document's, from a window that edits it.
    private var undoManager: UndoManager? {
        if let document = documentUndoManagerForKeyWindow { return document }
        guard let window = NSApp.keyWindow else { return nil }
        return window.firstResponder?.undoManager ?? window.undoManager
    }

    /// One refresh per turn of the run loop however many notifications arrive, and after the
    /// group that caused them has its action name.
    private func scheduleRefresh() {
        guard !refreshPending else { return }
        refreshPending = true
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.refreshPending = false
                self.refresh()
            }
        }
    }

    /// Writes only what changed: every write to an observed property rebuilds the menu, even a
    /// write of the same value.
    private func refresh() {
        let manager = undoManager
        let undo = manager?.undoMenuItemTitle ?? "Undo"
        let redo = manager?.redoMenuItemTitle ?? "Redo"
        let canUndo = manager?.canUndo ?? false
        let canRedo = manager?.canRedo ?? false
        if undo != undoTitle { undoTitle = undo }
        if redo != redoTitle { redoTitle = redo }
        if canUndo != self.canUndo { self.canUndo = canUndo }
        if canRedo != self.canRedo { self.canRedo = canRedo }
    }
}
