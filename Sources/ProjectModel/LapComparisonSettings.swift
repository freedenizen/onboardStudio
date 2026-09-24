import Foundation

/// Two laps played side by side, the second kept level with the first by distance (#154).
///
/// The project plays `lap`: its video is the project's own clock and its data drives the objects as
/// usual. `comparedLap` is shown beside it — its picture slowed down or sped up, moment by moment,
/// so that at every frame it is as far round its lap as `lap` is round its own. The two can come
/// from one session (lap 7 against lap 5) or from two (today against last month, or another
/// driver): each names its own data and video input.
public struct LapComparisonSettings: Hashable, Codable, Sendable {
    /// One lap: which data file it is in, which camera filmed it, and its number there.
    public struct Side: Hashable, Codable, Sendable {
        public var dataInputID: InputID
        public var videoInputID: InputID
        public var lap: Int

        public init(dataInputID: InputID, videoInputID: InputID, lap: Int) {
            self.dataInputID = dataInputID
            self.videoInputID = videoInputID
            self.lap = lap
        }
    }

    public var lap: Side
    public var comparedLap: Side
    public var layout: LapComparisonLayout

    public init(lap: Side, comparedLap: Side, layout: LapComparisonLayout = .sideBySide) {
        self.lap = lap
        self.comparedLap = comparedLap
        self.layout = layout
    }
}

/// How the two pictures of a lap comparison share the frame.
public enum LapComparisonLayout: String, Codable, Sendable, CaseIterable {
    /// Left and right, each with its readouts beneath it.
    case sideBySide
    /// One above the other, each with its readouts beside it.
    case stacked

    public var displayName: String {
        switch self {
        case .sideBySide: "Side by side"
        case .stacked: "Stacked"
        }
    }
}

extension Project {
    /// Lays the project out to compare two laps (#154): each lap's picture, its lap timer and speed
    /// with it, and the delta between them. Replaces the objects, as applying a template does;
    /// `lapRange` — the lap playing, in project seconds — becomes the export range when known.
    public mutating func compareLaps(_ settings: LapComparisonSettings, lapRange: ClosedRange<Double>?) {
        lapComparison = settings
        displayObjects = Self.comparisonLayout(settings)
        timeline = .empty
        if let lapRange { export.range = .span(start: lapRange.lowerBound, end: lapRange.upperBound) }
    }

    /// Stops comparing: the objects that showed the compared lap go, the rest stay as they are.
    public mutating func stopComparingLaps() {
        lapComparison = nil
        displayObjects.removeAll(where: \.followsComparedLap)
    }

    /// The objects of a comparison, for a 16:9 frame. Each 16:9 picture takes half the width
    /// side by side, or half the height stacked, with its readouts beneath it or beside it.
    static func comparisonLayout(_ settings: LapComparisonSettings) -> [DisplayObject] {
        struct Place {
            var picture: UnitRect
            var timer: UnitRect
            var speed: UnitRect
        }
        let places: [Place]
        let delta: UnitRect
        switch settings.layout {
        case .sideBySide:
            places = [0.0, 0.5].map { x in
                Place(
                    picture: UnitRect(x: x, y: 0.1, width: 0.5, height: 0.5),
                    timer: UnitRect(x: x + 0.05, y: 0.64, width: 0.25, height: 0.08),
                    speed: UnitRect(x: x + 0.32, y: 0.64, width: 0.13, height: 0.08))
            }
            delta = UnitRect(x: 0.4, y: 0.82, width: 0.2, height: 0.08)
        case .stacked:
            places = [0.0, 0.5].map { y in
                Place(
                    picture: UnitRect(x: 0.02, y: y, width: 0.5, height: 0.5),
                    timer: UnitRect(x: 0.56, y: y + 0.12, width: 0.25, height: 0.08),
                    speed: UnitRect(x: 0.56, y: y + 0.24, width: 0.13, height: 0.08))
            }
            delta = UnitRect(x: 0.72, y: 0.46, width: 0.2, height: 0.08)
        }
        var objects: [DisplayObject] = []
        for (index, (side, place)) in zip([settings.lap, settings.comparedLap], places).enumerated() {
            let follows = index == 1
            let name = follows ? "Compared Lap" : "Lap"
            objects.append(
                DisplayObject(
                    label: "\(name) Picture", inputID: side.videoInputID, frame: place.picture,
                    kind: .video(VideoObjectParams()), followsComparedLap: follows))
            objects.append(
                DisplayObject(
                    label: "\(name) Timer", inputID: side.dataInputID, frame: place.timer,
                    kind: .timer(TimerParams(mode: .currentLap)), followsComparedLap: follows))
            objects.append(
                DisplayObject(
                    label: "\(name) Speed", inputID: side.dataInputID, frame: place.speed,
                    kind: .textData(TextDataParams(channel: "speed", label: "SPEED", alignment: .trailing)),
                    followsComparedLap: follows))
        }
        objects.append(
            DisplayObject(
                label: "Delta", inputID: settings.lap.dataInputID, frame: delta,
                kind: .timer(
                    TimerParams(mode: .deltaToBest, showLapNumber: false, label: "DELTA", deltaReference: .comparedLap))
            ))
        return objects
    }
}
