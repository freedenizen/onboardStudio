import ProjectModel
import SwiftUI

struct SidebarView: View {
    @Bindable var editor: EditorModel

    var body: some View {
        List {
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
                    .onTapGesture {
                        editor.selectedInputID = input.id
                        editor.selectedObjectID = nil
                        editor.selectedSegmentID = nil
                        editor.selectedMarkerID = nil
                    }
                    .listRowBackground(
                        editor.selectedInputID == input.id && editor.selectedObjectID == nil
                            ? Color.accentColor.opacity(0.2) : nil
                    )
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
                        .onTapGesture { editor.select(marker: placed.marker.id, seekTo: placed.start) }
                        .listRowBackground(
                            editor.selectedMarkerID == placed.marker.id ? Color.accentColor.opacity(0.2) : nil
                        )
                        .contextMenu {
                            Button("Rename…") {
                                editor.selectedMarkerID = placed.marker.id
                                editor.renameSelectedMarker()
                            }
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
                    .onTapGesture {
                        // ⌘ or ⇧ adds to the selection, as in the Finder's lists (#90).
                        let extending = !NSEvent.modifierFlags.isDisjoint(with: [.command, .shift])
                        editor.selectObject(object.id, extending: extending, wholeGroup: false)
                    }
                    .listRowBackground(
                        editor.selectedObjectIDs.contains(object.id) ? Color.accentColor.opacity(0.2) : nil
                    )
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            editor.selectedObjectID = object.id
                            editor.deleteSelectedObject()
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
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
        case .sectorPanel: "chart.bar.doc.horizontal"
        case .steeringWheel: "steeringwheel"
        }
    }
}
