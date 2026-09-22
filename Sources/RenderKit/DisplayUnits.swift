import Foundation
import ProjectModel
import TelemetryKit

/// How each channel of one object's data input is converted and labelled for display (#89).
///
/// Resolved once by `RenderPlanner` and handed to the renderers, for the reason the speed unit
/// always was: a stored setting may say *automatic*, and automatic has no conversion in it.
/// Resolving here keeps that out of every renderer.
///
/// The conversion starts from the unit the values are **stored** in, not the unit the file wrote.
/// Those differ whenever `Channel.convertedToCanonicalUnit()` had something to do — speed becomes
/// m/s, altitude and distance become metres — and converting from the source unit instead would
/// apply the factor twice. `TelemetrySession.recordedUnit(of:)` answers the source unit and is the
/// wrong input here, however right it is for the mapping table's "Reads" column.
public struct DisplayUnits: Sendable, Hashable {
    /// What to do with one channel's values on the way to being drawn.
    public struct Conversion: Sendable, Hashable {
        /// The unit the values are stored in — where a conversion starts.
        public var from: TelemetryUnit
        /// The unit to draw in.
        public var to: TelemetryUnit
        /// The text to label it with.
        ///
        /// Usually `to.symbol`, but speed keeps the spelling it has always been drawn with —
        /// `kph`, not `km/h` — because changing it would change every saved project's
        /// speedometer, which is exactly what opening a project must not do.
        public var label: String

        public init(from: TelemetryUnit, to: TelemetryUnit, label: String? = nil) {
            self.from = from
            self.to = to
            self.label = label ?? to.symbol
        }
    }

    private var conversions: [String: Conversion]

    public init(_ conversions: [String: Conversion] = [:]) {
        self.conversions = conversions
    }

    /// `value`, stored, as it should be drawn. Unchanged when nothing asked for a conversion or
    /// the two units turn out not to be convertible — a wrong number is worse than an unconverted
    /// one, and the picker only offers convertible units anyway.
    public func value(_ value: Double, of identifier: String) -> Double {
        guard let conversion = conversions[identifier] else { return value }
        return conversion.from.convert(value, to: conversion.to) ?? value
    }

    /// The label to draw, or `nil` when nothing was chosen and the object's own unit label stands.
    public func label(for identifier: String) -> String? {
        conversions[identifier]?.label
    }

    /// Just #75's speed conversion, for a context built without the fuller chain: the speed
    /// channels converted out of the m/s they are stored in, labelled the way `SpeedDisplayUnit`
    /// has always spelled them.
    ///
    /// This is what `ObjectContext` falls back to, so that a caller that knows only a speed unit —
    /// a test, a preview — gets exactly the drawing it used to, rather than an empty table that
    /// silently draws m/s.
    public init(speed: SpeedDisplayUnit) {
        let conversion = Conversion(from: .metersPerSecond, to: TelemetryUnit(speed: speed), label: speed.rawValue)
        self.init(["speed": conversion, "speedDelta": conversion])
    }

    /// The unit `identifier` is drawn in, whether or not that differs from how it is stored.
    public func unit(for identifier: String) -> TelemetryUnit? {
        conversions[identifier]?.to
    }
}

extension TelemetryUnit {
    /// The telemetry unit a `SpeedDisplayUnit` names. The bridge exists because `ProjectModel`
    /// holds the document schema and does not depend on `TelemetryKit`, so #75's speed setting was
    /// written in its own three-case vocabulary. It goes away when the object level generalises.
    init(speed: SpeedDisplayUnit) {
        switch speed {
        case .mph: self = .milesPerHour
        case .kph: self = .kilometersPerHour
        case .metersPerSecond: self = .metersPerSecond
        }
    }
}
