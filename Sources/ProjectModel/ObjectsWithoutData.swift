import Foundation

extension DisplayObjectKind {
    /// The channels this object reads to draw anything at all, by identifier: the ones its
    /// inspector warns about when its data file has none of that name. An empty identifier is a
    /// channel not chosen yet. Objects drawn from laps or position — timers, the map, the panels
    /// — read none by name and are not listed.
    public var neededChannels: [String] {
        switch self {
        case .speedometer(let params), .tachometer(let params), .gauge(let params): [params.channel]
        case .bar(let params): [params.channel]
        case .textData(let params): [params.channel]
        case .gear(let params): [params.channel]
        case .graph(let params): params.series.map(\.channel)
        case .indicator(let params): [params.channel]
        case .steeringWheel(let params): [params.channel]
        case .gForce(let params):
            [
                params.lateralChannel.isEmpty ? "lateralG" : params.lateralChannel,
                params.longitudinalChannel.isEmpty ? "longitudinalG" : params.longitudinalChannel,
            ]
        default: []
        }
    }
}

extension Project {
    /// The objects on show that have nothing to draw: their data file is read, and it has none of
    /// the channels they need. `channels` is what each data input offers once loaded; an object
    /// whose input has not been read yet is not judged.
    ///
    /// A project made from a session lays its template out whole, and a file with no engine
    /// channels left the tachometer on zero, the gear a dash and the G plot at 0.00 — said only in
    /// each object's inspector, while the window's next step was Export (#658).
    public func objectsWithoutData(_ channels: [InputID: [ChannelSummary]]) -> [DisplayObject] {
        displayObjects.filter { object in
            guard object.isVisible, let inputID = object.inputID, let offered = channels[inputID], !offered.isEmpty
            else { return false }
            let needed = object.kind.neededChannels
            guard !needed.isEmpty else { return false }
            let names = Set(offered.map(\.identifier))
            return needed.allSatisfy { !names.contains($0) }
        }
    }
}

/// What the window says about objects with nothing to draw, before it suggests exporting (#658).
public enum ObjectsWithoutDataWording {
    /// "Give 3 gauges their data", "Give 1 gauge its data".
    public static func title(_ count: Int) -> String {
        count == 1 ? "Give 1 gauge its data" : "Give \(count) gauges their data"
    }

    /// "RPM, Gear and G have no channel in the data file and draw nothing. Map its columns to
    /// them, or remove them before you export."
    public static func detail(_ labels: [String]) -> String {
        let shown = Array(labels.prefix(3))
        let rest = labels.count - shown.count
        let names = ListFormatter.localizedString(byJoining: rest > 0 ? shown + ["\(rest) more"] : shown)
        let one = labels.count == 1
        return "\(names) \(one ? "has" : "have") no channel in the data file and \(one ? "draws" : "draw") nothing. "
            + "Map its columns to \(one ? "it" : "them"), or remove \(one ? "it" : "them") before you export."
    }

    /// "Remove It" / "Remove Them".
    public static func removeTitle(_ count: Int) -> String { count == 1 ? "Remove It" : "Remove Them" }
}
