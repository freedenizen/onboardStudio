import Foundation

/// What was on the car for a session (#559): tyre pressures at each corner, cold, hot and how much
/// was bled, the alignment, the dampers, the bars and the wing. Every part optional: a driver who
/// notes only the cold pressures has a sheet with only those.
///
/// Pressures are kept in kilopascals and ride heights in millimetres, whatever they were typed in,
/// so two sessions can be compared; toe is kept as typed, with its unit, since drivers measure it
/// in millimetres, inches or degrees and none converts to another without the wheel's size.
public struct SetupSheet: Hashable, Codable, Sendable {
    /// One number at each wheel.
    public struct Corners: Hashable, Codable, Sendable {
        public var frontLeft: Double?
        public var frontRight: Double?
        public var rearLeft: Double?
        public var rearRight: Double?

        public init(
            frontLeft: Double? = nil, frontRight: Double? = nil, rearLeft: Double? = nil, rearRight: Double? = nil
        ) {
            self.frontLeft = frontLeft
            self.frontRight = frontRight
            self.rearLeft = rearLeft
            self.rearRight = rearRight
        }

        public var isEmpty: Bool { values.allSatisfy { $0 == nil } }
        /// Front left, front right, rear left, rear right.
        public var values: [Double?] { [frontLeft, frontRight, rearLeft, rearRight] }
    }

    /// One number at each end of the car.
    public struct Axles: Hashable, Codable, Sendable {
        public var front: Double?
        public var rear: Double?

        public init(front: Double? = nil, rear: Double? = nil) {
            self.front = front
            self.rear = rear
        }

        public var isEmpty: Bool { front == nil && rear == nil }
    }

    /// A setting at each end of the car that is not a number: "hole 2", "full soft".
    public struct AxleSettings: Hashable, Codable, Sendable {
        public var front: String
        public var rear: String

        public init(front: String = "", rear: String = "") {
            self.front = front
            self.rear = rear
        }

        public var isEmpty: Bool { front.isEmpty && rear.isEmpty }
    }

    public enum ToeUnit: String, Codable, CaseIterable, Sendable {
        case millimeters, inches, degrees

        public var symbol: String {
            switch self {
            case .millimeters: "mm"
            case .inches: "in"
            case .degrees: "°"
            }
        }
    }

    /// The saved setup this one was loaded from (#559), kept when a value is changed after, so a
    /// session reads "Base, 2 psi less at the rear" rather than as a setup of its own.
    public var name: String
    /// kPa.
    public var coldPressure: Corners
    /// kPa, after the session.
    public var hotPressure: Corners
    /// kPa let out during or after the session.
    public var bled: Corners
    /// Degrees; negative leans the top of the wheel in.
    public var camber: Corners
    /// Per axle, in `toeUnit`; negative is toe-out.
    public var toe: Axles
    public var toeUnit: ToeUnit
    /// mm.
    public var rideHeight: Axles
    /// Clicks.
    public var bump: Axles
    /// Clicks.
    public var rebound: Axles
    public var antiRollBar: AxleSettings
    public var wing: String

    public init(
        name: String = "", coldPressure: Corners = Corners(), hotPressure: Corners = Corners(),
        bled: Corners = Corners(), camber: Corners = Corners(), toe: Axles = Axles(),
        toeUnit: ToeUnit = .millimeters, rideHeight: Axles = Axles(), bump: Axles = Axles(),
        rebound: Axles = Axles(), antiRollBar: AxleSettings = AxleSettings(), wing: String = ""
    ) {
        self.name = name
        self.coldPressure = coldPressure
        self.hotPressure = hotPressure
        self.bled = bled
        self.camber = camber
        self.toe = toe
        self.toeUnit = toeUnit
        self.rideHeight = rideHeight
        self.bump = bump
        self.rebound = rebound
        self.antiRollBar = antiRollBar
        self.wing = wing
    }

    /// Nothing noted, not even a name.
    public var isEmpty: Bool { name.isEmpty && hasNoValues }

    /// No value noted, whatever it is called.
    public var hasNoValues: Bool {
        coldPressure.isEmpty && hotPressure.isEmpty && bled.isEmpty && camber.isEmpty && toe.isEmpty
            && rideHeight.isEmpty && bump.isEmpty && rebound.isEmpty && antiRollBar.isEmpty && wing.isEmpty
    }

    /// The same values, whatever the sheet is called: what "unchanged from the saved setup" means.
    public func sameValues(as other: SetupSheet) -> Bool {
        var mine = self
        mine.name = other.name
        return mine == other
    }

    private enum CodingKeys: String, CodingKey {
        case name, coldPressure, hotPressure, bled, camber, toe, toeUnit, rideHeight, bump, rebound, antiRollBar, wing
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        coldPressure = try c.decodeIfPresent(Corners.self, forKey: .coldPressure) ?? Corners()
        hotPressure = try c.decodeIfPresent(Corners.self, forKey: .hotPressure) ?? Corners()
        bled = try c.decodeIfPresent(Corners.self, forKey: .bled) ?? Corners()
        camber = try c.decodeIfPresent(Corners.self, forKey: .camber) ?? Corners()
        toe = try c.decodeIfPresent(Axles.self, forKey: .toe) ?? Axles()
        // A unit a later build adds reads as the usual one rather than failing the session.
        toeUnit = (try? c.decodeIfPresent(ToeUnit.self, forKey: .toeUnit)) ?? .millimeters
        rideHeight = try c.decodeIfPresent(Axles.self, forKey: .rideHeight) ?? Axles()
        bump = try c.decodeIfPresent(Axles.self, forKey: .bump) ?? Axles()
        rebound = try c.decodeIfPresent(Axles.self, forKey: .rebound) ?? Axles()
        antiRollBar = try c.decodeIfPresent(AxleSettings.self, forKey: .antiRollBar) ?? AxleSettings()
        wing = try c.decodeIfPresent(String.self, forKey: .wing) ?? ""
    }
}

/// A setup kept with a car (#559), to load onto a session rather than type again; the one marked
/// as the car's starting setup goes onto every new session in it that has none.
public struct SavedSetup: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    /// The tyre set, as the session's Tyres line has it; empty leaves a session's own alone.
    public var tyres: String
    public var sheet: SetupSheet

    public init(id: UUID = UUID(), name: String, tyres: String = "", sheet: SetupSheet = SetupSheet()) {
        self.id = id
        self.name = name
        self.tyres = tyres
        self.sheet = sheet
    }

    private enum CodingKeys: String, CodingKey { case id, name, tyres, sheet }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        tyres = try c.decodeIfPresent(String.self, forKey: .tyres) ?? ""
        sheet = try c.decodeIfPresent(SetupSheet.self, forKey: .sheet) ?? SetupSheet()
    }
}

extension SessionConditions {
    /// This saved setup on the session: its values under its name, and its tyres when it names some.
    public mutating func load(_ saved: SavedSetup) {
        sheet = saved.sheet
        sheet.name = saved.name
        if !saved.tyres.isEmpty { tyres = saved.tyres }
    }
}
