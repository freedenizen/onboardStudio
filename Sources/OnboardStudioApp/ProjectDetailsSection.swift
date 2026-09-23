import ProjectModel
import SwiftUI

/// What the project is of — track, car, driver, day, and anything the owner adds (#74) — for text
/// objects to show by name.
struct ProjectDetailsSection: View {
    @Bindable var editor: EditorModel
    @State private var addingDetail = false
    @State private var newDetailName = ""

    var details: ProjectDetails { editor.project.details }

    var body: some View {
        Section("Details") {
            field("Track", \.track)
            field("Car", \.car)
            field("Driver", \.driver)
            field("Event", \.event)
            field("Session", \.session)
            dateRow
            ForEach(details.extras) { extra in
                HStack {
                    CommittingTextField(extra.name, text: extraBinding(extra))
                        .accessibilityIdentifier("details.extra.\(extra.name)")
                    Button {
                        editor.setDetail("Remove Detail") { $0.extras.removeAll { $0.id == extra.id } }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove \(extra.name)")
                    .accessibilityLabel("Remove \(extra.name)")
                }
            }
            HStack {
                Button("Add Detail…") {
                    newDetailName = ""
                    addingDetail = true
                }
                .popover(isPresented: $addingDetail, arrowEdge: .bottom) { addDetailPopover }
                Spacer()
                Button("Fill In from Data") { editor.fillDetailsFromData() }
                    .disabled(editor.project.dataInputs.isEmpty)
                    .help("Fill the blank details from what the data files say about themselves")
            }
            Text("Show any of these in a Text object by typing its name in braces: {track} · {date}.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    func field(_ title: String, _ keyPath: WritableKeyPath<ProjectDetails, String>) -> some View {
        CommittingTextField(
            title,
            text: Binding(
                get: { details[keyPath: keyPath] },
                set: { value in editor.setDetail("Change \(title)") { $0[keyPath: keyPath] = value } })
        )
        .accessibilityIdentifier("details.\(title.lowercased())")
    }

    /// A date picker once there is a day, and a way to set one until then: a picker cannot show
    /// "no date", and a project whose data never said when it was recorded has none.
    @ViewBuilder var dateRow: some View {
        if let day = ProjectDetails.day(details.date) {
            HStack {
                DatePicker(
                    "Date",
                    selection: Binding(
                        get: { day },
                        set: { value in editor.setDetail("Change Date") { $0.date = ProjectDetails.iso(value) } }),
                    displayedComponents: .date)
                Button {
                    editor.setDetail("Clear Date") { $0.date = "" }
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .help("Clear the date")
                .accessibilityLabel("Clear Date")
            }
        } else {
            LabeledContent("Date") {
                Button("Set Date") {
                    editor.setDetail("Change Date") { $0.date = ProjectDetails.iso(Date()) }
                }
            }
        }
    }

    func extraBinding(_ extra: ProjectDetail) -> Binding<String> {
        Binding(
            get: { details.extras.first { $0.id == extra.id }?.value ?? "" },
            set: { value in
                editor.setDetail("Change \(extra.name)") { details in
                    guard let index = details.extras.firstIndex(where: { $0.id == extra.id }) else { return }
                    details.extras[index].value = value
                }
            })
    }

    var addDetailPopover: some View {
        Form {
            TextField("Name", text: $newDetailName, prompt: Text("Tyres"))
                .onSubmit(addNewDetail)
            if let problem = problem(with: trimmedNewName) {
                Text(problem).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { addingDetail = false }
                    .keyboardShortcut(.cancelAction)
                Button("Add", action: addNewDetail)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedNewName.isEmpty || problem(with: trimmedNewName) != nil)
            }
        }
        .padding()
        .frame(width: 260)
    }

    var trimmedNewName: String { newDetailName.trimmingCharacters(in: .whitespaces) }

    /// Why `name` cannot be a new detail's, or `nil` when it can.
    func problem(with name: String) -> String? {
        if name.contains("{") || name.contains("}") { return "A name cannot contain braces." }
        let taken =
            ProjectDetails.coreKeys.contains(name.lowercased())
            || details.extras.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        return taken ? "The project already has a detail called \(name)." : nil
    }

    /// Reads the name as it is now rather than as it was when the view last drew: Return can
    /// arrive before the redraw for the last letter typed.
    func addNewDetail() {
        let name = trimmedNewName
        guard !name.isEmpty, problem(with: name) == nil else { return }
        editor.setDetail("Add Detail") { $0.extras.append(ProjectDetail(name: name)) }
        addingDetail = false
    }
}

/// Puts `{track}` and the like into a text object without the user having to know the braces
/// (#74). Each item says what it currently stands for, so the menu doubles as a preview.
struct InsertDetailMenu: View {
    let details: ProjectDetails
    let insert: (String) -> Void

    var body: some View {
        Menu("Insert Detail") {
            ForEach(ProjectDetails.coreKeys, id: \.self) { key in item(key, title: key.capitalized) }
            if !details.extras.isEmpty {
                Divider()
                ForEach(details.extras) { item($0.name, title: $0.name) }
            }
        }
        .accessibilityIdentifier("text.insertDetail")
        .help("Add a project detail to the text; it shows whatever the project's Details say")
    }

    func item(_ key: String, title: String) -> some View {
        let value = details.value(for: key).map { " (\($0))" } ?? ""
        return Button("\(title)\(value)") { insert("{\(key)}") }
    }
}
