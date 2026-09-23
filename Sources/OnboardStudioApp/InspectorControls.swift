import SwiftUI

/// Small controls shared by the inspector panels.

/// A number field that writes to the project once: on Return, when focus leaves it, or one step
/// per press of ↑/↓ (#205, #208).
///
/// `TextField(value:format:)` on its own updates its binding as the digits are typed, so typing
/// 200 was three undo steps — 2, 20, 200 — and three recompiles. This edits a draft instead, like
/// `CommittingTextField`, and Escape abandons it.
struct NumberField: View {
    let title: String
    @Binding var value: Double
    let fractionDigits: ClosedRange<Int>
    let step: Double
    let range: ClosedRange<Double>?

    @State private var draft: Double
    @State private var pending = false
    @FocusState private var focused: Bool

    /// `step` is how far one press of ↑/↓ moves the value. It defaults to 1, which suits the
    /// percentages, degrees and counts most of these fields hold — pass a smaller step for a
    /// field that lives between 0 and 1, where ±1 would be useless.
    init(
        _ title: String, value: Binding<Double>, fractionDigits: ClosedRange<Int> = 0...3,
        step: Double = 1, range: ClosedRange<Double>? = nil
    ) {
        self.title = title
        _value = value
        _draft = State(initialValue: value.wrappedValue)
        self.fractionDigits = fractionDigits
        self.step = step
        self.range = range
    }

    var body: some View {
        TextField(title, value: $draft, format: .number.precision(.fractionLength(fractionDigits)))
            .focused($focused)
            .onSubmit(commit)
            .onChange(of: draft) { _, new in if focused, new != value { pending = true } }
            .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
            .onChange(of: value) { _, new in if !pending { draft = new } }
            .onDisappear(perform: commit)
            // Bare ↑/↓ only. Inside a text field ⇧↑/⇧↓ extend the selection, which is the standard
            // macOS gesture and belongs to the field editor; `onKeyPress(keys:)` does not match a
            // modified key anyway, so they are left alone on purpose rather than by accident.
            .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                adjust(by: press.key == .upArrow ? step : -step)
                return .handled
            }
            .onKeyPress(.escape) {
                guard pending else { return .ignored }
                draft = value
                pending = false
                focused = false
                return .handled
            }
    }

    private func commit() {
        guard pending else { return }
        pending = false
        value = draft
    }

    /// Each press is its own edit, from whatever the field shows — typed or not.
    private func adjust(by amount: Double) {
        let moved = (pending ? draft : value) + amount
        let clamped = range.map { min(max(moved, $0.lowerBound), $0.upperBound) } ?? moved
        pending = false
        draft = clamped
        value = clamped
    }
}

/// A number field that can be empty, meaning "unset" — no trim limit, no fixed bound. Writes on
/// Return or losing focus, as `NumberField` does (#205).
struct OptionalNumberField: View {
    let title: String
    @Binding var value: Double?
    let placeholder: String

    @State private var draft: Double?
    @State private var pending = false
    @FocusState private var focused: Bool

    init(_ title: String, value: Binding<Double?>, placeholder: String) {
        self.title = title
        _value = value
        _draft = State(initialValue: value.wrappedValue)
        self.placeholder = placeholder
    }

    var body: some View {
        TextField(
            title,
            value: $draft,
            format: .number.precision(.fractionLength(0...3)),
            prompt: Text(placeholder)
        )
        .focused($focused)
        .onSubmit(commit)
        .onChange(of: draft) { _, new in if focused, new != value { pending = true } }
        .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
        .onChange(of: value) { _, new in if !pending { draft = new } }
        .onDisappear(perform: commit)
        .onKeyPress(.escape) {
            guard pending else { return .ignored }
            draft = value
            pending = false
            focused = false
            return .handled
        }
    }

    private func commit() {
        guard pending else { return }
        pending = false
        value = draft
    }
}

/// A text field that edits a draft and writes it to the project once: on Return, or when focus
/// leaves the field (#205).
///
/// Bound straight to the model, a `TextField` writes on every key press, and every write is an
/// undo step and a recompile — renaming an object took fourteen undos to take back, and a corner
/// name was trimmed between the word and the space after it. Escape abandons the draft.
///
/// Takes the same `Binding` a `TextField` would, and only calls its setter on commit, so adopting
/// it is a change of type and nothing else.
struct CommittingTextField: View {
    let title: String
    @Binding var text: String
    let prompt: Text?
    let axis: Axis

    @State private var draft = ""
    /// Whether the draft holds typing that has not been written yet. Tracked rather than worked
    /// out by comparing with `text`, because a commit on focus loss and one on disappearing can
    /// both see the value from before the first of them wrote.
    @State private var pending = false
    @FocusState private var focused: Bool

    init(_ title: String, text: Binding<String>, prompt: Text? = nil, axis: Axis = .horizontal) {
        self.title = title
        _text = text
        _draft = State(initialValue: text.wrappedValue)
        self.prompt = prompt
        self.axis = axis
    }

    var body: some View {
        TextField(title, text: $draft, prompt: prompt, axis: axis)
            .focused($focused)
            .onSubmit(commit)
            .onChange(of: draft) { _, new in if focused, new != text { pending = true } }
            .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
            // Escape abandons the edit and ends it, as it does when renaming in the Finder. Ending
            // it matters: while the field is still being edited, ⌘Z belongs to the field and would
            // bring the abandoned typing back.
            .onKeyPress(.escape) {
                guard pending else { return .ignored }
                draft = text
                pending = false
                focused = false
                return .handled
            }
            // Undo, and edits made elsewhere, show in the field while nobody is typing in it.
            .onChange(of: text) { _, new in if !pending { draft = new } }
            // A selection change can take the field away while it is focused; what was typed still
            // belongs to the thing it was typed for.
            .onDisappear(perform: commit)
    }

    private func commit() {
        guard pending else { return }
        pending = false
        text = draft
    }
}
