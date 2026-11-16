import ProjectModel
import SwiftUI
import TelemetryKit

extension GPSQuality.Rating {
    /// A seal for good data, a warning for fair, a stop for poor: the shape says it as well as the
    /// colour, for a driver who cannot tell green from red.
    var symbol: String {
        switch self {
        case .good: "checkmark.seal"
        case .fair: "exclamationmark.triangle"
        case .poor: "exclamationmark.octagon"
        }
    }

    var tint: Color {
        switch self {
        case .good: .green
        case .fair: .yellow
        case .poor: .red
        }
    }
}

extension CoachingUnits {
    /// The units the app's Speed setting implies, for sentences read outside a project.
    static var app: CoachingUnits {
        let setting = SpeedUnitSetting(rawValue: UserDefaults.standard.value(for: Preferences.speedUnit))
        return .following(setting ?? .automatic)
    }
}

/// How far a session's positions can be trusted (#555): the rating, what was measured, and
/// everything that counts against it.
struct GPSQualityView: View {
    /// As measured; rated here against the thresholds in Settings, so changing one shows at once.
    let measured: GPSQuality
    var units: CoachingUnits = .app
    @AppStorage(Preferences.gpsThresholds.key) private var thresholds = Preferences.gpsThresholds.unset

    private var quality: GPSQuality { measured.rated(with: GPSQuality.Options(preferenceText: thresholds)) }

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("GPS: \(quality.rating.title)").font(.headline)
                Text(quality.measurements(units: units))
                    .font(.callout).foregroundStyle(.secondary)
                ForEach(quality.messages(units: units), id: \.self) { message in
                    Text(message).font(.callout)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: quality.rating.symbol)
                .foregroundStyle(quality.rating.tint)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityIdentifier("gps.quality")
    }

    /// The rating, what was measured and what counts against it, read as one passage.
    private var spoken: String {
        (["GPS: \(quality.rating.title)", quality.measurements(units: units)] + quality.messages(units: units))
            .joined(separator: ". ")
    }
}

/// The GPS column of the Logbook's table (#555): the rating's symbol, with what counts against
/// it in the help tag.
struct GPSRatingBadge: View {
    let entry: LogbookEntry
    @AppStorage(Preferences.gpsThresholds.key) private var thresholds = Preferences.gpsThresholds.unset

    var body: some View {
        if let gps = entry.gps?.rated(with: GPSQuality.Options(preferenceText: thresholds)) {
            Image(systemName: gps.rating.symbol)
                .foregroundStyle(gps.rating == .good ? AnyShapeStyle(.secondary) : AnyShapeStyle(gps.rating.tint))
                .help(Self.help(gps))
                .accessibilityLabel("GPS \(gps.rating.title)")
        } else if entry.needsGPSReading {
            Text("—").foregroundStyle(.tertiary)
                .help("Not judged yet: select the session and its file is read")
                .accessibilityLabel("GPS not judged yet")
        }
    }

    static func help(_ gps: GPSQuality, units: CoachingUnits = .app) -> String {
        (["GPS \(gps.rating.title.lowercased()): \(gps.measurements(units: units))"] + gps.messages(units: units))
            .joined(separator: "\n")
    }
}

/// The GPS row of a session's details in the Logbook (#555).
struct GPSQualityGridRow: View {
    let measured: GPSQuality
    var units: CoachingUnits = .app
    @AppStorage(Preferences.gpsThresholds.key) private var thresholds = Preferences.gpsThresholds.unset

    private var gps: GPSQuality { measured.rated(with: GPSQuality.Options(preferenceText: thresholds)) }

    var body: some View {
        GridRow(alignment: .firstTextBaseline) {
            Text("GPS").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: gps.rating.symbol).foregroundStyle(gps.rating.tint).accessibilityHidden(true)
                    Text(gps.rating.title)
                }
                Text(gps.measurements(units: units)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(gps.messages(units: units), id: \.self) { message in
                    Text(message).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(GPSRatingBadge.help(gps, units: units).replacing("\n", with: ". "))
            .accessibilityIdentifier("logbook.detail.gps")
        }
    }
}
