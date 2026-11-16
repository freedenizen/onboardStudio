import Foundation

extension GPSQuality {
    /// What was measured, as a driver reads it: "25 positions a second · accuracy 0.8 m ·
    /// 14 satellites · distances to about 1 m".
    public func measurements(units: CoachingUnits) -> String {
        var parts = ["\(Self.rate(rateHertz)) a second"]
        if let accuracyMeters { parts.append("accuracy \(Self.length(accuracyMeters, units))") }
        if let hdop { parts.append("HDOP \(Self.decimal(hdop))") }
        if let satellites { parts.append("\(Int(satellites.rounded())) satellites") }
        parts.append("distances to about \(Self.number(distanceStep(in: units.distance))) \(units.distance.symbol)")
        return parts.joined(separator: " · ")
    }

    /// One sentence per finding, worst first; empty when the data is good.
    public func messages(units: CoachingUnits) -> [String] {
        findings.map { message(of: $0, units: units) }
    }

    public func message(of finding: Finding, units: CoachingUnits) -> String {
        switch finding.issue {
        case .rate(let hertz, let wanted):
            return "Only \(Self.rate(hertz)) a second; corner-level advice needs \(Self.number(wanted)) or more."
        case .dropouts(let count, let longest):
            if count == 1 { return "Positions stopped for \(Self.decimal(longest)) s while moving." }
            return "Positions stopped \(count) times while moving, for up to \(Self.decimal(longest)) s."
        case .jumps(let count):
            let what = count == 1 ? "A position" : "\(count) positions"
            return "\(what) landed further away than the car could have got to."
        case .accuracy(let meters):
            return "The logger put its own accuracy at \(Self.length(meters, units))."
        case .hdop(let value):
            return "HDOP \(Self.decimal(value)): the satellites in view were poorly spread."
        case .satellites(let count):
            return "Only \(Int(count.rounded())) satellites in use."
        case .longLaps(let numbers):
            let laps = numbers.map(String.init).formattedList
            let verb = numbers.count == 1 ? "Lap \(laps) is" : "Laps \(laps) are"
            return "\(verb) about twice the usual length: the start/finish line was probably missed."
        }
    }

    static func rate(_ hertz: Double) -> String {
        let text = hertz >= 2 ? String(Int(hertz.rounded())) : decimal(hertz)
        return "\(text) position\(text == "1" ? "" : "s")"
    }

    static func length(_ meters: Double, _ units: CoachingUnits) -> String {
        let converted = TelemetryUnit.meters.convert(meters, to: units.distance) ?? meters
        return "\(converted < 10 ? decimal(converted) : String(Int(converted.rounded()))) \(units.distance.symbol)"
    }

    /// One decimal, without a trailing ".0".
    static func decimal(_ value: Double) -> String {
        let text = String(format: "%.1f", value)
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }

    static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : decimal(value)
    }
}

extension [String] {
    /// "4", "4 and 7", "4, 7 and 9".
    public var formattedList: String {
        guard count > 1, let last else { return first ?? "" }
        return dropLast().joined(separator: ", ") + " and " + last
    }
}
