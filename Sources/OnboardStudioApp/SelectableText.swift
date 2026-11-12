import SwiftUI

/// Words the user can select and copy, read by VoiceOver as they are now.
///
/// On macOS 27 a `Text` with `.textSelection(.enabled)` goes on telling accessibility the words it
/// was first given after they change on screen: the status line read "Put the playhead inside
/// test-3s to split it." to VoiceOver while it showed "Split test-3s at the playhead." (#509). So
/// each new string is a new view, and accessibility is given the new one.
struct SelectableText: View {
    let string: String

    init(_ string: String) { self.string = string }

    var body: some View {
        Text(string).textSelection(.enabled).id(string)
    }
}
