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
    let quality: GPSQuality
    var units: CoachingUnits = .app

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
