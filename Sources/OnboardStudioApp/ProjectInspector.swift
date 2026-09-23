import ProjectModel
import SwiftUI

// MARK: - Project

struct ProjectInspector: View {
    @Bindable var editor: EditorModel

    var body: some View {
        Section("Output") {
            Picker("Size", selection: sizeBinding) {
                ForEach(sizeOptions, id: \.self) { option in
                    Text(option.replacingOccurrences(of: "x", with: " × ")).tag(option)
                }
            }
            Picker("Frame rate", selection: frameRateBinding) {
                Text("24").tag(24.0)
                Text("25").tag(25.0)
                Text("30").tag(30.0)
                Text("50").tag(50.0)
                Text("60").tag(60.0)
            }
        }
        ProjectDetailsSection(editor: editor)
        OverlayOpacitySection(editor: editor)
        ProjectFontSection(editor: editor)
        CameraFramingSection(editor: editor)
        GettingStartedSection(editor: editor)
        Section {
            Text(
                "Select an input or a display object to edit it. Drag objects on the preview to move them; "
                    + "drag their handles to resize (⇧ keeps the aspect ratio)."
            )
            .font(.callout).foregroundStyle(.secondary)
        }
    }

    var sizeOptions: [String] {
        let presets = ["1280x720", "1920x1080", "2560x1440", "3840x2160"]
        let current = "\(editor.project.settings.outputWidth)x\(editor.project.settings.outputHeight)"
        return presets.contains(current) ? presets : [current] + presets
    }

    var sizeBinding: Binding<String> {
        Binding(
            get: { "\(editor.project.settings.outputWidth)x\(editor.project.settings.outputHeight)" },
            set: { value in
                let parts = value.split(separator: "x").compactMap { Int($0) }
                guard parts.count == 2 else { return }
                editor.edit("Change Output Size") {
                    $0.settings.outputWidth = parts[0]
                    $0.settings.outputHeight = parts[1]
                    $0.export.width = parts[0]
                    $0.export.height = parts[1]
                }
            })
    }

    var frameRateBinding: Binding<Double> {
        Binding(
            get: { editor.project.settings.frameRate },
            set: { value in
                editor.edit("Change Frame Rate") {
                    $0.settings.frameRate = value
                    $0.export.frameRate = value
                }
            })
    }
}
