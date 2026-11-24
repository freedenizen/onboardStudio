import SwiftUI

extension Label where Title == Text, Icon == ModifiedContent<Image, AccessibilityAttachmentModifier> {
    /// The label of a toolbar `Menu`, with its symbol named for what the menu does.
    ///
    /// A toolbar menu is read by its symbol unless the menu has its own `.accessibilityLabel`
    /// (#153), and that lasts only until SwiftUI next updates the menu: the control it rebuilds
    /// takes its name from the image again. So Export or Import became "Share" once a first
    /// import had refreshed the Logbook's toolbar, and New Project "doc.badge.plus" once a session
    /// was chosen (#691). The image's own label survives the rebuild.
    ///
    /// `name` is for a menu whose title is too short to stand alone when read aloud ("Speed").
    init(toolbarMenu title: LocalizedStringKey, systemImage: String, named name: LocalizedStringKey? = nil) {
        self.init {
            Text(title)
        } icon: {
            Image(systemName: systemImage).accessibilityLabel(name ?? title)
        }
    }
}
