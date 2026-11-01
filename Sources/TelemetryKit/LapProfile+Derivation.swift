import Foundation

extension LapProfile {
    // MARK: - Derivation

    /// Bearing at each grid point from the points either side of it, so one jittery fix cannot
    /// swing it; one-sided at the ends.
    static func headings(latitude: [Double], longitude: [Double]) -> [Double] {
        let count = latitude.count
        guard count >= 2 else { return Array(repeating: 0, count: count) }
        return (0..<count).map { index in
            let from = max(0, index - 1)
            let to = min(count - 1, index + 1)
            return DerivedChannels.bearing(
                lat1: latitude[from], lon1: longitude[from], lat2: latitude[to], lon2: longitude[to])
        }
    }

    /// Speed at each grid point from how long the step either side of it took.
    static func speeds(distances: [Double], elapsed: [Double]) -> [Double] {
        let count = distances.count
        guard count >= 2 else { return Array(repeating: 0, count: count) }
        var result = [Double](repeating: 0, count: count)
        for index in 0..<count {
            let from = max(0, index - 1)
            let to = min(count - 1, index + 1)
            let dt = elapsed[to] - elapsed[from]
            result[index] = dt > 0 ? (distances[to] - distances[from]) / dt : 0
        }
        return result
    }

    /// `v · dv/ds` in g: how hard the car was accelerating (+) or braking (−) at each grid point.
    static func longitudinalG(speed: [Double], distances: [Double]) -> [Double] {
        let count = speed.count
        guard count >= 2 else { return Array(repeating: 0, count: count) }
        var result = [Double](repeating: 0, count: count)
        for index in 0..<count {
            let from = max(0, index - 1)
            let to = min(count - 1, index + 1)
            let ds = distances[to] - distances[from]
            result[index] = ds > 0 ? speed[index] * (speed[to] - speed[from]) / ds / gravity : 0
        }
        return result
    }

    /// `v² · κ` in g, where κ is the heading change per metre; positive turning right, which is
    /// the sign the recorded `lateralG` channel uses.
    static func lateralG(speed: [Double], heading: [Double], distances: [Double]) -> [Double] {
        let count = speed.count
        guard count >= 2 else { return Array(repeating: 0, count: count) }
        var result = [Double](repeating: 0, count: count)
        for index in 0..<count {
            let from = max(0, index - 1)
            let to = min(count - 1, index + 1)
            let ds = distances[to] - distances[from]
            var turn = heading[to] - heading[from]
            if turn > 180 { turn -= 360 }
            if turn < -180 { turn += 360 }
            let curvature = ds > 0 ? turn * .pi / 180 / ds : 0
            result[index] = speed[index] * speed[index] * curvature / gravity
        }
        return result
    }

    /// Centred moving average over `points` grid points (made odd), shrinking at the ends.
    static func smoothed(_ values: [Double], points: Int) -> [Double] {
        let half = max(0, (points - 1) / 2)
        guard half > 0, values.count > 2 else { return values }
        var prefix = [0.0]
        prefix.reserveCapacity(values.count + 1)
        for value in values { prefix.append(prefix[prefix.count - 1] + value) }
        return (0..<values.count).map { index in
            let lower = max(0, index - half)
            let upper = min(values.count - 1, index + half)
            return (prefix[upper + 1] - prefix[lower]) / Double(upper - lower + 1)
        }
    }
}
