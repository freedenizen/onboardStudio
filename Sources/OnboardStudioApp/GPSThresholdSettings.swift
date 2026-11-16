import ProjectModel
import SwiftUI
import TelemetryKit

/// Settings ▸ GPS Quality (#555): the thresholds a session's positions are rated Good, Fair or
/// Poor against, in the import report and the Logbook. Changing one re-rates every session at
/// once; nothing is read again.
struct GPSThresholdSettings: View {
    @AppStorage(Preferences.gpsThresholds.key) private var text = Preferences.gpsThresholds.unset

    private var options: GPSQuality.Options { GPSQuality.Options(preferenceText: text) }

    var body: some View {
        Section {
            row("Positions a second", good: ("good from", \.goodRateHertz), poor: ("poor below", \.poorRateHertz))
            row("Dropout", poor: ("poor from", \.poorDropoutSeconds), unit: "s")
            row("Jumps", poor: ("poor from", \.poorJumpCount))
            row(
                "Logged accuracy", good: ("good within", \.goodAccuracyMeters),
                poor: ("poor beyond", \.poorAccuracyMeters), unit: "m")
            row("HDOP", good: ("good up to", \.goodHDOP), poor: ("poor above", \.poorHDOP))
            row("Satellites", good: ("good from", \.goodSatellites), poor: ("poor below", \.poorSatellites))
            Button("Restore Default Thresholds") { text = Preferences.gpsThresholds.unset }
                .disabled(text.isEmpty)
                .accessibilityIdentifier("settings.gps.restore")
        } header: {
            Text("GPS Quality")
        } footer: {
            Text(
                "How a session's positions are rated in the import report and the Logbook. Between good and "
                    + "poor is fair; a lap about twice the usual length is always fair."
            )
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    private typealias Threshold = (words: String, path: WritableKeyPath<GPSQuality.Options, Double>)

    private func row(_ title: String, good: Threshold? = nil, poor: Threshold, unit: String? = nil) -> some View {
        LabeledContent(title) {
            HStack(spacing: 14) {
                if let good { field(title, good, unit: unit) }
                field(title, poor, unit: unit)
            }
        }
    }

    private func field(_ title: String, _ threshold: Threshold, unit: String?) -> some View {
        HStack(spacing: 4) {
            Text(threshold.words).foregroundStyle(.secondary)
            TextField(
                "\(title), \(threshold.words)", value: binding(threshold.path),
                format: .number.precision(.fractionLength(0...1))
            )
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .frame(width: 44)
            .accessibilityLabel("\(title), \(threshold.words)")
            .accessibilityIdentifier(
                "settings.gps.\(GPSQuality.Options.editable.first { $0.path == threshold.path }?.name ?? "")")
            if let unit { Text(unit).foregroundStyle(.secondary) }
        }
    }

    private func binding(_ path: WritableKeyPath<GPSQuality.Options, Double>) -> Binding<Double> {
        Binding(
            get: { options[keyPath: path] },
            set: { value in
                var changed = options
                changed[keyPath: path] = max(0, value)
                text = changed.preferenceText
            })
    }
}
