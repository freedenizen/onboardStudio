import Foundation

/// What a project is called before it is saved (#481, #467): the title of its window, the name Save
/// suggests, and the name of a video exported from it. A project made from a Logbook session is
/// called by the session as the Logbook lists it — "Sonoma Raceway, Sep 22, 2026" — and any other
/// by its Details when they say where or when. A saved project is called by its file.
public enum ProjectNaming {
    /// "Sonoma Raceway, Sep 22, 2026": a session as the Logbook lists it, its title alone when the
    /// day is unknown.
    public static func name(title: String, date: Date?) -> String {
        guard let date else { return title }
        return "\(title), \(date.formatted(date: .abbreviated, time: .omitted))"
    }

    /// From a project's Details: the track and the day when both are given, else whichever is;
    /// `nil` when neither is, and the project stays "Untitled".
    public static func name(details: ProjectDetails) -> String? {
        let track = details.track.trimmingCharacters(in: .whitespacesAndNewlines)
        let day = ProjectDetails.displayDate(details.date)
        switch (track.isEmpty ? nil : track, day) {
        case (let track?, let day?): return "\(track), \(day)"
        case (let track?, nil): return track
        case (nil, let day?): return day
        case (nil, nil): return nil
        }
    }

    /// `name`, or "name 2", "name 3"… — the first that no other open project is called, as a second
    /// Untitled is "Untitled 2".
    public static func numbered(_ name: String, taken: Set<String>) -> String {
        guard taken.contains(name) else { return name }
        var number = 2
        while taken.contains("\(name) \(number)") { number += 1 }
        return "\(name) \(number)"
    }

    /// `name` as the name of a file: a slash or a colon, which the file system and the Finder each
    /// read as a separator, becomes a hyphen, and nothing at all becomes "Untitled".
    public static func fileName(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Untitled" : cleaned
    }
}
