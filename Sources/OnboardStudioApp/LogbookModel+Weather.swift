import Foundation
import ProjectModel
import TelemetryKit

// MARK: - The weather, looked up (#560)

/// The app's one request for analysis: the hourly weather for a session's place and time, from
/// Open-Meteo. Under UI tests nothing is sent; a fixed sunny, dry, 21.5 °C answer comes back.
enum WeatherService {
    enum Failure: Error { case answer(Int) }

    static let testReading = WeatherLookup.Reading(airCelsius: 21.5, weather: .sunny, track: .dry)

    static func reading(for request: WeatherLookup.Request) async throws -> WeatherLookup.Reading {
        if UITestSupport.isActive { return testReading }
        let (data, response) = try await URLSession.shared.data(
            for: URLRequest(url: request.url(), timeoutInterval: 20))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Failure.answer(status) }
        return WeatherLookup.reading(of: try WeatherLookup.parse(data), for: request)
    }
}

extension LogbookModel {
    /// After every reload: the sessions added since the lookup began, not looked up yet, when
    /// Settings says so. Bookkeeping, as entering the session was: no step of Undo of its own.
    func lookUpNewWeather() {
        let defaults = UserDefaults.standard
        guard defaults.value(for: Preferences.weatherSince) > 0 else {
            // The first run of a build that looks the weather up: what is already here is offered.
            defaults.set(Date().timeIntervalSince1970, for: Preferences.weatherSince)
            return
        }
        guard defaults.value(for: Preferences.lookUpWeather) else { return }
        let since = Date(timeIntervalSince1970: defaults.value(for: Preferences.weatherSince))
        let due = entries.filter {
            $0.added >= since && $0.weatherLookedUp == nil && $0.date != nil && !weatherAttempted.contains($0.id)
        }
        guard !due.isEmpty else { return }
        weatherAttempted.formUnion(due.map(\.id))
        Task { @MainActor in
            var changed = false
            for entry in due {
                guard let reading = await weather(for: entry) else { continue }
                changed = save(reading, to: entry.id) || changed
            }
            if changed { reload() }
        }
    }

    /// The sessions from before the lookup began whose weather, surface or air is empty: what the
    /// one offer is for.
    var sessionsWithoutWeather: [LogbookEntry] {
        let since = Date(timeIntervalSince1970: UserDefaults.standard.value(for: Preferences.weatherSince))
        return entries.filter { $0.added < since && $0.date != nil && $0.conditions.lacksWeather }
    }

    /// Fill In Weather: the sessions' empty weather, surface and air from the record, as one step
    /// of Undo; says how it went.
    func fillWeather(_ ids: [UUID], undo: UndoManager?) async -> String {
        let chosen = entries.filter { ids.contains($0.id) && $0.date != nil }
        guard !chosen.isEmpty else { return "No session there says when it was driven." }
        isLookingUpWeather = true
        defer { isLookingUpWeather = false }
        var readings: [UUID: WeatherLookup.Reading] = [:]
        for entry in chosen {
            if let reading = await weather(for: entry) { readings[entry.id] = reading }
        }
        guard !readings.isEmpty else {
            return "The weather could not be looked up. Check the connection and try again."
        }
        var filled = 0
        edit("Fill In Weather", undo: undo) { logbook in
            for (id, reading) in readings {
                guard var entry = logbook.entry(id: id) else { continue }
                if entry.conditions.fill(from: reading) { filled += 1 }
                entry.weatherLookedUp = Date()
                try logbook.save(entry)
            }
        }
        let missed = chosen.count - readings.count
        var words = "Filled in the weather of \(filled) session\(filled == 1 ? "" : "s")"
        if filled < readings.count { words += "; the rest already had it noted" }
        if missed > 0 { words += "; \(missed) could not be looked up" }
        return words + ". " + WeatherLookup.credit + "."
    }

    /// What the record says of `entry`, or `nil` when its place or time is not known or the
    /// request failed.
    private func weather(for entry: LogbookEntry) async -> WeatherLookup.Reading? {
        guard let date = entry.date else { return nil }
        var place = WeatherLookup.place(of: entry)
        if place == nil, let session = await session(for: entry), let latitude = session[.latitude],
            let longitude = session[.longitude],
            let index = latitude.values.indices.first(where: {
                latitude.values[$0].isFinite && longitude.values.indices.contains($0)
                    && longitude.values[$0].isFinite
            })
        {
            place = (latitude.values[index], longitude.values[index])
        }
        guard let place else { return nil }
        let request = WeatherLookup.Request(
            latitude: place.latitude, longitude: place.longitude, start: date, duration: entry.durationSeconds)
        return try? await WeatherService.reading(for: request)
    }

    /// Fills the entry's empty fields and notes when it was looked up. Whether anything was written.
    private func save(_ reading: WeatherLookup.Reading, to id: UUID) -> Bool {
        let logbook = AppLogbook.shared
        guard var entry = logbook.entry(id: id) else { return false }
        entry.conditions.fill(from: reading)
        entry.weatherLookedUp = Date()
        return (try? logbook.save(entry)) != nil
    }
}
