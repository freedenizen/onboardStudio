import ProjectModel
import SwiftUI

/// The Marker and Playback menus: the timeline's commands, acting on the focused editor. Apart
/// from `EditorCommands` only for length; declared after it, so the menus follow Arrange.
///
/// With no project in front every item is dimmed and gives up its key (#450): a dimmed item still
/// takes its key, which would leave Space, M, J, K, L, I and O dead in the Logbook.
struct TimelineCommands: Commands {
    @FocusedValue(\.editor) private var editor

    /// A project is in front: the items are live and hold their keys.
    private var live: Bool { editor != nil }

    var body: some Commands {
        CommandMenu("Marker") {
            Group {
                // M to drop one, ⌘M to drop and name it, ⇧↑/⇧↓ to walk them: the Resolve bindings
                // recorded in docs/conventions.md, which Premiere shares.
                Button("Add Marker") { editor?.addMarkerAtPlayhead() }
                    .keyboardShortcut("m", modifiers: [], when: live)
                Button("Add and Name Marker…") { editor?.addAndNameMarker() }
                    .keyboardShortcut("m", modifiers: [.command], when: live)
                Button("Rename Marker…") { editor?.renameSelectedMarker() }
                    .disabled(editor?.selectedMarkerID == nil)
                Button("Delete Marker") { editor?.deleteSelectedMarker() }
                    .disabled(editor?.selectedMarkerID == nil)
                Divider()
                Button("Previous Marker") { editor?.goToPreviousMarker() }
                    .keyboardShortcut(.upArrow, modifiers: [.shift], when: live)
                Button("Next Marker") { editor?.goToNextMarker() }
                    .keyboardShortcut(.downArrow, modifiers: [.shift], when: live)
                Divider()
                // Laps are the marks the data brings with it, so they sit beside the ones you place,
                // on ⌥ rather than ⇧ to keep the two apart.
                Button("Previous Lap") { editor?.goToPreviousLap() }
                    .keyboardShortcut(.upArrow, modifiers: [.option], when: live)
                    .disabled(editor?.canJumpByLap != true)
                Button("Next Lap") { editor?.goToNextLap() }
                    .keyboardShortcut(.downArrow, modifiers: [.option], when: live)
                    .disabled(editor?.canJumpByLap != true)
            }
            .disabled(editor == nil)
        }
        CommandMenu("Playback") {
            Group {
                Button(editor?.isPlaying == true ? "Pause" : "Play") { editor?.togglePlayback() }.keyboardShortcut(
                    .space, modifiers: [], when: live)
                // `,`/`.` rather than the arrows, which belong to the selected object: a menu key
                // equivalent is matched before the key reaches the picture, so binding the arrows
                // here would stop them ever nudging. See docs/conventions.md.
                Button("Step Back") { editor?.step(by: -1) }.keyboardShortcut(",", modifiers: [], when: live)
                Button("Step Forward") { editor?.step(by: 1) }.keyboardShortcut(".", modifiers: [], when: live)
                Button("Go to Start") { editor?.seek(to: 0) }.keyboardShortcut(.home, modifiers: [], when: live)
                Divider()
                // J-K-L and I/O, the tape-deck keys every editor shares (#230, docs/conventions.md).
                Button("Play Backward") { editor?.shuttle(-1) }.keyboardShortcut("j", modifiers: [], when: live)
                Button("Stop") { editor?.shuttle(0) }.keyboardShortcut("k", modifiers: [], when: live)
                Button("Play Forward") { editor?.shuttle(1) }.keyboardShortcut("l", modifiers: [], when: live)
                Divider()
                Button("Mark In") { editor?.markInAtPlayhead() }.keyboardShortcut("i", modifiers: [], when: live)
                Button("Mark Out") { editor?.markOutAtPlayhead() }.keyboardShortcut("o", modifiers: [], when: live)
                Button("Clear In and Out") { editor?.clearInOut() }.keyboardShortcut(
                    "x", modifiers: [.option], when: live
                )
                .disabled(editor?.markIn == nil && editor?.markOut == nil)
                Divider()
                // Retimes (#443): a speed for In to Out, and Final Cut's ⇧H Hold at the playhead.
                Menu("Change Speed of In to Out") {
                    ForEach(Retime.editorRates, id: \.self) { rate in
                        Button(Retime.percent(rate)) { editor?.setSpeedOfInOut(rate) }
                    }
                    Divider()
                    Button("Normal Speed") { editor?.setSpeedOfInOut(1) }
                }
                .disabled(editor?.canRetimeInOut != true)
                Button("Hold Frame") { editor?.holdFrameAtPlayhead() }.keyboardShortcut(
                    "h", modifiers: [.shift], when: live
                )
                .disabled(editor == nil || editor?.duration ?? 0 <= 0)
            }
            .disabled(editor == nil)
        }
    }
}
