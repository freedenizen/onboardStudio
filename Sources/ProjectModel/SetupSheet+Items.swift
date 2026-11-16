import Foundation

/// The units a setup sheet is typed and read in (#559): tyre pressures in psi, bar or kPa, and
/// ride heights in millimetres or inches. What is kept does not change with them.
public struct SetupUnits: Hashable, Sendable {
    public enum Pressure: String, CaseIterable, Sendable {
        case psi, bar, kilopascals

        public var symbol: String {
            switch self {
            case .psi: "psi"
            case .bar: "bar"
            case .kilopascals: "kPa"
            }
        }

        public func fromKilopascals(_ value: Double) -> Double {
            switch self {
            case .psi: value / 6.894_757
            case .bar: value / 100
            case .kilopascals: value
            }
        }

        /// To kilopascals, to a tenth of one, so a pressure typed twice in psi is the same twice.
        public func toKilopascals(_ value: Double) -> Double {
            let kilopascals =
                switch self {
                case .psi: value * 6.894_757
                case .bar: value * 100
                case .kilopascals: value
                }
            return (kilopascals * 10).rounded() / 10
        }

        /// psi to a tenth, bar to a hundredth, kPa whole, as gauges read.
        public var decimals: Int {
            switch self {
            case .psi: 1
            case .bar: 2
            case .kilopascals: 0
            }
        }
    }

    public enum Length: String, CaseIterable, Sendable {
        case millimeters, inches

        public var symbol: String { self == .millimeters ? "mm" : "in" }
        public func fromMillimeters(_ value: Double) -> Double { self == .millimeters ? value : value / 25.4 }
        public func toMillimeters(_ value: Double) -> Double {
            self == .millimeters ? value : (value * 25.4 * 10).rounded() / 10
        }
        public var decimals: Int { self == .millimeters ? 0 : 2 }
    }

    public var pressure: Pressure
    public var length: Length

    public init(pressure: Pressure, length: Length) {
        self.pressure = pressure
        self.length = length
    }

    /// psi and inches where the speed is in miles an hour, bar and millimetres elsewhere.
    public static func following(imperial: Bool) -> SetupUnits {
        imperial ? SetupUnits(pressure: .psi, length: .inches) : SetupUnits(pressure: .bar, length: .millimeters)
    }
}

/// One value on a setup sheet (#559): what it is called, and how it reads. Trends splits sessions by
/// any one of them, and the sheet's summary counts them.
public enum SetupItem: Hashable, Sendable {
    public enum Corner: Int, CaseIterable, Sendable {
        case frontLeft, frontRight, rearLeft, rearRight

        public var title: String {
            switch self {
            case .frontLeft: "Front Left"
            case .frontRight: "Front Right"
            case .rearLeft: "Rear Left"
            case .rearRight: "Rear Right"
            }
        }

        public var keyPath: WritableKeyPath<SetupSheet.Corners, Double?> {
            switch self {
            case .frontLeft: \.frontLeft
            case .frontRight: \.frontRight
            case .rearLeft: \.rearLeft
            case .rearRight: \.rearRight
            }
        }
    }

    public enum Axle: Int, CaseIterable, Sendable {
        case front, rear

        public var title: String { self == .front ? "Front" : "Rear" }
        public var keyPath: WritableKeyPath<SetupSheet.Axles, Double?> { self == .front ? \.front : \.rear }
        public var settingKeyPath: WritableKeyPath<SetupSheet.AxleSettings, String> {
            self == .front ? \.front : \.rear
        }
    }

    case coldPressure(Corner)
    case hotPressure(Corner)
    case bled(Corner)
    case camber(Corner)
    case toe(Axle)
    case rideHeight(Axle)
    case bump(Axle)
    case rebound(Axle)
    case antiRollBar(Axle)
    case wing

    /// Every value, in the order the sheet shows them.
    public static let all: [SetupItem] =
        Corner.allCases.map(coldPressure) + Corner.allCases.map(hotPressure) + Corner.allCases.map(bled)
        + Corner.allCases.map(camber) + Axle.allCases.map(toe) + Axle.allCases.map(rideHeight)
        + Axle.allCases.map(bump) + Axle.allCases.map(rebound) + Axle.allCases.map(antiRollBar) + [wing]

    /// "Cold Pressure, Front Left".
    public var title: String {
        switch self {
        case .coldPressure(let corner): "Cold Pressure, \(corner.title)"
        case .hotPressure(let corner): "Hot Pressure, \(corner.title)"
        case .bled(let corner): "Bled, \(corner.title)"
        case .camber(let corner): "Camber, \(corner.title)"
        case .toe(let axle): "Toe, \(axle.title)"
        case .rideHeight(let axle): "Ride Height, \(axle.title)"
        case .bump(let axle): "Bump, \(axle.title)"
        case .rebound(let axle): "Rebound, \(axle.title)"
        case .antiRollBar(let axle): "Anti-Roll Bar, \(axle.title)"
        case .wing: "Wing"
        }
    }

    /// The number as kept (kPa, mm, degrees, clicks, toe in its own unit); `nil` for a setting in words.
    public func number(in sheet: SetupSheet) -> Double? {
        switch self {
        case .coldPressure(let corner): sheet.coldPressure[keyPath: corner.keyPath]
        case .hotPressure(let corner): sheet.hotPressure[keyPath: corner.keyPath]
        case .bled(let corner): sheet.bled[keyPath: corner.keyPath]
        case .camber(let corner): sheet.camber[keyPath: corner.keyPath]
        case .toe(let axle): sheet.toe[keyPath: axle.keyPath]
        case .rideHeight(let axle): sheet.rideHeight[keyPath: axle.keyPath]
        case .bump(let axle): sheet.bump[keyPath: axle.keyPath]
        case .rebound(let axle): sheet.rebound[keyPath: axle.keyPath]
        case .antiRollBar, .wing: nil
        }
    }

    /// How the value reads: "30.5 psi", "−2.5°", "12 clicks", "Hole 2"; `nil` when not noted.
    public func text(in sheet: SetupSheet, units: SetupUnits) -> String? {
        switch self {
        case .antiRollBar(let axle):
            let setting = sheet.antiRollBar[keyPath: axle.settingKeyPath]
            return setting.isEmpty ? nil : setting
        case .wing: return sheet.wing.isEmpty ? nil : sheet.wing
        default: break
        }
        guard let value = number(in: sheet) else { return nil }
        switch self {
        case .coldPressure, .hotPressure, .bled:
            let pressure = units.pressure
            return "\(Self.format(pressure.fromKilopascals(value), pressure.decimals)) \(pressure.symbol)"
        case .camber: return "\(Self.format(value, 2))°"
        case .toe:
            let unit = sheet.toeUnit
            return unit == .degrees ? "\(Self.format(value, 2))°" : "\(Self.format(value, 2)) \(unit.symbol)"
        case .rideHeight:
            return "\(Self.format(units.length.fromMillimeters(value), units.length.decimals)) \(units.length.symbol)"
        case .bump, .rebound:
            let clicks = Self.format(value, 1)
            return "\(clicks) click\(clicks == "1" ? "" : "s")"
        case .antiRollBar, .wing: return nil
        }
    }

    /// What two sheets are compared by: the value as kept, the same whatever it is shown in.
    public func key(in sheet: SetupSheet) -> String? {
        switch self {
        case .antiRollBar, .wing: text(in: sheet, units: .following(imperial: false))?.lowercased()
        case .toe: number(in: sheet).map { "\($0) \(sheet.toeUnit.rawValue)" }
        default: number(in: sheet).map { "\($0)" }
        }
    }

    /// Up to `decimals` places, without trailing zeros; a minus sign rather than a hyphen.
    public static func format(_ value: Double, _ decimals: Int) -> String {
        var text = String(format: "%.\(decimals)f", value)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        if text == "-0" { text = "0" }
        return text.replacingOccurrences(of: "-", with: "−")
    }
}

extension SetupSheet {
    /// The values noted, in the sheet's order.
    public var notedItems: [SetupItem] { SetupItem.all.filter { $0.key(in: self) != nil } }

    /// "Base · 2.1/1.9 bar cold · 6 more", with only what was noted; empty when nothing was.
    public func summary(units: SetupUnits) -> String {
        var parts: [String] = []
        if !name.isEmpty { parts.append(name) }
        var counted = notedItems
        let cold = SetupItem.Corner.allCases.map { coldPressure[keyPath: $0.keyPath] }
        if cold.contains(where: { $0 != nil }) {
            let shown = cold.map {
                $0.map { SetupItem.format(units.pressure.fromKilopascals($0), units.pressure.decimals) }
            }
            // One figure an axle when both sides match; else every corner.
            let text =
                shown[0] == shown[1] && shown[2] == shown[3]
                ? [shown[0], shown[2]].map { $0 ?? "–" }.joined(separator: "/")
                : shown.map { $0 ?? "–" }.joined(separator: "/")
            parts.append("\(text) \(units.pressure.symbol) cold")
            counted.removeAll { if case .coldPressure = $0 { true } else { false } }
        }
        if !counted.isEmpty { parts.append(parts.isEmpty ? "\(counted.count) values" : "\(counted.count) more") }
        return parts.joined(separator: " · ")
    }
}

extension SetupItem {
    /// The value as a field shows it for editing: the number in `units`, without its symbol.
    public func editText(in sheet: SetupSheet, units: SetupUnits) -> String {
        switch self {
        case .antiRollBar, .wing: return text(in: sheet, units: units) ?? ""
        default: break
        }
        guard let value = number(in: sheet) else { return "" }
        let shown =
            switch self {
            // A place finer than a gauge reads, so what was typed comes back as it was typed.
            case .coldPressure, .hotPressure, .bled:
                SetupItem.format(units.pressure.fromKilopascals(value), units.pressure.decimals + 1)
            case .rideHeight: SetupItem.format(units.length.fromMillimeters(value), units.length.decimals + 1)
            default: SetupItem.format(value, 3)
            }
        return shown.replacingOccurrences(of: "−", with: "-")
    }

    /// Writes what was typed into `sheet`; empty clears it. Returns `false`, leaving the sheet as it
    /// was, for a number that is not one.
    @discardableResult
    public func set(_ typed: String, in sheet: inout SetupSheet, units: SetupUnits) -> Bool {
        let trimmed = typed.trimmingCharacters(in: .whitespaces)
        switch self {
        case .antiRollBar(let axle):
            sheet.antiRollBar[keyPath: axle.settingKeyPath] = trimmed
            return true
        case .wing:
            sheet.wing = trimmed
            return true
        default: break
        }
        var number: Double?
        if !trimmed.isEmpty {
            let normalised = trimmed.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: "−", with: "-")
            guard let value = Double(normalised), value.isFinite else { return false }
            number = value
        }
        switch self {
        case .coldPressure(let corner):
            sheet.coldPressure[keyPath: corner.keyPath] = number.map(units.pressure.toKilopascals)
        case .hotPressure(let corner):
            sheet.hotPressure[keyPath: corner.keyPath] = number.map(units.pressure.toKilopascals)
        case .bled(let corner): sheet.bled[keyPath: corner.keyPath] = number.map(units.pressure.toKilopascals)
        case .camber(let corner): sheet.camber[keyPath: corner.keyPath] = number
        case .toe(let axle): sheet.toe[keyPath: axle.keyPath] = number
        case .rideHeight(let axle): sheet.rideHeight[keyPath: axle.keyPath] = number.map(units.length.toMillimeters)
        case .bump(let axle): sheet.bump[keyPath: axle.keyPath] = number
        case .rebound(let axle): sheet.rebound[keyPath: axle.keyPath] = number
        case .antiRollBar, .wing: break
        }
        return true
    }
}
