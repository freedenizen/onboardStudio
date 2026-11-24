import ProjectModel
import SwiftUI

/// Brings the Logbook window back where it was (#701): what the sidebar had chosen, the view and
/// the sessions selected, kept in the preferences as they change and put back when the window
/// opens — at launch, and when it is closed and opened again. The window used to open on All
/// Sessions with nothing selected every time. It does not depend on macOS bringing windows back
/// (System Settings ▸ Desktop & Dock ▸ Close windows when quitting an application), which is
/// what decides whether the projects that were open return.
struct LogbookPlaceKeeper: View {
    @Binding private var scope: LogbookScope
    @Binding private var view: LogbookWindow.LogbookView
    @Binding private var selection: Set<UUID>
    /// Under the UI tests a store of their own, emptied at launch, as the panes' widths are.
    @AppStorage("logbook.place", store: UITestSupport.paneDefaults) private var kept = ""
    /// Nothing is written down before the place kept has been read, or the window's first
    /// moment — All Sessions, nothing selected — would be what is kept.
    @State private var restored = false
    private var model = LogbookModel.shared

    init(scope: Binding<LogbookScope>, view: Binding<LogbookWindow.LogbookView>, selection: Binding<Set<UUID>>) {
        _scope = scope
        _view = view
        _selection = selection
    }

    var body: some View {
        Color.clear.frame(width: 0, height: 0).accessibilityHidden(true)
            // Once the logbook has been read: before that there is no session to select and no
            // day to find, and the place kept would be thrown away as gone.
            .onChange(of: model.hasLoaded, initial: true) { if model.hasLoaded { restore() } }
            .onChange(of: place) { if restored { kept = place.storageValue } }
    }

    private var place: LogbookPlace {
        LogbookPlace(scope: scope, view: view.rawValue, selection: selection.sorted { $0.uuidString < $1.uuidString })
    }

    private func restore() {
        guard !restored else { return }
        restored = true
        // Something has sent the window somewhere already — an import report's Show Trends: it
        // stands, and is what is kept from here on.
        guard place == .start, let stored = LogbookPlace(storageValue: kept) else { return }
        let found = stored.resolved(in: model.entries, days: model.days, cars: model.cars)
        scope = found.scope
        view = LogbookWindow.LogbookView(rawValue: found.view) ?? .sessions
        selection = Set(found.selection)
    }
}
