import ProjectModel
import SwiftUI

/// The one offer for the sessions from before the weather was looked up (#560): fill in their
/// weather, surface and air as one step of Undo, or not. Either answer puts it away for good;
/// Fill In Weather on a session's menu is still there.
struct WeatherOffer: View {
    let count: Int
    let isWorking: Bool
    let fill: () -> Void
    @AppStorage(Preferences.weatherOfferAnswered.key) private var answered = Preferences.weatherOfferAnswered.unset

    var body: some View {
        if !answered, count >= 1 {
            HStack(spacing: 8) {
                Image(systemName: "cloud.sun").foregroundStyle(.secondary).accessibilityHidden(true)
                Text(Self.text(count))
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("logbook.weatherOffer.text")
                Spacer()
                Button("Not Now") { answered = true }
                    .accessibilityIdentifier("logbook.weatherOffer.notNow")
                Button(isWorking ? "Looking Up…" : "Fill In Weather") {
                    answered = true
                    fill()
                }
                .disabled(isWorking)
                .help("Looks up each session's weather from where and when it was driven; what you noted is kept")
                .accessibilityIdentifier("logbook.weatherOffer.fill")
            }
            .padding(.horizontal).padding(.vertical, 8)
            Divider()
        }
    }

    /// "12 sessions have no weather noted. It can be looked up from where and when each was driven."
    static func text(_ count: Int) -> String {
        let sessions = count == 1 ? "1 session has" : "\(count) sessions have"
        return "\(sessions) no weather noted. It can be looked up from where and when "
            + (count == 1 ? "it was driven." : "each was driven.")
    }
}

extension LogbookWindow {
    /// Fill In Weather on the sessions, saying how it went under the table (#560).
    func fillWeather(_ ids: [UUID]) {
        Task { @MainActor in message = await model.fillWeather(ids, undo: undoManager) }
    }

    /// Over the table: the offer for the sessions from before the weather was looked up.
    var weatherOffer: some View {
        let waiting = model.sessionsWithoutWeather
        return WeatherOffer(count: waiting.count, isWorking: model.isLookingUpWeather) {
            fillWeather(waiting.map(\.id))
        }
    }
}
