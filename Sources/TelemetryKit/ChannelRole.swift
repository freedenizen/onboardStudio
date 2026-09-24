/// The semantic meaning of a telemetry channel. Importers tag columns with a role so display
/// objects can find "speed" or "RPM" regardless of the source file's column names.
public enum ChannelRole: Hashable, Sendable, Codable {
    case time
    case latitude
    case longitude
    case altitude
    case gpsUpdate
    case gpsDelay
    case accuracy
    case speed
    case heading
    case lap
    case distance
    case rpm
    case gear
    case throttle
    case brake
    /// Longitudinal acceleration (positive = accelerating).
    case longitudinalG
    /// Lateral acceleration (positive = right turn by RaceRender convention).
    case lateralG
    /// Seconds behind (+) or ahead of (−) the session's best lap at the same distance into the lap.
    case lapDelta
    /// Speed minus the best lap's speed at the same distance into the lap (m/s; + = faster).
    case speedDelta
    /// What the lap in progress will come to at the best lap's pace from here (s): the best lap's
    /// time plus `lapDelta`.
    case projectedLap

    // MARK: - Vehicle attributes
    //
    // Universal, not the source's wiring: a file may or may not supply one, but what it means
    // does not change with the file. The same brake pressure is `brake_pressure_front` in a
    // RaceChrono CSV and channel `66569` in the same session's `.rcz`, and both map to
    // `brakePressureFront` here.

    /// Brake line pressure, as distinct from `brake` — pedal position in percent. A car often
    /// logs both, and they are different attributes.
    case brakePressureFront
    case brakePressureRear
    case oilPressure
    case oilTemperature
    case coolantTemperature
    /// Intake or ambient air temperature.
    case intakeTemperature
    case exhaustTemperature
    /// Manifold pressure above atmospheric.
    case boostPressure
    /// Positive to the right; loggers disagree, and `TurnDirection` measures which way this one
    /// means from the session itself.
    case steeringAngle
    case clutch
    /// Roll angle of a motorcycle, or of a car's body.
    case leanAngle
    case airFuelRatio
    case fuelLevel
    case batteryVoltage
    case engineLoad

    // MARK: - Vehicle states
    //
    // On or off rather than measured. A logger rarely records them as a boolean — the reference
    // session carries ABS as a raw analog channel reading 512…2800 — so a state attribute is
    // mapped with a threshold rather than a unit.

    case absActive
    case tractionControlActive
    case pitLimiter
    /// A channel from an OBD-II source that may update at a different rate than GPS.
    case obd(String)
    /// A channel decoded straight off the vehicle's CAN bus. Distinct from `obd`: loggers read
    /// far more from CAN than OBD-II exposes, and calling those channels OBD is simply wrong.
    case canbus(String)
    /// Any other named channel.
    case aux(String)

    /// A stable, human-readable identifier such as `speed` or `aux:engine_load`.
    public var identifier: String {
        switch self {
        case .brakePressureFront: "brakePressureFront"
        case .brakePressureRear: "brakePressureRear"
        case .oilPressure: "oilPressure"
        case .oilTemperature: "oilTemperature"
        case .coolantTemperature: "coolantTemperature"
        case .intakeTemperature: "intakeTemperature"
        case .exhaustTemperature: "exhaustTemperature"
        case .boostPressure: "boostPressure"
        case .steeringAngle: "steeringAngle"
        case .clutch: "clutch"
        case .leanAngle: "leanAngle"
        case .airFuelRatio: "airFuelRatio"
        case .fuelLevel: "fuelLevel"
        case .batteryVoltage: "batteryVoltage"
        case .engineLoad: "engineLoad"
        case .absActive: "absActive"
        case .tractionControlActive: "tractionControlActive"
        case .pitLimiter: "pitLimiter"
        case .time: "time"
        case .latitude: "latitude"
        case .longitude: "longitude"
        case .altitude: "altitude"
        case .gpsUpdate: "gpsUpdate"
        case .gpsDelay: "gpsDelay"
        case .accuracy: "accuracy"
        case .speed: "speed"
        case .heading: "heading"
        case .lap: "lap"
        case .distance: "distance"
        case .rpm: "rpm"
        case .gear: "gear"
        case .throttle: "throttle"
        case .brake: "brake"
        case .longitudinalG: "longitudinalG"
        case .lateralG: "lateralG"
        case .lapDelta: "lapDelta"
        case .speedDelta: "speedDelta"
        case .projectedLap: "projectedLap"
        case .obd(let name): "obd:\(name)"
        case .canbus(let name): "canbus:\(name)"
        case .aux(let name): "aux:\(name)"
        }
    }

    /// Whether the role is one of the well-known channels (as opposed to `obd`/`canbus`/`aux`).
    public var isStandard: Bool {
        switch self {
        case .obd, .canbus, .aux: false
        default: true
        }
    }

    /// The same channel under the name it used to be given. Vehicle channels were all filed as
    /// `obd:` before CAN got its own role, so projects saved then still name them that way and
    /// must keep resolving. Lookups try a role and then its alias.
    public var legacyAlias: ChannelRole? {
        switch self {
        case .obd(let name): .canbus(name)
        case .canbus(let name): .obd(name)
        default: nil
        }
    }
}

extension ChannelRole: CustomStringConvertible {
    public var description: String { identifier }
}

extension ChannelRole {
    /// Parses the `identifier` form (`speed`, `canbus:Coolant`, `aux:Oil temp`). Returns `nil` for
    /// unknown standard names.
    public init?(identifier: String) {
        if identifier.hasPrefix("obd:") {
            self = .obd(String(identifier.dropFirst(4)))
            return
        }
        if identifier.hasPrefix("canbus:") {
            self = .canbus(String(identifier.dropFirst(7)))
            return
        }
        if identifier.hasPrefix("aux:") {
            self = .aux(String(identifier.dropFirst(4)))
            return
        }
        guard let standard = Self.standardRoles.first(where: { $0.identifier == identifier }) else { return nil }
        self = standard
    }

    /// How the attribute is named to a person. Channels the file named itself — OBD, CAN bus and
    /// anything else — keep that name, because it is what the user recognises in their logger.
    public var displayName: String {
        switch self {
        case .brakePressureFront: "Brake pressure (front)"
        case .brakePressureRear: "Brake pressure (rear)"
        case .oilPressure: "Oil pressure"
        case .oilTemperature: "Oil temperature"
        case .coolantTemperature: "Coolant temperature"
        case .intakeTemperature: "Intake temperature"
        case .exhaustTemperature: "Exhaust temperature"
        case .boostPressure: "Boost pressure"
        case .steeringAngle: "Steering angle"
        case .clutch: "Clutch"
        case .leanAngle: "Lean angle"
        case .airFuelRatio: "Air/fuel ratio"
        case .fuelLevel: "Fuel level"
        case .batteryVoltage: "Battery voltage"
        case .engineLoad: "Engine load"
        case .absActive: "ABS"
        case .tractionControlActive: "Traction control"
        case .pitLimiter: "Pit limiter"
        case .time: "Time"
        case .latitude: "Latitude"
        case .longitude: "Longitude"
        case .altitude: "Altitude"
        case .gpsUpdate: "GPS update"
        case .gpsDelay: "GPS delay"
        case .accuracy: "GPS accuracy"
        case .speed: "Speed"
        case .heading: "Heading"
        case .lap: "Lap"
        case .distance: "Distance"
        case .rpm: "RPM"
        case .gear: "Gear"
        case .throttle: "Throttle"
        case .brake: "Brake"
        case .longitudinalG: "Longitudinal G"
        case .lateralG: "Lateral G"
        case .lapDelta: "Lap delta"
        case .speedDelta: "Speed delta"
        case .projectedLap: "Projected lap time"
        case .obd, .canbus, .aux: identifier
        }
    }

    /// Whether an attribute is measured or is simply on or off.
    public enum Kind: String, Hashable, Sendable {
        /// Has a source unit and a display unit, and converts between them.
        case measurement
        /// Has a threshold instead. A logger rarely records a state as a boolean — the reference
        /// session carries ABS as a raw analog channel reading 512…2800 — so what a state needs
        /// is a level to cross, not a unit to be shown in.
        case state
    }

    public var kind: Kind {
        switch self {
        case .absActive, .tractionControlActive, .pitLimiter: .state
        default: .measurement
        }
    }

    /// The vocabulary a person maps their file's columns onto (#111, #191).
    ///
    /// Universal by construction: these say what a value *means*, never where it came from. A
    /// file may or may not supply any of them, and the same attribute is a differently named
    /// column in every logger — which is exactly why `obd`, `canbus` and `aux` are absent here.
    /// Those carry the source's own name for a channel, so they are what an attribute is mapped
    /// *to*, never a row in the table.
    ///
    /// `time` and `lap` are structure rather than data, the GPS diagnostics are not displayed,
    /// and the deltas and projection are computed from the session rather than read from a column — none of
    /// them has a source column to choose.
    public static let mappableAttributes: [ChannelRole] = [
        .speed, .rpm, .gear, .throttle, .brake, .clutch, .steeringAngle,
        .longitudinalG, .lateralG, .leanAngle,
        .brakePressureFront, .brakePressureRear, .oilPressure, .boostPressure,
        .oilTemperature, .coolantTemperature, .intakeTemperature, .exhaustTemperature,
        .airFuelRatio, .fuelLevel, .batteryVoltage, .engineLoad,
        .absActive, .tractionControlActive, .pitLimiter,
        .altitude, .distance, .heading, .latitude, .longitude, .accuracy,
    ]

    public static let standardRoles: [ChannelRole] = [
        .time, .latitude, .longitude, .altitude, .gpsUpdate, .gpsDelay, .accuracy, .speed, .heading, .lap, .distance,
        .rpm, .gear, .throttle, .brake, .longitudinalG, .lateralG, .lapDelta, .speedDelta,
        .projectedLap, .brakePressureFront, .brakePressureRear, .oilPressure, .oilTemperature, .coolantTemperature,
        .intakeTemperature, .exhaustTemperature, .boostPressure, .steeringAngle, .clutch, .leanAngle,
        .airFuelRatio, .fuelLevel, .batteryVoltage, .engineLoad,
        .absActive, .tractionControlActive, .pitLimiter,
    ]
}

extension ChannelRole {
    /// Whether this attribute answers to what was typed in a filter field (#200): its name, or
    /// the column it is read from, so that typing either `brake` or `analog_2` finds the row.
    public func matches(filter: String, source: String? = nil) -> Bool {
        TextFilter(filter).matches([displayName, source])
    }
}

extension ChannelRole {
    /// How a picker names this channel (#208): an attribute by its name — *Lateral G*, never
    /// `lateralG` — and a channel the file named itself by that name, with where it came from, so
    /// a CAN channel called `Speed` is not mistaken for the Speed attribute.
    public var pickerTitle: String {
        switch self {
        case .obd(let name): "\(name) (OBD)"
        case .canbus(let name): "\(name) (CAN bus)"
        case .aux(let name): name
        default: displayName
        }
    }

    /// `pickerTitle` for a stored identifier, which is what objects keep. One this build cannot
    /// read is shown as it is, rather than hidden.
    public static func pickerTitle(forIdentifier identifier: String) -> String {
        ChannelRole(identifier: identifier)?.pickerTitle ?? identifier
    }
}
