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
                        Image(systemName: input.kind.isVideo ? "video" : "waveform.path.ecg")
                        VStack(alignment: .leading) {
                            Text(input.label)
                            Text(inputDetail(input)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        editor.selectedInputID = input.id
                        editor.selectedObjectID = nil
                    }
                    .listRowBackground(
                        editor.selectedInputID == input.id && editor.selectedObjectID == nil
                            ? Color.accentColor.opacity(0.2) : nil
                    )
                    .contextMenu { Button("Remove", role: .destructive) { editor.removeInput(input.id) } }
                }
            }
            Section("Display Objects") {
                ForEach(editor.project.displayObjects.reversed()) { object in
                    HStack {
                        Image(systemName: icon(for: object.kind))
                        Text(object.label)
                        Spacer()
                        Button {
                            editor.updateObject(object.id, name: object.isVisible ? "Hide Object" : "Show Object") {
                                $0.isVisible.toggle()
                            }
                        } label: {
                            Image(systemName: object.isVisible ? "eye" : "eye.slash").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { editor.selectedObjectID = object.id }
                    .listRowBackground(editor.selectedObjectID == object.id ? Color.accentColor.opacity(0.2) : nil)
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
                return "\(info.width)×\(info.height), \(Int(info.duration.rounded())) s"
            }
            return "video"
        case .data:
            if let session = editor.sessions[input.id] {
                return "\(session.info.sourceFormat), \(session.channels.count) channels, \(session.laps.count) laps"
            }
            return "data"
        case .audio: return "audio"
        case .image: return "image"
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
        }
    }
}
