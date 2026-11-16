import Foundation
import TelemetryKit

extension Preferences {
    /// The thresholds GPS quality is rated against (#555), as `GPSQuality.Options.preferenceText`;
    /// empty for the defaults.
    public static let gpsThresholds = Preference(key: "gpsThresholds", unset: "")
}

extension GPSQuality.Options {
    /// The thresholds a driver can change in Settings, by the name each is kept under. Detection —
    /// what counts as a dropout or a jump at all — stays the app's.
    public static var editable: [(name: String, path: WritableKeyPath<GPSQuality.Options, Double>)] {
        [
            ("goodRateHertz", \.goodRateHertz), ("poorRateHertz", \.poorRateHertz),
            ("poorDropoutSeconds", \.poorDropoutSeconds), ("poorJumpCount", \.poorJumpCount),
            ("goodAccuracyMeters", \.goodAccuracyMeters), ("poorAccuracyMeters", \.poorAccuracyMeters),
            ("goodHDOP", \.goodHDOP), ("poorHDOP", \.poorHDOP),
            ("goodSatellites", \.goodSatellites), ("poorSatellites", \.poorSatellites),
        ]
    }

    /// The thresholds kept as text: the ones changed from the defaults, as JSON. Unreadable or
    /// empty text is the defaults.
    public init(preferenceText: String) {
        self.init()
        guard let data = preferenceText.data(using: .utf8),
            let values = try? JSONDecoder().decode([String: Double].self, from: data)
        else { return }
        for (name, path) in Self.editable {
            if let value = values[name], value.isFinite, value >= 0 { self[keyPath: path] = value }
        }
    }

    /// Empty when every threshold is its default, so a later build's better default reaches it.
    public var preferenceText: String {
        let defaults = GPSQuality.Options()
        var changed: [String: Double] = [:]
        for (name, path) in Self.editable where self[keyPath: path] != defaults[keyPath: path] {
            changed[name] = self[keyPath: path]
        }
        guard !changed.isEmpty else { return "" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(changed)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    /// The thresholds Settings holds now.
    public static var app: GPSQuality.Options {
        GPSQuality.Options(preferenceText: UserDefaults.standard.value(for: Preferences.gpsThresholds))
    }
}
