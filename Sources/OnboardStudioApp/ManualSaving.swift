import AppKit
import ObjectiveC

/// Projects are saved when the user saves them, and not before.
///
/// SwiftUI's `DocumentGroup` autosaves in place: every edit is written into the project file a
/// few seconds later, so there is no way to try something and walk away from it. AppKit's other
/// mode keeps the edits in a separate autosave file — enough to bring them back after a crash —
/// and leaves the project file as it was last saved until **File ▸ Save**; closing a window with
/// changes asks whether to save them. `DocumentGroup` offers no switch for it, so the document
/// classes SwiftUI registers are told to answer `autosavesInPlace` with `false` (#300).
enum ManualSaving {
    /// Idempotent. Call as soon as the document classes are registered, before any document opens.
    @MainActor
    static func install() {
        // Out of place, AppKit autosaves only on a timer, and the timer is off until given a period.
        if NSDocumentController.shared.autosavingDelay == 0 { NSDocumentController.shared.autosavingDelay = 5 }
        for name in NSDocumentController.shared.documentClassNames {
            // The registered class is generated at run time; the documents report SwiftUI's own
            // class above it, and AppKit asks one or the other depending on the path, so every
            // class up to NSDocument has to give the same answer.
            var current: AnyClass? = NSClassFromString(name)
            while let documentClass = current, documentClass != NSDocument.self {
                if let metaclass = object_getClass(documentClass) {
                    let answer: @convention(block) (AnyObject) -> Bool = { _ in false }
                    class_replaceMethod(
                        metaclass, #selector(getter: NSDocument.autosavesInPlace), imp_implementationWithBlock(answer),
                        "B@:")
                }
                current = class_getSuperclass(documentClass)
            }
        }
    }
}
