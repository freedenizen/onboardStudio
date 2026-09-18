import ProjectModel
import Scripting
import SwiftUI

/// Edits a scripted object's JavaScript with live checking and ready-made examples.
struct ScriptInspector: View {
    @Bindable var editor: EditorModel
    let object: DisplayObject
    let params: ScriptedParams
    @State private var draft = ""
    @State private var problem: ScriptEngine.Problem?

    var body: some View {
        Section("Script") {
            TextEditor(text: $draft)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 260)
                .onChange(of: draft) { _, source in check(source) }
            if let problem {
                Label(
                    problem.line.map { "Line \($0): \(problem.message)" } ?? problem.message,
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.yellow).font(.callout)
            } else {
                Label("Script compiles.", systemImage: "checkmark.circle").foregroundStyle(.secondary).font(.callout)
            }
            HStack {
                Button("Apply") { apply() }.disabled(draft == params.source)
                Button("Revert") { draft = params.source }.disabled(draft == params.source)
                Spacer()
                Menu("Examples") {
                    ForEach(ScriptExamples.all) { example in
                        Button(example.name) { draft = example.source }
                    }
                }
            }
            Text(
                "Define background(canvas) for static drawing and frame(canvas, data) for every frame. "
                    + "canvas: fill/stroke/rect/roundRect/circle/line/polygon/arc/text/gradientRect; "
                    + "data: value(id), speed(unit), valueAgo(id, s), range(id), lap, laps, time. "
                    + "See docs/scripting.md."
            )
            .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear {
            draft = params.source
            check(draft)
        }
        .onChange(of: params.source) { _, source in
            if draft != source, draft.isEmpty { draft = source }
        }
    }

    func check(_ source: String) {
        problem = ScriptEngine.check(source)
    }

    func apply() {
        var new = params
        new.source = draft
        editor.updateObject(object.id, name: "Edit Script") { $0.kind = .scripted(new) }
    }
}
