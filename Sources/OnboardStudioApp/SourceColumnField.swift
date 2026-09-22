import SwiftUI

/// Chooses the column an attribute is read from (#195).
///
/// A field you can type into, with a menu beside it that filters as you type. A flat pop-up of
/// every column was the obvious control and the wrong one: the reference session has 43 columns
/// and the reference VBOX file 35, so the one being looked for is somewhere in the middle of a
/// list of `analog_1` and `x_rate_of_rotation`. Worse, such a menu scrolls, and what scrolls out
/// is not in the accessibility tree at all — it could not even be selected by name.
///
/// Typing also handles the case a pop-up cannot: naming a column of a file that is not open,
/// which is exactly what setting a global mapping means.
struct SourceColumnField: View {
    /// The column pinned at this level, or `nil` for automatic.
    let pinned: String?
    /// The column the importer matched, shown as what automatic amounts to.
    let detected: String?
    /// Every column the file in view offers.
    let columns: [String]
    let identifier: String
    let write: (String?) -> Void

    @State private var text: String = ""
    @FocusState private var focused: Bool

    /// Columns the typed text narrows to. Matching anywhere, not just at the start: a user looking
    /// for brake pressure types "brake", and the column is called `canbus:front_brake_pressure`.
    private var matches: [String] {
        guard !text.isEmpty else { return columns }
        return columns.filter { $0.localizedCaseInsensitiveContains(text) }
    }

    var body: some View {
        HStack(spacing: 2) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { commit() }
                .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
                .accessibilityIdentifier(identifier)
            Menu {
                Button("Automatic") { set(nil) }
                if !matches.isEmpty { Divider() }
                ForEach(matches.prefix(40), id: \.self) { column in
                    Button(column) { set(column) }
                }
            } label: {
                Image(systemName: "chevron.down")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityIdentifier("\(identifier).menu")
        }
        .onAppear { text = pinned ?? "" }
        .onChange(of: pinned) { _, new in if !focused { text = new ?? "" } }
    }

    /// What automatic amounts to, so a field nobody has filled in still says where the numbers
    /// come from (#196).
    private var placeholder: String {
        detected.map { "Automatic (\($0))" } ?? "Automatic"
    }

    private func set(_ column: String?) {
        text = column ?? ""
        write(column)
    }

    /// Committed on submit or on losing focus rather than per keystroke, so typing a column name
    /// is one undoable edit instead of twenty.
    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed != (pinned ?? "") else { return }
        write(trimmed.isEmpty ? nil : trimmed)
    }
}
