import Foundation
import TelemetryKit

/// A session's weather from the hourly record for its place and time (#560), from Open-Meteo: what
/// to ask for, how to read the answer, and what it says about the air, the sky and the surface.
///
/// Only the circuit's position rounded to a tenth of a degree (about 10 km, finer than the record
/// itself) and the dates are sent. The network request is the app's; this is the arithmetic.
public enum WeatherLookup {
    /// Where the answer comes from, for the credit line the licence (CC BY 4.0) asks for.
    public static let credit = "Weather data by Open-Meteo.com"
    public static let creditURL = URL(filePath: "/").openMeteo

    /// How long a session without a known duration is taken to have run.
    public static let assumedDuration: TimeInterval = 20 * 60
    /// How long before the session rain is taken to have left the surface damp.
    public static let wetBefore: TimeInterval = 6 * 3600
    /// The archive is days behind; a session newer than this is read from the forecast record.
    public static let archiveDelay: TimeInterval = 6 * 86_400

    /// What is asked for: a place and a span of time.
    public struct Request: Hashable, Sendable {
        public var latitude: Double
        public var longitude: Double
        public var start: Date
        public var end: Date

        /// The session from `start` for `duration`, at a place rounded to a tenth of a degree.
        public init(latitude: Double, longitude: Double, start: Date, duration: TimeInterval?) {
            self.latitude = (latitude * 10).rounded() / 10
            self.longitude = (longitude * 10).rounded() / 10
            self.start = start
            end = start.addingTimeInterval(max(duration ?? WeatherLookup.assumedDuration, 60))
        }

        /// The request's URL: the archive for an old session, the forecast record for a recent one.
        public func url(now: Date = Date()) -> URL {
            let recent = now.timeIntervalSince(end) < WeatherLookup.archiveDelay
            var components = URLComponents()
            components.scheme = "https"
            components.host = recent ? "api.open-meteo.com" : "archive-api.open-meteo.com"
            components.path = recent ? "/v1/forecast" : "/v1/archive"
            let day = Date.ISO8601FormatStyle(timeZone: .gmt).year().month().day()
                .dateSeparator(.dash)
            components.queryItems = [
                URLQueryItem(name: "latitude", value: String(format: "%.1f", latitude)),
                URLQueryItem(name: "longitude", value: String(format: "%.1f", longitude)),
                URLQueryItem(
                    name: "start_date", value: start.addingTimeInterval(-WeatherLookup.wetBefore).formatted(day)),
                URLQueryItem(name: "end_date", value: end.addingTimeInterval(3600).formatted(day)),
                URLQueryItem(name: "hourly", value: "temperature_2m,precipitation,cloud_cover"),
                URLQueryItem(name: "timezone", value: "GMT"),
                URLQueryItem(name: "timeformat", value: "unixtime"),
            ]
            // Every part above is a plain host, path and query, so this always makes a URL.
            return components.url ?? URL(filePath: "/")
        }
    }

    /// The hourly record as the API returns it: each `precipitation` is the hour up to its time,
    /// each temperature and cloud cover is at its time.
    public struct Hourly: Equatable, Sendable {
        public var time: [Date]
        public var temperature: [Double?]
        public var precipitation: [Double?]
        public var cloudCover: [Double?]

        public init(time: [Date], temperature: [Double?], precipitation: [Double?], cloudCover: [Double?]) {
            self.time = time
            self.temperature = temperature
            self.precipitation = precipitation
            self.cloudCover = cloudCover
        }
    }

    public enum Failure: Error, Equatable {
        /// Not the answer to this question: no hourly record in it.
        case unreadable
    }

    /// The record in an API response.
    public static func parse(_ data: Data) throws -> Hourly {
        guard let series = (try? JSONDecoder().decode(OpenMeteoResponse.self, from: data))?.hourly, !series.time.isEmpty
        else { throw Failure.unreadable }
        let count = series.time.count
        func padded(_ values: [Double?]?) -> [Double?] {
            let values = values ?? []
            return (0..<count).map { $0 < values.count ? values[$0] : nil }
        }
        return Hourly(
            time: series.time.map { Date(timeIntervalSince1970: $0) }, temperature: padded(series.temperature),
            precipitation: padded(series.precipitation), cloudCover: padded(series.cloudCover))
    }

    /// What the record says of a session: each `nil` when the record does not cover it.
    public struct Reading: Equatable, Sendable {
        public var airCelsius: Double?
        public var weather: SessionConditions.Weather?
        public var track: SessionConditions.Track?

        public init(
            airCelsius: Double? = nil, weather: SessionConditions.Weather? = nil, track: SessionConditions.Track? = nil
        ) {
            self.airCelsius = airCelsius
            self.weather = weather
            self.track = track
        }
    }

    /// An hour with this much is a wet hour.
    static let wetHour = 0.1
    /// This much over the session leaves the surface wet rather than damp.
    static let wetSurface = 0.5

    /// The air at the middle of the session; the sky across it (rain in every hour, in some, or
    /// by its cloud); the surface from rain in it or in the six hours before.
    public static func reading(of hourly: Hourly, for request: Request) -> Reading {
        let start = request.start
        let end = request.end
        var reading = Reading()
        reading.airCelsius = temperature(in: hourly, at: start.addingTimeInterval(end.timeIntervalSince(start) / 2))
            .map { ($0 * 10).rounded() / 10 }
        // Each hour's rain is up to its time: the hours that overlap the session, and those before.
        let during = hourly.time.indices.filter {
            hourly.time[$0] > start && hourly.time[$0].addingTimeInterval(-3600) < end
        }
        let before = hourly.time.indices.filter {
            hourly.time[$0] <= start && hourly.time[$0] > start.addingTimeInterval(-wetBefore)
        }
        let rain = during.compactMap { hourly.precipitation[$0] }
        guard !rain.isEmpty else { return reading }
        let wetHours = rain.filter { $0 >= wetHour }.count
        let total = rain.reduce(0, +)
        if wetHours == rain.count {
            reading.weather = .rain
        } else if wetHours > 0 {
            reading.weather = .mixed
        } else {
            let cloud = during.compactMap { hourly.cloudCover[$0] }
            if !cloud.isEmpty {
                let mean = cloud.reduce(0, +) / Double(cloud.count)
                reading.weather = mean < 30 ? .sunny : mean < 70 ? .cloudy : .overcast
            }
        }
        let earlier = before.compactMap { hourly.precipitation[$0] }.reduce(0, +)
        if total >= wetSurface {
            reading.track = .wet
        } else if wetHours > 0 || earlier >= 0.2 {
            reading.track = .damp
        } else {
            reading.track = .dry
        }
        return reading
    }

    /// The temperature at `date`, between the two hours either side of it.
    static func temperature(in hourly: Hourly, at date: Date) -> Double? {
        let known = hourly.time.indices.compactMap { index in
            hourly.temperature[index].map { (hourly.time[index], $0) }
        }
        // Not a reading of a time the record does not reach.
        guard let first = known.first?.0, let last = known.last?.0,
            date >= first.addingTimeInterval(-3600), date <= last.addingTimeInterval(3600)
        else { return nil }
        guard let after = known.firstIndex(where: { $0.0 >= date }) else { return known.last?.1 }
        guard after > 0 else { return known[after].1 }
        let (t0, v0) = known[after - 1]
        let (t1, v1) = known[after]
        let span = t1.timeIntervalSince(t0)
        guard span > 0 else { return v1 }
        return v0 + (v1 - v0) * date.timeIntervalSince(t0) / span
    }

    /// Where a session was driven, without reading its file: its circuit's place, else the start of
    /// its course. `nil` when neither is known; the app then reads the file.
    public static func place(of entry: LogbookEntry) -> (latitude: Double, longitude: Double)? {
        if let id = entry.circuitID, let circuit = CircuitCatalog.circuit(id: id) {
            return (circuit.latitude, circuit.longitude)
        }
        return entry.coursePath.first.map { ($0.latitude, $0.longitude) }
    }
}

extension SessionConditions {
    /// Fills whichever of the weather, the surface and the air the driver left empty from
    /// `reading`, and notes them as looked up. Returns whether anything was filled.
    @discardableResult
    public mutating func fill(from reading: WeatherLookup.Reading) -> Bool {
        var filled = false
        if weather == nil, let value = reading.weather {
            weather = value
            lookedUp.insert(.weather)
            filled = true
        }
        if track == nil, let value = reading.track {
            track = value
            lookedUp.insert(.track)
            filled = true
        }
        if ambientCelsius == nil, let value = reading.airCelsius {
            ambientCelsius = value
            lookedUp.insert(.air)
            filled = true
        }
        return filled
    }

    /// These conditions as the driver set them over `old`: a looked-up field they changed is
    /// theirs now.
    public func keepingLookups(from old: SessionConditions) -> SessionConditions {
        var kept = self
        if weather != old.weather { kept.lookedUp.remove(.weather) }
        if track != old.track { kept.lookedUp.remove(.track) }
        if ambientCelsius != old.ambientCelsius { kept.lookedUp.remove(.air) }
        return kept
    }

    /// Whether any field the weather lookup fills is empty.
    public var lacksWeather: Bool { weather == nil || track == nil || ambientCelsius == nil }
}

/// An Open-Meteo answer, as far as the lookup reads it.
private struct OpenMeteoResponse: Decodable {
    let hourly: OpenMeteoSeries?
}

private struct OpenMeteoSeries: Decodable {
    let time: [Double]
    let temperature: [Double?]?
    let precipitation: [Double?]?
    let cloudCover: [Double?]?

    enum CodingKeys: String, CodingKey {
        case time, precipitation
        case temperature = "temperature_2m"
        case cloudCover = "cloud_cover"
    }
}

extension URL {
    /// Open-Meteo's own page, which the credit links to.
    fileprivate var openMeteo: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "open-meteo.com"
        components.path = "/"
        return components.url ?? self
    }
}
