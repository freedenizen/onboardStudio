import Foundation

/// How far a driver has come along the Logbook's Getting Started (#452): from a day's files to a
/// video, a coaching session and the progress across visits — read from the logbook where it
/// keeps a trace, and from what the window remembers where it keeps none.
public struct LogbookChecklist: Sendable, Equatable {
    /// There is a session in the logbook.
    public let hasSessions: Bool
    /// Every session names its car.
    public let carsNamed: Bool
    /// A project has been made from a session.
    public let madeVideo: Bool
    /// The Coaching window has been opened on a session, or a session has coaching choices.
    public let coached: Bool
    /// Trends or the Season has been looked at.
    public let sawProgress: Bool

    public init(entries: [LogbookEntry], coached: Bool, sawProgress: Bool) {
        hasSessions = !entries.isEmpty
        carsNamed = hasSessions && !entries.contains { $0.car.trimmingCharacters(in: .whitespaces).isEmpty }
        madeVideo = entries.contains { !$0.projects.isEmpty }
        self.coached = coached || entries.contains { $0.coaching != nil }
        self.sawProgress = sawProgress
    }

    public var isComplete: Bool { hasSessions && carsNamed && madeVideo && coached && sawProgress }

    /// The newest session with no car, whose day is where the car is given.
    public static func sessionWithoutCar(in entries: [LogbookEntry]) -> LogbookEntry? {
        entries.filter { $0.car.trimmingCharacters(in: .whitespaces).isEmpty }
            .max { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
    }
}
