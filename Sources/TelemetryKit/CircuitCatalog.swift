import Foundation

/// A motorsport circuit from the bundled list.
public struct Circuit: Sendable, Hashable, Codable, Identifiable {
    /// Wikidata item id (`Q112563`). Stable across name changes, which circuits do often —
    /// Laguna Seca has been renamed twice by sponsors — so this is what a saved reference uses.
    public let id: String
    public let name: String
    public let latitude: Double
    public let longitude: Double
    /// ISO 3166-1 alpha-2, empty when Wikidata records no country.
    public let country: String

    public init(id: String, name: String, latitude: Double, longitude: Double, country: String = "") {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.country = country
    }

    public var displayName: String { country.isEmpty ? name : "\(name) (\(country))" }
}

/// Works out which circuit a session was recorded at.
///
/// The list is Wikidata's motorsport racing tracks (`wdt:P31/wdt:P279* wd:Q2338524`): 1,290 venues
/// with a name, a coordinate and a country, **CC0**, so it carries no attribution obligation and
/// no share-alike. It holds one point per circuit and no geometry — which is all that is needed,
/// because the outline comes from the driver's own laps.
///
/// OpenStreetMap was evaluated and rejected for the geometry; `docs/tracks-and-sectors.md` records
/// why. Nothing here queries the network: the list ships with the app and is never fetched.
public enum CircuitCatalog {
    /// Every circuit in the bundled list, in the order the file has them (by name).
    public static let all: [Circuit] = load()

    /// A circuit the session might have been recorded at.
    public struct Match: Sendable, Hashable {
        public let circuit: Circuit
        /// Kilometres from the session's centroid to the circuit's coordinate.
        public let distanceKm: Double
        /// How far away the next nearest circuit was. `nil` when there is no second candidate.
        ///
        /// This is what says whether a match is safe: on the reference session Sonoma is 0.27 km
        /// away and the runner-up 91.5 km, a margin no coincidence produces.
        public let runnerUpKm: Double?
        /// Whether the file's own track name agrees with the circuit's.
        public let nameAgrees: Bool

        /// Whether the match stands out from its rivals, which is what decides between telling
        /// the driver where they were and asking them.
        ///
        /// The Isle of Man's Clypse, Four Inch and Highroads courses share a single coordinate,
        /// and Wikidata lists several other venues twice under different names; a nearest-point
        /// match between those is a coin toss and should say so. The file's own track name
        /// settles it when there is one.
        public var isConfident: Bool {
            if nameAgrees { return true }
            guard let runnerUpKm else { return true }
            return runnerUpKm > max(distanceKm * 10, 1)
        }

        public init(circuit: Circuit, distanceKm: Double, runnerUpKm: Double?, nameAgrees: Bool) {
            self.circuit = circuit
            self.distanceKm = distanceKm
            self.runnerUpKm = runnerUpKm
            self.nameAgrees = nameAgrees
        }
    }

    /// A session's mean position. `nil` without latitude and longitude channels.
    ///
    /// A plain mean is enough: a session's bounding box was measured at 96% circuit, so the
    /// centroid lands inside the track however the laps are distributed.
    public static func centroid(of session: TelemetrySession) -> (latitude: Double, longitude: Double)? {
        guard let latitude = session[.latitude], let longitude = session[.longitude],
            !latitude.isEmpty, !longitude.isEmpty
        else { return nil }
        let meanLatitude = latitude.values.reduce(0, +) / Double(latitude.count)
        let meanLongitude = longitude.values.reduce(0, +) / Double(longitude.count)
        guard meanLatitude.isFinite, meanLongitude.isFinite else { return nil }
        return (meanLatitude, meanLongitude)
    }

    /// The circuit `session` was recorded at, or `nil` when it has no position or nothing is
    /// within `maxDistanceKm`.
    ///
    /// Distance decides and the file's track name only confirms — except when a *further*
    /// candidate inside the radius is the one the file names, which is how a venue with several
    /// layouts listed separately resolves to the one the driver says they drove.
    public static func identify(_ session: TelemetrySession, maxDistanceKm: Double = 10) -> Match? {
        guard let centre = centroid(of: session) else { return nil }
        return identify(
            latitude: centre.latitude, longitude: centre.longitude, trackName: session.info.trackName,
            maxDistanceKm: maxDistanceKm)
    }

    public static func identify(
        latitude: Double, longitude: Double, trackName: String? = nil, maxDistanceKm: Double = 10
    ) -> Match? {
        identify(in: all, latitude: latitude, longitude: longitude, trackName: trackName, maxDistanceKm: maxDistanceKm)
    }

    static func identify(
        in circuits: [Circuit], latitude: Double, longitude: Double, trackName: String?, maxDistanceKm: Double
    ) -> Match? {
        let ranked =
            circuits
            .map { (circuit: $0, km: distanceKm(latitude, longitude, $0.latitude, $0.longitude)) }
            .sorted { $0.km < $1.km }
        guard let nearest = ranked.first, nearest.km <= maxDistanceKm else { return nil }
        let runnerUp = ranked.dropFirst().first?.km
        let named = ranked.prefix { $0.km <= maxDistanceKm }.first { names(trackName, match: $0.circuit.name) }
        let chosen = named ?? nearest
        return Match(
            circuit: chosen.circuit, distanceKm: chosen.km, runnerUpKm: runnerUp,
            nameAgrees: names(trackName, match: chosen.circuit.name))
    }

    /// How `session` sits against a circuit that has already been chosen — by the driver, or
    /// recorded in the project — rather than against the nearest one.
    ///
    /// There is no runner-up here: nothing was ranked. A decision already made is not a guess,
    /// so it reports as confident.
    public static func match(_ circuit: Circuit, to session: TelemetrySession) -> Match {
        let centre = centroid(of: session)
        let km = centre.map { distanceKm($0.latitude, $0.longitude, circuit.latitude, circuit.longitude) } ?? 0
        return Match(
            circuit: circuit, distanceKm: km, runnerUpKm: nil,
            nameAgrees: names(session.info.trackName, match: circuit.name))
    }

    /// Circuits whose name contains `query`, for a correction list. Empty query returns nothing
    /// rather than all 1,290.
    public static func search(_ query: String, limit: Int = 25) -> [Circuit] {
        let needle = normalised(query)
        guard !needle.isEmpty else { return [] }
        return Array(all.filter { normalised($0.name).contains(needle) }.prefix(limit))
    }

    public static func circuit(id: String) -> Circuit? { all.first { $0.id == id } }

    // MARK: - Names

    /// Whether a file's track name and a circuit's name are talking about the same place.
    ///
    /// Loggers record what the driver typed or what their own list called it — "Sonoma" for
    /// "Sonoma Raceway", "Spa" for "Circuit de Spa-Francorchamps" — so either containing the
    /// other counts, once punctuation and case are out of the way. A name is never enough on its
    /// own here; it only confirms a coordinate.
    static func names(_ fileName: String?, match circuitName: String) -> Bool {
        guard let fileName else { return false }
        let a = normalised(fileName)
        let b = normalised(circuitName)
        guard a.count >= 3, b.count >= 3 else { return false }
        return a.contains(b) || b.contains(a)
    }

    /// Lowercased, accents folded, and everything but letters and digits removed, so
    /// "Circuit de Spa-Francorchamps" and "circuit de spa francorchamps" are the same string.
    static func normalised(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
            .reduce(into: "") { $0.unicodeScalars.append($1) }
    }

    // MARK: - Distance

    /// Great-circle distance in kilometres.
    static func distanceKm(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        DerivedChannels.distance(lat1: lat1, lon1: lon1, lat2: lat2, lon2: lon2) / 1000
    }

    // MARK: - Loading

    /// Parses `circuits.csv` once. A row that does not parse is skipped rather than throwing:
    /// a damaged list should cost circuit identification, not the ability to open a file.
    static func load() -> [Circuit] {
        guard let url = Bundle.module.url(forResource: "circuits", withExtension: "csv"),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else { return [] }
        return parse(text)
    }

    static func parse(_ text: String) -> [Circuit] {
        var result: [Circuit] = []
        for line in text.components(separatedBy: .newlines).dropFirst() where !line.isEmpty {
            let fields = splitCSV(line)
            guard fields.count >= 4, let latitude = Double(fields[2]), let longitude = Double(fields[3]),
                !fields[0].isEmpty, !fields[1].isEmpty
            else { continue }
            result.append(
                Circuit(
                    id: fields[0], name: fields[1], latitude: latitude, longitude: longitude,
                    country: fields.count > 4 ? fields[4] : ""))
        }
        return result
    }

    /// One CSV line, honouring the doubled-quote escaping the list uses for names with commas.
    static func splitCSV(_ line: String) -> [String] {
        var fields: [String] = []
        var field = ""
        var inQuotes = false
        var characters = Array(line)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                if inQuotes, index + 1 < characters.count, characters[index + 1] == "\"" {
                    field.append("\"")
                    index += 1
                } else {
                    inQuotes.toggle()
                }
            } else if character == "," && !inQuotes {
                fields.append(field)
                field = ""
            } else {
                field.append(character)
            }
            index += 1
        }
        fields.append(field)
        return fields
    }
}
