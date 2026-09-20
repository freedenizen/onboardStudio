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

    public static let standardRoles: [ChannelRole] = [
        .time, .latitude, .longitude, .altitude, .gpsUpdate, .gpsDelay, .accuracy, .speed, .heading, .lap, .distance,
        .rpm, .gear, .throttle, .brake, .longitudinalG, .lateralG, .lapDelta, .speedDelta,
    ]
}
