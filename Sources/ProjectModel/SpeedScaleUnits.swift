import Foundation

/// A speed's scale when the unit it is drawn in changes (#668).
///
/// A dial and a bar hold their scale in the numbers they show, so a dial fitted to a file as
/// 0–140 mph and then set to km/h was still 0–140: the readout converted, and the needle sat past
/// the end of the dial for most of the lap. #487 fitted the dial to its unit when the object was
/// made and when its first file arrived; the unit can also be changed afterwards — on the object,
/// or for the whole project — and the scale has to follow then too.
///
/// A scale that is still the one the file gave it is fitted again in the new unit, so going
/// to km/h and back restores the dial exactly. A scale somebody set is converted — its ends are
/// the same speeds as before, rounded outwards to a step that keeps the labels round — and so
/// are its zones, which are speeds as well.
enum SpeedScaleUnits {
    /// The ends of a scale that ran `low...high` in `old`, in `new`: rounded outwards to a round
    /// step that keeps the labels to a dozen or so, with that step and half of it for the marks.
    static func converted(
        _ low: Double, _ high: Double, from old: SpeedDisplayUnit, to new: SpeedDisplayUnit
    ) -> (min: Double, scale: SpeedScale) {
        let ratio = new.factorFromMetersPerSecond / old.factorFromMetersPerSecond
        let (low, high) = (Swift.min(low, high) * ratio, Swift.max(low, high) * ratio)
        let span = Swift.max(high - low, 1)
        let steps: [Double] = [1, 2, 5, 10, 20, 50, 100, 200, 500]
        let major = steps.first { (span / $0).rounded(.up) <= 13 } ?? 1_000
        // A hair's tolerance, so an end that lands on a step is not pushed a whole step further
        // out by the last digit of the conversion.
        let floor = ((low / major) + 1e-9).rounded(.down) * major
        let ceiling = ((high / major) - 1e-9).rounded(.up) * major
        return (floor, SpeedScale(max: Swift.max(ceiling, floor + major), major: major, minor: major / 2))
    }

    static func converted(_ zones: [GaugeZone], from old: SpeedDisplayUnit, to new: SpeedDisplayUnit) -> [GaugeZone] {
        let ratio = new.factorFromMetersPerSecond / old.factorFromMetersPerSecond
        return zones.map { zone in
            var zone = zone
            zone.from *= ratio
            zone.to = zone.to.map { $0 * ratio }
            return zone
        }
    }
}

extension GaugeParams {
    /// The same gauge once the speed it shows is drawn in `new` instead of `old` (#668). A gauge
    /// of anything but a speed is unchanged, and so is a speedometer still waiting for its first
    /// file, which is fitted in whatever unit it has by then.
    public func reshown(
        from old: SpeedDisplayUnit, in new: SpeedDisplayUnit, channels: [ChannelSummary]
    ) -> GaugeParams {
        guard old != new, !scaleAwaitsData, ChannelSummary.isSpeed(channel) else { return self }
        if zones.isEmpty, channels.contains(where: { $0.identifier == channel }) {
            let asFitted = fitted(to: channels, speedUnit: old)
            if (asFitted.minValue, asFitted.maxValue, asFitted.majorTick, asFitted.minorTick)
                == (minValue, maxValue, majorTick, minorTick)
            {
                return fitted(to: channels, speedUnit: new)
            }
        }
        var dial = self
        let (low, scale) = SpeedScaleUnits.converted(minValue, maxValue, from: old, to: new)
        (dial.minValue, dial.maxValue, dial.majorTick, dial.minorTick) = (low, scale.max, scale.major, scale.minor)
        dial.zones = SpeedScaleUnits.converted(zones, from: old, to: new)
        return dial
    }
}

extension BarParams {
    /// The same bar once the speed it shows is drawn in `new` instead of `old` (#668).
    public func reshown(from old: SpeedDisplayUnit, in new: SpeedDisplayUnit, channels: [ChannelSummary]) -> BarParams {
        guard old != new, ChannelSummary.isSpeed(channel) else { return self }
        if zones.isEmpty, channels.contains(where: { $0.identifier == channel }) {
            let asFitted = fitted(to: channels, speedUnit: old)
            if (asFitted.minValue, asFitted.maxValue) == (minValue, maxValue) {
                return fitted(to: channels, speedUnit: new)
            }
        }
        var bar = self
        let (low, scale) = SpeedScaleUnits.converted(minValue, maxValue, from: old, to: new)
        (bar.minValue, bar.maxValue) = (low, scale.max)
        bar.zones = SpeedScaleUnits.converted(zones, from: old, to: new)
        return bar
    }
}

extension Project {
    /// After an edit that may have changed the unit a speed is drawn in — the object's own
    /// setting, or the project's — gives every speed dial and bar whose unit did change the scale
    /// for its new one (#668). `shown` is the unit each object was drawn in before the edit, and
    /// `unit` what it is drawn in now; an object not in `shown` was made by the edit and is left
    /// as made. Returns the labels of the objects it changed.
    @discardableResult
    public mutating func reshowSpeedScales(
        from shown: [DisplayObjectID: SpeedDisplayUnit], channels: [InputID: [ChannelSummary]],
        unit: (DisplayObject) -> SpeedDisplayUnit
    ) -> [String] {
        var changed: [String] = []
        for index in displayObjects.indices {
            let object = displayObjects[index]
            guard let old = shown[object.id] else { continue }
            let new = unit(object)
            guard new != old else { continue }
            let available = object.inputID.flatMap { channels[$0] } ?? []
            var kind = object.kind
            if let params = kind.gaugeParams {
                kind = kind.replacingGaugeParams(params.reshown(from: old, in: new, channels: available))
            } else if case .bar(let params) = kind {
                kind = .bar(params.reshown(from: old, in: new, channels: available))
            }
            guard kind != object.kind else { continue }
            displayObjects[index].kind = kind
            changed.append(object.label)
        }
        return changed
    }

    /// The objects whose scale is a speed's: the ones `reshowSpeedScales` may have to change.
    public var speedScaleObjects: [DisplayObject] {
        displayObjects.filter { object in
            if let params = object.kind.gaugeParams { return ChannelSummary.isSpeed(params.channel) }
            if case .bar(let params) = object.kind { return ChannelSummary.isSpeed(params.channel) }
            return false
        }
    }
}
