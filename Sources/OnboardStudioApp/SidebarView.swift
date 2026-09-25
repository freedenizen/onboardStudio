import AppKit
import ProjectModel
import SwiftUI

struct SidebarView: View {
    @Bindable var editor: EditorModel

    var body: some View {
        // The list's own selection (#280): the table does what a Mac list does — a click on empty
        // space selects nothing, ⌘- and ⇧-click extend, the arrow keys move — and the rows are
        // highlighted as the system highlights them.
        List(selection: selection) {
            Section("Inputs") {
                if editor.project.inputs.isEmpty {
                    Text("Add a video and a data file to begin.").foregroundStyle(.secondary).font(.callout)
                }
                ForEach(editor.project.inputs) { input in
                    HStack {
                        Image(
                            systemName: input.kind.isVideo
                                ? "video" : input.kind.isImage ? "photo" : "waveform.path.ecg"
                        )
                        .accessibilityLabel(input.kind.isVideo ? "Video" : input.kind.isImage ? "Image" : "Data")
                        .help(input.kind.isVideo ? "A video" : input.kind.isImage ? "An image" : "A data file")
                        VStack(alignment: .leading) {
                            Text(input.label)
                            Text(inputDetail(input)).font(.caption).foregroundStyle(.secondary)
                        }
                        if editor.problems[input.id] != nil {
                            Spacer()
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                                .help(editor.problems[input.id] ?? "")
                                .accessibilityLabel("Problem: \(editor.problems[input.id] ?? "")")
                        }
                    }
                    .contentShape(Rectangle())
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("input.\(input.label)")
                    .tag(SidebarItem.input(input.id))
                    .contextMenu { Button("Remove", role: .destructive) { editor.removeInput(input.id) } }
                    // A recording the camera split into several files is joined into one input.
                    // Listing the files under the selected row says so without making the user
                    // open the inspector to find out, and without cluttering every other row.
                    if editor.selectedInputID == input.id, editor.selectedObjectID == nil {
                        ForEach(editor.chapters(of: input.id)) { chapter in
                            HStack(spacing: 6) {
                                Image(systemName: "film").foregroundStyle(.secondary).accessibilityHidden(true)
                                Text(chapter.name).lineLimit(1).truncationMode(.middle)
                                Spacer(minLength: 0)
                                Text(EditorModel.clock(chapter.duration)).foregroundStyle(.secondary)
                            }
                            .font(.caption)
                            .padding(.leading, 22)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("chapter.\(chapter.name)")
                            .help(
                                chapter.gapBefore > 0
                                    ? "Starts \(EditorModel.clock(chapter.gapBefore)) after the previous file ends."
                                    : "Continues straight on from the previous file.")
                        }
                    }
                }
            }
            // Markers you cannot enumerate are markers you lose, which is why every editor has a
            // list as well as the marks themselves.
            if !editor.project.markers.isEmpty {
                Section("Markers") {
                    ForEach(editor.markersInProjectTime) { placed in
                        HStack(spacing: 6) {
                            Image(systemName: placed.marker.isRange ? "arrow.left.and.right" : "mappin")
                                .foregroundStyle(Color(placed.marker.colour))
                                .accessibilityLabel(placed.marker.isRange ? "Range" : "Marker")
                                .help(placed.marker.isRange ? "A range marker" : "A marker at one moment")
                            Text(placed.marker.name.isEmpty ? "Marker" : placed.marker.name).lineLimit(1)
                            Spacer(minLength: 0)
                            Text(TimelineRuler.label(placed.start)).font(.caption).monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("markerRow.\(placed.marker.name)")
                        .tag(SidebarItem.marker(placed.marker.id))
                        .contextMenu {
                            Button("Rename…") {
                                editor.selectedMarkerID = placed.marker.id
                                editor.renameSelectedMarker()
                            }
                            Button("Export as Vertical Clip…") { editor.requestClip(of: placed) }
                            Divider()
                            Button("Delete", role: .destructive) { editor.deleteMarker(placed.marker.id) }
                        }
                    }
                }
            }
            Section("Display Objects") {
                ForEach(editor.project.displayObjects.reversed()) { object in
                    HStack {
                        Image(systemName: icon(for: object.kind)).accessibilityLabel(object.kind.typeName)
                            .help(object.kind.typeName)
                        Text(object.label).accessibilityIdentifier("object.\(object.label)")
                        Spacer()
                        if object.groupID != nil {
                            Image(systemName: "link").foregroundStyle(.secondary).font(.caption)
                                .help("In a group: it moves and resizes with the others")
                                .accessibilityLabel("Grouped")
                        }
                        // Always there rather than only on hover: easier to find, and to reach by keyboard.
                        Button {
                            editor.selectObject(object.id)
                            editor.toggleLockSelection()
                        } label: {
                            Image(systemName: object.isLocked ? "lock.fill" : "lock.open")
                                .foregroundStyle(object.isLocked ? Color.primary : Color.secondary.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                        .help(object.isLocked ? "Unlock \(object.label) (⌘L)" : "Lock \(object.label) (⌘L)")
                        .accessibilityLabel(object.isLocked ? "Unlock \(object.label)" : "Lock \(object.label)")
                        .accessibilityIdentifier("object.\(object.label).lock")
                        let visible = editor.resolvedObject(object.id)?.isVisible ?? object.isVisible
                        Button {
                            editor.setOverridable(object.id, name: visible ? "Hide Object" : "Show Object") {
                                $0.isVisible = !visible
                            }
                        } label: {
                            Image(systemName: visible ? "eye" : "eye.slash").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(visible ? "Hide \(object.label)" : "Show \(object.label)")
                        .accessibilityIdentifier("object.\(object.label).visibility")
                        .accessibilityLabel(visible ? "Hide \(object.label)" : "Show \(object.label)")
                    }
                    .contentShape(Rectangle())
                    .tag(SidebarItem.object(object.id))
                    .contextMenu {
                        // On the row clicked, or the whole selection when the row is in it (#277).
                        ForEach(LayerMove.allCases, id: \.self) { move in
                            Button(move.title) {
                                if !editor.selectedObjectIDs.contains(object.id) {
                                    editor.selectObject(object.id, wholeGroup: false)
                                }
                                editor.arrangeSelection(move)
                            }
                        }
                        Divider()
                        Button("Delete", role: .destructive) {
                            editor.selectedObjectID = object.id
                            editor.deleteSelectedObject()
                        }
                    }
                }
                // Drag a row up to bring it forward, down to send it back (#277).
                .onMove { editor.moveObjectsInList($0, to: $1) }
            }
        }
        .listStyle(.sidebar)
        // SwiftUI's list keeps its selection when empty space is clicked; AppKit's clears it, and
        // that is what a Mac user expects of a list.
        .background(EmptyRowClick { editor.deselectAll() })
    }

    /// What a row stands for, so the list can select it.
    enum SidebarItem: Hashable {
        case input(InputID)
        case object(DisplayObjectID)
        case marker(MarkerID)
    }

    /// The editor's selection as the list sees it, and the list's changes back into the editor.
    var selection: Binding<Set<SidebarItem>> {
        Binding(
            get: {
                if !editor.selectedObjectIDs.isEmpty { return Set(editor.selectedObjectIDs.map { .object($0) }) }
                if let marker = editor.selectedMarkerID { return [.marker(marker)] }
                if let input = editor.selectedInputID { return [.input(input)] }
                return []
            },
            set: { select($0) })
    }

    /// Objects win over the rest of a mixed selection, since only they can be edited together;
    /// a sidebar click selects just the object, not its group, which is how one member of a
    /// group is reached to edit it (#90).
    func select(_ items: Set<SidebarItem>) {
        let objects = items.compactMap { item -> DisplayObjectID? in
            if case .object(let id) = item { id } else { nil }
        }
        if let first = objects.first {
            let primary = editor.selectedObjectID.flatMap { objects.contains($0) ? $0 : nil } ?? first
            editor.selectObject(primary, wholeGroup: false)
            editor.additionalSelection = Set(objects).subtracting([primary])
        } else if let marker = items.lazy.compactMap({ item -> MarkerID? in
            if case .marker(let id) = item { id } else { nil }
        }).first,
            let placed = editor.markersInProjectTime.first(where: { $0.marker.id == marker })
        {
            editor.select(marker: marker, seekTo: placed.start)
        } else if let input = items.lazy.compactMap({ item -> InputID? in
            if case .input(let id) = item { id } else { nil }
        }).first {
            editor.deselectAll()
            editor.selectedInputID = input
        } else {
            editor.deselectAll()
        }
    }

    func inputDetail(_ input: Input) -> String {
        switch input.kind {
        case .video:
            if let info = editor.loaded?.mediaInfo[input.id] {
                let size = "\(info.width)×\(info.height), \(Int(info.duration.rounded())) s"
                let chapters = editor.chapters(of: input.id).count
                // Two files going in and one row coming out is surprising unless the row says so.
                return chapters > 1 ? "\(size) · \(chapters) files" : size
            }
            return "video"
        case .data:
            if let session = editor.sessions[input.id] {
                let laps = session.laps.count == 1 ? "1 lap" : "\(session.laps.count) laps"
                return "\(session.info.sourceFormat), \(session.channels.count) channels, \(laps)"
            }
            return "data"
        case .audio: return "audio"
        case .image:
            if let image = editor.loaded?.images[input.id] { return "\(image.width)×\(image.height) image" }
            return "image"
        }
    }

    func icon(for kind: DisplayObjectKind) -> String {
        switch kind {
        case .video: "video"
        case .speedometer, .tachometer, .gauge: "gauge.with.dots.needle.67percent"
        case .trackMap: "map"
        case .gForce: "scope"
        case .timer: "stopwatch"
        case .textData: "textformat.123"
        case .shape: "square.on.circle"
        case .text: "textformat"
        case .image: "photo"
        case .bar: "chart.bar.fill"
        case .graph: "chart.xyaxis.line"
        case .gear: "g.square"
        case .lapCounter: "number.square"
        case .scripted: "curlybraces"
        case .indicator: "exclamationmark.triangle"
        case .lapPanel: "timer"
        case .statCard: "list.bullet.rectangle"
        case .sectorPanel: "chart.bar.doc.horizontal"
        case .steeringWheel: "steeringwheel"
        }
    }
}

/// Calls `action` when a click in the table behind it lands on no row (#280). A local event
/// monitor, so the click itself still goes where it was going.
struct EmptyRowClick: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.action = action
        return view
    }

    func updateNSView(_ view: MonitorView, context: Context) { view.action = action }

    final class MonitorView: NSView {
        var action: (() -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                self?.handle(event)
                return event
            }
        }

        /// Only clicks inside this view, which lies behind the sidebar's list and has its frame,
        /// and only those that land on no row of the table there.
        private func handle(_ event: NSEvent) {
            guard let window, event.window === window,
                convert(bounds, to: nil).contains(event.locationInWindow),
                let hit = window.contentView?.hitTest(event.locationInWindow),
                let table = Self.table(containing: hit)
            else { return }
            if table.row(at: table.convert(event.locationInWindow, from: nil)) == -1 { action?() }
        }

        /// The table the click is in: an ancestor, or the document of an enclosing scroll view
        /// (the empty space below the last row belongs to the scroll view, not the table).
        private static func table(containing view: NSView) -> NSTableView? {
            var current: NSView? = view
            while let candidate = current {
                if let table = candidate as? NSTableView { return table }
                if let scroll = candidate as? NSScrollView { return scroll.documentView as? NSTableView }
                current = candidate.superview
            }
            return nil
        }
    }
}
