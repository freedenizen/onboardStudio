import Foundation

/// The other half of agreement across laps (#598): a bend most of the session's laps find as a
/// corner, which the reference lap drove through without turning enough to count, is a corner of
/// the reference lap too.
///
/// The best lap is the likeliest to straighten a gentle bend — a quick lap uses more of the track —
/// so without this the lap everything is measured on was the lap most likely to be a corner short:
/// one fewer on the map, in the sectors and in the coaching, a named turn never shown, and every
/// count after it one less than on a visit whose best lap found it.
extension CornerAgreement {
    /// `corners` — the reference lap's, already agreed on — with the corners most of `others`
    /// find and the reference lap does not, placed on the reference lap along `path`.
    ///
    /// Each other lap's corners that pair with none of the reference's (one to one, closest first,
    /// as in `agreed`) are grouped across laps the same way; a group found on more than half of the
    /// laps — the reference among them when it is one of the session's laps, not finding it — is a
    /// missing corner. It is placed where the reference lap passes the group's most central
    /// corner: its entry, apex and exit, each the nearest point of `path` to that corner's, looked
    /// for only around the apex so a parallel straight cannot take it. It keeps that corner's turn
    /// (left or right, and how far), since the reference lap barely turned there. One the
    /// reference lap does not pass within `CornerNaming.matchRadiusMeters` of, or whose apex falls
    /// inside a corner the reference already has — two bends it drove as one — is not added.
    static func addingMissing(
        to corners: [Corner], from others: [[Corner]], includesReference: Bool, along path: CornerDetector.Path
    ) -> [Corner] {
        let voters = others.filter { lap in lap.contains { $0.apexLatitude != nil } }
        let laps = voters.count + (includesReference ? 1 : 0)
        guard laps >= minimumLaps else { return corners }
        let pins = corners.compactMap { TurnName(label: "·", corner: $0) }
        // Every other lap's corners the reference has no corner for, grouped bend by bend.
        var groups: [[Corner]] = []
        for lap in voters {
            let unmatched = zip(lap, CornerNaming.match(lap, to: pins)).filter { $0.1 == nil }.map(\.0)
            let seeds = groups.compactMap { $0.first.flatMap { TurnName(label: "·", corner: $0) } }
            for (corner, group) in zip(unmatched, CornerNaming.match(unmatched, to: seeds)) {
                if let group { groups[group].append(corner) } else { groups.append([corner]) }
            }
        }
        let missing = groups.filter { Double($0.count) > Double(laps) * majority }.compactMap(central)
        let added = missing.compactMap { placed($0, on: path) }.filter { corner in
            !corners.contains { $0.contains(distance: corner.apexDistance) }
        }
        return (corners + added).sorted { $0.apexDistance < $1.apexDistance }
    }

    /// The corner of `group` whose apex is nearest the others': the bend as most laps drove it.
    static func central(_ group: [Corner]) -> Corner? {
        func metres(_ a: Corner, _ b: Corner) -> Double {
            guard let la = a.apexLatitude, let lo = a.apexLongitude, let lb = b.apexLatitude, let mb = b.apexLongitude
            else { return .infinity }
            return DerivedChannels.distance(lat1: la, lon1: lo, lat2: lb, lon2: mb)
        }
        return group.min { a, b in
            group.reduce(0) { $0 + metres(a, $1) } < group.reduce(0) { $0 + metres(b, $1) }
        }
    }

    /// `corner`, found on another lap, as the reference lap along `path` drove it; `nil` when the
    /// reference lap does not pass near it.
    static func placed(_ corner: Corner, on path: CornerDetector.Path) -> Corner? {
        guard let latitude = corner.apexLatitude, let longitude = corner.apexLongitude,
            let apex = path.nearest(latitude: latitude, longitude: longitude, around: nil),
            apex.metres <= CornerNaming.matchRadiusMeters
        else { return nil }
        // Entry and exit are looked for within the corner's own length of the apex, either way.
        let reach = Int((corner.lengthMeters / path.step).rounded(.up)) + 1
        let entry = corner.trace.first.flatMap {
            path.nearest(latitude: $0.latitude, longitude: $0.longitude, around: (apex.index, reach))
        }
        let exit = corner.trace.last.flatMap {
            path.nearest(latitude: $0.latitude, longitude: $0.longitude, around: (apex.index, reach))
        }
        let start = entry?.index ?? apex.index
        let end = exit?.index ?? apex.index
        let indices = path.indices(from: start, to: end)
        let every = max(1, Int((CornerDetector.traceSpacingMeters / path.step).rounded()))
        let trace = indices.enumerated().compactMap { offset, index in
            offset % every == 0 || offset == indices.count - 1
                ? GeoPoint(latitude: path.latitude[index], longitude: path.longitude[index]) : nil
        }
        return Corner(
            startDistance: path.distances[start], endDistance: path.distances[end],
            apexDistance: path.distances[apex.index], headingChangeDegrees: corner.headingChangeDegrees,
            lapLengthMeters: path.length, apexLatitude: path.latitude[apex.index],
            apexLongitude: path.longitude[apex.index], trace: trace)
    }
}

extension Corner {
    /// Whether `distance` into the lap lies between this corner's entry and exit, across the
    /// start/finish line for a corner that wraps it.
    func contains(distance: Double) -> Bool {
        wrapsStartFinish
            ? distance >= startDistance || distance <= endDistance
            : (startDistance...endDistance).contains(distance)
    }
}

extension CornerDetector.Path {
    /// The point of the path nearest a position, and how far it is, metres. With `around`, only
    /// within `reach` points of that index either way — round the line on a closed lap.
    func nearest(latitude: Double, longitude: Double, around: (index: Int, reach: Int)?) -> (
        index: Int, metres: Double
    )? {
        let candidates: [Int]
        if let around {
            let span = (around.index - around.reach)...(around.index + around.reach)
            candidates = span.compactMap { index in
                if (0..<count).contains(index) { return index }
                return isClosed ? (index % count + count) % count : nil
            }
        } else {
            candidates = Array(0..<count)
        }
        return candidates.map { index in
            (
                index,
                DerivedChannels.distance(
                    lat1: latitude, lon1: longitude, lat2: self.latitude[index], lon2: self.longitude[index])
            )
        }.min { $0.1 < $1.1 }
    }

    /// The indices from `start` to `end` in driving order, round the line when `end` comes first.
    func indices(from start: Int, to end: Int) -> [Int] {
        start <= end ? Array(start...end) : Array(start..<count) + Array(0...end)
    }
}
