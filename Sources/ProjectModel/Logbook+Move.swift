import Foundation

/// Sessions put on another day (#454): one filed on the wrong day could only be removed and added
/// again.
extension Logbook {
    /// Moves the sessions onto `dayID`, with the clips that are their picture. A session that had
    /// its old day's car or driver takes the new day's, when it names one, as one added to it
    /// would; a session whose circuit was its old day's typed name takes the new day's. What the
    /// session says of itself — a circuit recognised from its trace, its conditions, its notes —
    /// goes with it. The days left behind stay, empty or not. Returns how many moved.
    @discardableResult
    public func move(_ ids: [UUID], toDay dayID: UUID) throws -> Int {
        guard var target = day(id: dayID) else { return 0 }
        let moving = entries().filter { ids.contains($0.id) && $0.trackDayID != dayID }
        var sources: [UUID: TrackDay] = [:]
        for entry in moving {
            let old = entry.trackDayID.flatMap { id in sources[id] ?? day(id: id) }
            var moved = entry
            moved.trackDayID = target.id
            if !target.car.isEmpty, entry.car == (old?.car ?? "") { moved.car = target.car }
            if !target.driver.isEmpty, entry.driver == (old?.driver ?? "") { moved.driver = target.driver }
            let ownCircuit = entry.circuitID != nil || (entry.trackName ?? "") != (old?.trackName ?? "")
            if !ownCircuit, !target.circuitKey.isEmpty {
                moved.circuitID = target.circuitID
                moved.trackName = target.circuitID == nil ? target.trackName : entry.trackName
            }
            try save(moved)
            // The session's picture goes where it goes.
            if var source = old {
                let clips = source.clips.filter { $0.sessionID == entry.id }
                source.clips.removeAll { $0.sessionID == entry.id }
                target.clips += clips
                sources[source.id] = source
            }
        }
        for source in sources.values { try saveDay(source) }
        if !sources.isEmpty { try saveDay(target) }
        return moving.count
    }

    /// The day the session's own date and circuit say, found or made: where it would have gone had
    /// it been added with no day chosen.
    public func ownDay(for entry: LogbookEntry) throws -> TrackDay {
        try day(
            on: entry.date ?? Self.fileDate(of: entry) ?? entry.added, circuitID: entry.circuitID,
            trackName: entry.circuitID == nil ? entry.trackName : nil, car: entry.car, driver: entry.driver)
    }

    /// Each session onto the day its own date and circuit say (Move to Day ▸ Its Own Day).
    @discardableResult
    public func moveToOwnDays(_ ids: [UUID]) throws -> Int {
        var count = 0
        for entry in entries() where ids.contains(entry.id) {
            count += try move([entry.id], toDay: ownDay(for: entry).id)
        }
        return count
    }
}
