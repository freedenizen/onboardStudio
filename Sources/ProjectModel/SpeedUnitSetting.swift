import Foundation
import TelemetryKit

/// A speed unit as *stored* on an object, a project or the app: a concrete choice, or a deferral
/// to whatever the level above decided (#75).
///
/// Deliberately a different type from `SpeedDisplayUnit`, which stays concrete and total. Adding an
/// `automatic` case to `SpeedDisplayUnit` would have given `factorFromMetersPerSecond` a value it
/// cannot have, and every renderer reads that directly — an unresolved unit would have silently
/// converted by the wrong factor. Keeping the two types apart makes rendering an unresolved unit a
/// compile error instead.
///
/// The raw values of the concrete cases match `SpeedDisplayUnit`'s exactly, so a file written
/// before this existed decodes unchanged.
public enum SpeedUnitSetting: String, Codable, Sendable, CaseIterable, Hashable {
    /// Follow the level above: object → project → app → the data itself.
    case automatic
    case mph
    case kph
    case metersPerSecond = "m/s"

    public init(_ unit: SpeedDisplayUnit) {
        switch unit {
        case .mph: self = .mph
        case .kph: self = .kph
        case .metersPerSecond: self = .metersPerSecond
        }
    }

    /// The concrete unit this pins, or `nil` when it defers.
    public var pinned: SpeedDisplayUnit? {
        switch self {
        case .automatic: nil
        case .mph: .mph
        case .kph: .kph
        case .metersPerSecond: .metersPerSecond
        }
    }

    public var displayName: String {
        switch self {
        case .automatic: "Automatic"
        case .mph: "mph"
        case .kph: "kph"
        case .metersPerSecond: "m/s"
        }
    }

    /// The unit for a place with no one data file to ask — the Logbook, Coaching, Replay (#464):
    /// what the setting pins, else the road unit of the region. Those places each had their own
    /// answer to *Automatic*, and the Logbook's was km/h whatever the setting said.
    public func shown(in locale: Locale = .current) -> SpeedDisplayUnit {
        pinned ?? .regional(locale)
    }
}

extension SpeedDisplayUnit {
    /// The unit a region's roads are signed in: miles per hour under the US and UK measurement
    /// systems, kilometres per hour everywhere else. What *Automatic* comes to when no file says
    /// better (#464) — never metres per second, which is how a logger stores speed and not how
    /// anybody reads a speedometer.
    public static func regional(_ locale: Locale = .current) -> SpeedDisplayUnit {
        locale.measurementSystem == .metric ? .kph : .mph
    }

    /// The symbol for a line of text: "km/h" where the picker and a saved gauge say "kph".
    public var symbol: String {
        switch self {
        case .mph: "mph"
        case .kph: "km/h"
        case .metersPerSecond: "m/s"
        }
    }

    /// "212 km/h": a speed stored in metres per second, in this unit, to the whole number.
    public func text(metersPerSecond: Double) -> String {
        "\(Int((metersPerSecond * factorFromMetersPerSecond).rounded())) \(symbol)"
    }

    /// "+3 km/h", or "same" within half a unit: a change of speed stored in metres per second.
    public func changeText(metersPerSecond: Double) -> String {
        let change = metersPerSecond * factorFromMetersPerSecond
        return change.magnitude < 0.5 ? "same" : String(format: "%+.0f \(symbol)", change)
    }
}

extension CoachingUnits {
    /// What coaching is written in for the app's speed setting: mph gives mph and feet, anything
    /// else km/h and metres. *Automatic* follows the region (#464) — except in a project saved
    /// before schema 3, whose notes stay in km/h and metres as that build wrote them.
    public static func following(
        _ setting: SpeedUnitSetting, legacyAutomatic: Bool = false, locale: Locale = .current
    ) -> CoachingUnits {
        let unit = legacyAutomatic ? setting.pinned ?? .kph : setting.shown(in: locale)
        return unit == .mph ? .imperial : .metric
    }
}

/// Resolves the levels of #75's chain for one project: **object → project → app → automatic**.
///
/// Each level stores `automatic` unless somebody pinned it, so changing a level moves everything
/// below it that has not been pinned and leaves the pinned ones alone. That is the intended
/// behaviour, not a side effect.
public struct UnitResolver: Hashable, Sendable {
    /// What the app-wide preference says.
    public var app: SpeedUnitSetting
    /// What this project says.
    public var project: SpeedUnitSetting
    /// What the data itself suggests — the unit the speed channel was recorded in. `nil` when
    /// there is no data to ask, which is why there is a final fallback below.
    public var automatic: SpeedDisplayUnit?
    /// The road unit of the user's region, which stands in when the data recorded metres per
    /// second (#464): RaceChrono's CSV does, and every new project from one had a speedometer
    /// reading "22 m/s" at 80 km/h. `nil` leaves the data's unit alone, as a project saved before
    /// schema 3 must (`ProjectSettings.legacyAutomaticUnits`).
    public var regional: SpeedDisplayUnit?

    /// Used when every level defers and the data has nothing to say. mph because that is what
    /// every object has silently asserted since before any of this existed, so a project with no
    /// data loaded looks the way it always did.
    public static let lastResort = SpeedDisplayUnit.mph

    public init(
        app: SpeedUnitSetting = .automatic, project: SpeedUnitSetting = .automatic, automatic: SpeedDisplayUnit? = nil,
        regional: SpeedDisplayUnit? = nil
    ) {
        self.app = app
        self.project = project
        self.automatic = automatic
        self.regional = regional
    }

    /// Whether the region's unit is standing in for a file that recorded metres per second.
    private var regionStandsIn: Bool { automatic == .metersPerSecond && regional != nil }

    /// The unit an object with this setting actually draws in.
    public func speed(_ object: SpeedUnitSetting) -> SpeedDisplayUnit {
        let fromTheData = regionStandsIn ? regional : automatic
        return object.pinned ?? project.pinned ?? app.pinned ?? fromTheData ?? Self.lastResort
    }

    /// Which level supplied the answer, so a control can say so rather than showing a bare value.
    public func source(_ object: SpeedUnitSetting) -> UnitSource {
        if object.pinned != nil { return .object }
        if project.pinned != nil { return .project }
        if app.pinned != nil { return .app }
        if regionStandsIn { return .region }
        return automatic == nil ? .fallback : .data
    }
}

/// Where an effective unit came from.
public enum UnitSource: String, Sendable, Hashable {
    case object, project, app, data, fallback
    /// The region's road unit, for a file that recorded metres per second (#464).
    case region

    /// How a control describes where the value it is showing came from.
    public var describedAsInherited: String? {
        switch self {
        case .object: nil
        case .project: "from this project"
        case .app: "from Settings"
        case .data: "from the data"
        case .region: "for your region, as the data is in m/s"
        case .fallback: "the default"
        }
    }
}
