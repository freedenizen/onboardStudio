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
        case .aux(let name): "aux:\(name)"
        }
    }

    /// Whether the role is one of the well-known channels (as opposed to `obd`/`aux`).
    public var isStandard: Bool {
        switch self {
        case .obd, .aux: false
        default: true
        }
    }
}

extension ChannelRole: CustomStringConvertible {
    public var description: String { identifier }
}

extension ChannelRole {
    /// Parses the `identifier` form (`speed`, `obd:Coolant`, `aux:Oil temp`). Returns `nil` for
    /// unknown standard names.
    public init?(identifier: String) {
        if identifier.hasPrefix("obd:") {
            self = .obd(String(identifier.dropFirst(4)))
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
