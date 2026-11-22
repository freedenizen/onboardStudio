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
    /// The tyre set: compound, age, which set.
    public var tyres: String
    /// What was changed, in the driver's words.
    public var setup: String
    /// What was on the car, value by value (#559).
    public var sheet: SetupSheet
    /// Which of the weather, the surface and the air came from the weather record (#560) and not
    /// from the driver; empty for a session noted by hand.
    public var lookedUp: Set<LookedUp> = []

    public enum LookedUp: String, Codable, CaseIterable, Sendable { case weather, track, air }

    public init(
        weather: Weather? = nil, track: Track? = nil, ambientCelsius: Double? = nil, tyres: String = "",
        setup: String = "", sheet: SetupSheet = SetupSheet()
    ) {
        self.weather = weather
        self.track = track
        self.ambientCelsius = ambientCelsius
        self.tyres = tyres
        self.setup = setup
        self.sheet = sheet
    }

    public var isEmpty: Bool {
        weather == nil && track == nil && ambientCelsius == nil && tyres.isEmpty && setup.isEmpty && sheet.isEmpty
    }

    /// No tyres and no setup noted: a car's starting setup may go onto it (#559).
    public var hasNoSetup: Bool { tyres.isEmpty && sheet.isEmpty }

    /// "Sunny · Dry · 24 °C · RE-71RS · Base", with only what was filled in; empty when nothing was.
    public var summary: String {
        var parts: [String] = []
        if let weather { parts.append(weather.displayName) }
        if let track { parts.append(track.displayName) }
        if let ambientCelsius { parts.append("\(Int(ambientCelsius.rounded())) °C") }
        if !tyres.isEmpty { parts.append(tyres) }
        if !sheet.name.isEmpty { parts.append(sheet.name) }
        return parts.joined(separator: " · ")
    }

    private enum CodingKeys: String, CodingKey { case weather, track, ambientCelsius, tyres, setup, sheet, lookedUp }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        weather = try? c.decodeIfPresent(Weather.self, forKey: .weather)
        track = try? c.decodeIfPresent(Track.self, forKey: .track)
        ambientCelsius = try c.decodeIfPresent(Double.self, forKey: .ambientCelsius)
        tyres = try c.decodeIfPresent(String.self, forKey: .tyres) ?? ""
        setup = try c.decodeIfPresent(String.self, forKey: .setup) ?? ""
        sheet = try c.decodeIfPresent(SetupSheet.self, forKey: .sheet) ?? SetupSheet()
        // Absent before #560, and for anything noted by hand. An unknown field is skipped.
        let names = (try? c.decodeIfPresent([String].self, forKey: .lookedUp)) ?? []
        lookedUp = Set(names.compactMap(LookedUp.init(rawValue:)))
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(weather, forKey: .weather)
        try c.encodeIfPresent(track, forKey: .track)
        try c.encodeIfPresent(ambientCelsius, forKey: .ambientCelsius)
        try c.encode(tyres, forKey: .tyres)
        try c.encode(setup, forKey: .setup)
        // A session with no sheet is written as an earlier build wrote it.
        if !sheet.isEmpty { try c.encode(sheet, forKey: .sheet) }
        if !lookedUp.isEmpty { try c.encode(lookedUp.map(\.rawValue).sorted(), forKey: .lookedUp) }
    }
}
