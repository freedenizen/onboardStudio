import Foundation

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

    /// Used when every level defers and the data has nothing to say. mph because that is what
    /// every object has silently asserted since before any of this existed, so a project with no
    /// data loaded looks the way it always did.
    public static let lastResort = SpeedDisplayUnit.mph

    public init(
        app: SpeedUnitSetting = .automatic, project: SpeedUnitSetting = .automatic, automatic: SpeedDisplayUnit? = nil
    ) {
        self.app = app
        self.project = project
        self.automatic = automatic
    }

    /// The unit an object with this setting actually draws in.
    public func speed(_ object: SpeedUnitSetting) -> SpeedDisplayUnit {
        object.pinned ?? project.pinned ?? app.pinned ?? automatic ?? Self.lastResort
    }

    /// Which level supplied the answer, so a control can say so rather than showing a bare value.
    public func source(_ object: SpeedUnitSetting) -> UnitSource {
        if object.pinned != nil { return .object }
        if project.pinned != nil { return .project }
        if app.pinned != nil { return .app }
        return automatic == nil ? .fallback : .data
    }
}

/// Where an effective unit came from.
public enum UnitSource: String, Sendable, Hashable {
    case object, project, app, data, fallback

    /// How a control describes where the value it is showing came from.
    public var describedAsInherited: String? {
        switch self {
        case .object: nil
        case .project: "from this project"
        case .app: "from Settings"
        case .data: "from the data"
        case .fallback: "the default"
        }
    }
}
