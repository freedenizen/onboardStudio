import ProjectModel
import SwiftUI
import TelemetryKit

/// The attribute mapping table and the import report, in a window of their own (#192).
///
/// The table has three columns and an inspector can show one. Squeezed into a ~300 pt column each
/// row became three lines, which made a long scroll inside a longer one and got worse as the
/// vocabulary grew. Here the columns are columns, and the window can be left open beside the
/// editor while the preview is checked.
struct AttributeMappingWindow: View {
    @State private var scope: Scope = .global
    @State private var tab: Tab = .attributes

    private var active = ActiveEditor.shared

    /// Which level of the chain is being edited, and for which input.
    enum Scope: Hashable {
        /// The global mapping in Settings — every later import follows it.
        case global
        /// This project's deviations from the global mapping.
        case project
        /// One data input's deviations, for when a file is the exception.
        case input(InputID)
    }

    enum Tab: String, CaseIterable, Identifiable {
        case attributes, report
        var id: String { rawValue }
        var title: String { self == .attributes ? "Attributes" : "Import" }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 720, minHeight: 400)
        // A project closing, or a different one coming forward, must not leave the window editing
        // a level of a project that is no longer there.
        .onChange(of: active.editor?.project.inputs.map(\.id) ?? []) { _, inputs in
            if case .input(let id) = scope, !inputs.contains(id) { scope = .project }
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack {
            Picker("Applies to", selection: $scope) {
                Text("All projects").tag(Scope.global)
                if active.editor != nil {
                    Text("This project").tag(Scope.project)
                    Divider()
                    ForEach(dataInputs, id: \.id) { input in
                        Text(input.label).tag(Scope.input(input.id))
                    }
                }
            }
            .frame(maxWidth: 320)
            .accessibilityIdentifier("attributes.scope")
            Spacer()
            if active.editor != nil {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 220)
                .accessibilityIdentifier("attributes.tab")
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private var content: some View {
        if tab == .report, let session = selectedSession {
            ImportReportTable(report: session.importReport)
        } else {
            AttributeMappingGrid(scope: scope, editor: active.editor)
        }
    }

    private var dataInputs: [Input] { active.editor?.project.dataInputs ?? [] }

    /// The session the report describes: the selected input's, or the first one when the scope is
    /// the project or the global mapping and there is nothing more specific to show.
    private var selectedSession: TelemetrySession? {
        guard let editor = active.editor else { return nil }
        if case .input(let id) = scope { return editor.sessions[id] }
        return editor.project.dataInputs.first.flatMap { editor.sessions[$0.id] }
    }
}

/// A button that opens the window, for the places that used to hold the table itself.
struct OpenAttributeWindowButton: View {
    let title: String
    /// Distinct per place, because more than one of these can share an inspector and a query for
    /// "the button that opens the window" would then match several.
    let identifier: String
    @Environment(\.openWindow) private var openWindow

    init(_ title: String = "Map Attributes…", identifier: String = "attributes.open") {
        self.title = title
        self.identifier = identifier
    }

    var body: some View {
        Button(title) { openWindow(id: AttributeMappingWindow.windowID) }
            .accessibilityIdentifier(identifier)
    }
}

extension AttributeMappingWindow {
    static let windowID = "attributes"
}
