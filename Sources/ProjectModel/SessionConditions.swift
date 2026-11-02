import Foundation

/// What the logger does not record (#348): the weather, the track, the temperature, the tyres
/// and the setup — the half of a session's record that makes a 1:56 mean something six months
/// later. Every part optional; the summary says what was filled in.
public struct SessionConditions: Hashable, Codable, Sendable {
    public enum Weather: String, Codable, CaseIterable, Sendable {
        case sunny, cloudy, overcast, rain, mixed

        public var displayName: String {
            switch self {
            case .sunny: "Sunny"
            case .cloudy: "Cloudy"
            case .overcast: "Overcast"
            case .rain: "Rain"
            case .mixed: "Mixed"
            }
        }
    }

    public enum Track: String, Codable, CaseIterable, Sendable {
        case dry, damp, wet, drying, greasy

        public var displayName: String {
            switch self {
            case .dry: "Dry"
            case .damp: "Damp"
            case .wet: "Wet"
            case .drying: "Drying"
            case .greasy: "Greasy"
            }
        }
    }

    public var weather: Weather?
    public var track: Track?
    /// Air temperature, °C.
    public var ambientCelsius: Double?
    public var tyres: String
    public var setup: String

    public init(
        weather: Weather? = nil, track: Track? = nil, ambientCelsius: Double? = nil, tyres: String = "",
        setup: String = ""
    ) {
        self.weather = weather
        self.track = track
        self.ambientCelsius = ambientCelsius
        self.tyres = tyres
        self.setup = setup
    }

    public var isEmpty: Bool {
        weather == nil && track == nil && ambientCelsius == nil && tyres.isEmpty && setup.isEmpty
    }

    /// "Sunny · Dry · 24 °C · RE-71RS", with only what was filled in; empty when nothing was.
    public var summary: String {
        var parts: [String] = []
        if let weather { parts.append(weather.displayName) }
        if let track { parts.append(track.displayName) }
        if let ambientCelsius { parts.append("\(Int(ambientCelsius.rounded())) °C") }
        if !tyres.isEmpty { parts.append(tyres) }
        return parts.joined(separator: " · ")
    }

    private enum CodingKeys: String, CodingKey { case weather, track, ambientCelsius, tyres, setup }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        weather = try? c.decodeIfPresent(Weather.self, forKey: .weather)
        track = try? c.decodeIfPresent(Track.self, forKey: .track)
        ambientCelsius = try c.decodeIfPresent(Double.self, forKey: .ambientCelsius)
        tyres = try c.decodeIfPresent(String.self, forKey: .tyres) ?? ""
        setup = try c.decodeIfPresent(String.self, forKey: .setup) ?? ""
    }
}
