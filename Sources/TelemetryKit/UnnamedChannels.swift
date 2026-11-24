import Foundation

/// Channels a file had no name for: CAN channels known only by the logger's own number, as a
/// RaceChrono `.rcz` archive carries them (#111). They bind to nothing until the driver says what
/// each is, and nothing said so: a project from such a session had a dead tachometer, a dead gear
/// readout and empty Throttle and Brake panels, with no word of why (#657).
public enum UnnamedChannels {
    /// Whether `role` is a channel named by a number alone.
    public static func isUnnamed(_ role: ChannelRole) -> Bool {
        guard case .canbus(let id) = role else { return false }
        return !id.isEmpty && id.allSatisfy(\.isNumber)
    }

    /// How many of a session's channels have no name.
    public static func count(in session: TelemetrySession) -> Int {
        session.orderedChannels.filter { isUnnamed($0.role) }.count
    }

    /// Whether the session has an accelerometer's own axes and neither lateral nor longitudinal G:
    /// the G plot then has nothing to draw until two of the axes are said to be those.
    public static func hasOnlyRawAxes(_ session: TelemetrySession) -> Bool {
        let roles = session.orderedChannels.map(\.role)
        let raw = roles.contains { role in
            if case .aux(let name) = role { return ["x_acc", "y_acc", "z_acc"].contains(name) }
            return false
        }
        return raw && !roles.contains(.lateralG) && !roles.contains(.longitudinalG)
    }

    /// What the data file's inspector says, above Map Attributes…; `nil` when there is nothing to
    /// say. `namesInCSV` is for a file whose logger also exports the same session with names.
    public static func notice(unnamed: Int, rawAxes: Bool, namesInCSV: Bool) -> String? {
        guard unnamed > 0 || rawAxes else { return nil }
        var sentences: [String] = []
        if unnamed > 0 {
            let channels = unnamed == 1 ? "1 channel has" : "\(unnamed) channels have"
            sentences.append(
                "\(channels) no name in this file, only the logger's number. Say which is the RPM, the "
                    + "throttle or the brake in Map Attributes, and the gauges that read them will draw.")
            if namesInCSV {
                sentences.append("RaceChrono's CSV export of the same session carries the names.")
            }
        }
        if rawAxes {
            sentences.append(
                "Its accelerometer is in the logger's own axes (x, y, z): map the two that point across and "
                    + "along the car to Lateral G and Longitudinal G for the G plot.")
        }
        return sentences.joined(separator: " ")
    }

    /// The notice for `session`.
    public static func notice(for session: TelemetrySession, namesInCSV: Bool) -> String? {
        notice(unnamed: count(in: session), rawAxes: hasOnlyRawAxes(session), namesInCSV: namesInCSV)
    }
}
