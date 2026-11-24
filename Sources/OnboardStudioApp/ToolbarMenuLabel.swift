import SwiftUI

extension Label where Title == Text, Icon == ModifiedContent<Image, AccessibilityAttachmentModifier> {
    /// The label of a toolbar `Menu`, with its symbol named for what the menu does.
    ///
    /// A toolbar menu is read by its symbol unless the menu has its own `.accessibilityLabel`
    /// (#153). That gives the menu its accessibility label, and holds; but once SwiftUI has
    /// updated the menu, the control it rebuilds has an accessibility *title* as well, taken from
    /// the image. So Export or Import was also "Share" once a first import had refreshed the
    /// Logbook's toolbar, and New Project also "doc.badge.plus" once a session was chosen (#691):
    /// two names, and which one is read depends on the tool. Named itself, the image gives the
    /// rebuilt control the same title as its label.
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
