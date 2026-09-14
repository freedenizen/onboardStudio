import Foundation

/// Channels computed from other channels (speed, heading and distance from GPS position).
public enum DerivedChannels {
    static let earthRadius = 6_371_008.8

    /// Great-circle distance in meters between two coordinates (haversine).
    public static func distance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let φ1 = lat1 * .pi / 180
        let φ2 = lat2 * .pi / 180
        let dφ = (lat2 - lat1) * .pi / 180
        let dλ = (lon2 - lon1) * .pi / 180
        let a = sin(dφ / 2) * sin(dφ / 2) + cos(φ1) * cos(φ2) * sin(dλ / 2) * sin(dλ / 2)
        return 2 * earthRadius * atan2(sqrt(a), sqrt(1 - a))
    }

    /// Initial bearing in degrees (0 = north, 90 = east) from point 1 to point 2.
    public static func bearing(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let φ1 = lat1 * .pi / 180
        let φ2 = lat2 * .pi / 180
        let dλ = (lon2 - lon1) * .pi / 180
        let y = sin(dλ) * cos(φ2)
        let x = cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(dλ)
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Speed in m/s at each position sample from the distance to the next sample. The last
    /// sample repeats the previous speed. Requires latitude and longitude on identical time axes.
    public static func speed(latitude: Channel, longitude: Channel) -> Channel? {
        guard let pairs = alignedPositions(latitude, longitude), pairs.times.count >= 2 else { return nil }
        var speeds = [Double](repeating: 0, count: pairs.times.count)
        for index in 0..<(pairs.times.count - 1) {
            let dt = pairs.times[index + 1] - pairs.times[index]
            guard dt > 0 else { continue }
            let d = distance(
                lat1: pairs.lat[index], lon1: pairs.lon[index], lat2: pairs.lat[index + 1], lon2: pairs.lon[index + 1])
            speeds[index] = d / dt
        }
        speeds[speeds.count - 1] = speeds[speeds.count - 2]
        return Channel(
            role: .speed, name: "Speed (from GPS)", unit: .metersPerSecond, times: pairs.times, values: speeds)
    }

    /// Heading in degrees from each sample to the next. Holds the last computed heading when
    /// consecutive samples coincide.
    public static func heading(latitude: Channel, longitude: Channel) -> Channel? {
        guard let pairs = alignedPositions(latitude, longitude), pairs.times.count >= 2 else { return nil }
        var headings = [Double](repeating: 0, count: pairs.times.count)
        var last = 0.0
        for index in 0..<(pairs.times.count - 1) {
            let moved = pairs.lat[index] != pairs.lat[index + 1] || pairs.lon[index] != pairs.lon[index + 1]
            if moved {
                last = bearing(
                    lat1: pairs.lat[index], lon1: pairs.lon[index], lat2: pairs.lat[index + 1],
                    lon2: pairs.lon[index + 1])
            }
            headings[index] = last
        }
        headings[headings.count - 1] = last
        return Channel(
            role: .heading, name: "Heading (from GPS)", unit: .degrees, times: pairs.times, values: headings,
            interpolation: .step)
    }

    /// Cumulative distance travelled in meters.
    public static func distance(latitude: Channel, longitude: Channel) -> Channel? {
        guard let pairs = alignedPositions(latitude, longitude), pairs.times.count >= 2 else { return nil }
        var cumulative = [Double](repeating: 0, count: pairs.times.count)
        for index in 1..<pairs.times.count {
            cumulative[index] =
                cumulative[index - 1]
                + distance(
                    lat1: pairs.lat[index - 1], lon1: pairs.lon[index - 1], lat2: pairs.lat[index],
                    lon2: pairs.lon[index])
        }
        return Channel(
            role: .distance, name: "Distance (from GPS)", unit: .meters, times: pairs.times, values: cumulative)
    }

    private struct AlignedPositions {
        let times: [Double]
        let lat: [Double]
        let lon: [Double]
    }

    private static func alignedPositions(_ latitude: Channel, _ longitude: Channel) -> AlignedPositions? {
        guard latitude.times == longitude.times else {
            // Resample longitude onto latitude's time axis.
            let lon = latitude.times.map { longitude.value(at: $0) ?? 0 }
            return AlignedPositions(times: latitude.times, lat: latitude.values, lon: lon)
        }
        return AlignedPositions(times: latitude.times, lat: latitude.values, lon: longitude.values)
    }
}
