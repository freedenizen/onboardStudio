import CoreGraphics
import Foundation
import ProjectModel
import TelemetryKit

/// The lap being driven painted by a channel's value (#561): speed, brake, throttle, G, anything
/// the data has, on the ramp set in Settings.
extension TrackMapRenderer {
    /// What a channel's values mean as colour: the channel, and the session's low and high that the
    /// ramp's ends stand for. Worked out once per renderer.
    ///
    /// The low and high are the whole session's, not the lap's, so a colour means the same speed
    /// on every lap and a lap that never reached the top colour shows it. They are the 2nd and 98th
    /// percentiles of the complete laps' values, so the slow out-lap and the pit lane do not stretch
    /// the scale and a single spike cannot squash everything else into one colour.
    struct ChannelScale: Sendable {
        let identifier: String
        let channel: Channel
        let low: Double
        let high: Double

        init?(session: TelemetrySession, identifier: String) {
            guard let role = ChannelRole(identifier: identifier), let channel = session[role], !channel.isEmpty else {
                return nil
            }
            let complete = session.laps.filter(\.isComplete)
            let values: [Double]
            if complete.isEmpty {
                values = channel.values.filter(\.isFinite)
            } else {
                values = zip(channel.times, channel.values).compactMap { time, value in
                    value.isFinite && complete.contains { $0.contains(time) } ? value : nil
                }
            }
            guard !values.isEmpty else { return nil }
            let sorted = values.sorted()
            func percentile(_ fraction: Double) -> Double {
                sorted[min(sorted.count - 1, Int((Double(sorted.count - 1) * fraction).rounded()))]
            }
            self.identifier = identifier
            self.channel = channel
            low = percentile(0.02)
            high = percentile(0.98)
        }

        /// Where `value` sits between the low and the high; the middle when they are the same.
        func fraction(of value: Double) -> Double {
            high > low ? (value - low) / (high - low) : 0.5
        }
    }

    /// A point of the painted lap: where it is drawn, when the car was there, and its colour step.
    struct ChannelSample {
        var point: CGPoint
        var time: Double
        var level: Int
    }

    /// The lap painted at `inputTime`: the one the car is on, of any kind and complete or not.
    func channelLap(atInputTime inputTime: Double) -> Lap? {
        guard channelScale != nil, let laps = context.sampler?.session.laps else { return nil }
        return laps.first { $0.contains(inputTime) }
    }

    /// The lap's line, each stretch in the colour of its value. Consecutive stretches of nearly the
    /// same colour are stroked as one path, so a lap is a few dozen strokes rather than thousands.
    func drawChannel(on lap: Lap, in cg: CGContext, size: CGSize, projection: TrackProjection) {
        guard let scale = channelScale, let session = context.sampler?.session,
            let latitude = session[.latitude], let longitude = session[.longitude]
        else { return }
        let bounds = plotBounds(in: size)
        let end = lap.end ?? latitude.lastTime ?? lap.start
        var from = 0
        var upper = latitude.count
        while from < upper {
            let mid = (from + upper) / 2
            if latitude.times[mid] < lap.start { from = mid + 1 } else { upper = mid }
        }
        let steps = 64
        var samples: [ChannelSample] = []
        for index in from..<latitude.count {
            let time = latitude.times[index]
            guard time <= end else { break }
            guard let lon = longitude.value(at: time), let value = scale.channel.value(at: time) else { continue }
            let point = projection.point(latitude: latitude.values[index], longitude: lon, in: bounds)
            // Points closer than a pixel add strokes without adding anything to see.
            if let last = samples.last?.point, hypot(point.x - last.x, point.y - last.y) < 1 { continue }
            let level = Int((min(max(scale.fraction(of: value), 0), 1) * Double(steps)).rounded())
            samples.append(ChannelSample(point: point, time: time, level: level))
        }
        guard samples.count > 1 else { return }
        let lineScale = max(0.5, min(size.width, size.height) / 300)
        cg.setLineWidth(params.lineWidth * lineScale * 1.1)
        cg.setLineJoin(.round)
        cg.setLineCap(.round)
        // Each stretch takes the colour of the sample it starts from. A stretch ends where that
        // colour changes and across a gap in the positions, where joining the two sides would rule
        // a line across the circuit.
        var stretch = [samples[0].point]
        var level = samples[0].level
        func flush() {
            cg.setStrokeColor(ramp.color(at: Double(level) / Double(steps)).cgColor)
            stroke(stretch, in: cg)
        }
        for index in 1..<samples.count {
            let previous = samples[index - 1]
            if samples[index].time - previous.time > 2 {
                flush()
                stretch = [samples[index].point]
                level = samples[index].level
                continue
            }
            if previous.level != level {
                flush()
                stretch = [previous.point]
                level = previous.level
            }
            stretch.append(samples[index].point)
        }
        flush()
    }

    /// Where the legend goes and how large its words are, or `nil` when there is none.
    struct LegendLayout {
        var bar: CGRect
        var textSize: Double
        /// The top of the band the legend takes, words included.
        var top: Double
    }

    func legendLayout(in size: CGSize) -> LegendLayout? {
        guard channelScale != nil, params.showChannelLegend else { return nil }
        let side = min(size.width, size.height)
        let textSize = max(6, side * params.labelScale * 0.6)
        let width = size.width * 0.6
        let height = max(3, textSize * 0.45)
        let bar = CGRect(
            x: (size.width - width) / 2, y: size.height - height - max(4, side * 0.04), width: width, height: height)
        return LegendLayout(bar: bar, textSize: textSize, top: bar.minY - textSize * 1.6)
    }

    /// Where the circuit is fitted: the whole object, less the legend's band at its foot so the
    /// legend never sits on the line. Never less than half the object, however large the words.
    func plotBounds(in size: CGSize) -> CGRect {
        let whole = CGRect(origin: .zero, size: size)
        guard let legend = legendLayout(in: size) else { return whole }
        return CGRect(x: 0, y: 0, width: size.width, height: max(size.height * 0.5, legend.top))
    }

    /// The ramp as a bar along the map's foot, the channel's name and its low and high above it in
    /// the unit the object shows it in.
    func drawChannelLegend(in cg: CGContext, size: CGSize) {
        guard let scale = channelScale, let layout = legendLayout(in: size) else { return }
        let bar = layout.bar
        let pieces = 48
        for piece in 0..<pieces {
            let x = bar.minX + bar.width * Double(piece) / Double(pieces)
            cg.setFillColor(ramp.color(at: (Double(piece) + 0.5) / Double(pieces)).cgColor)
            // A hair wider than its share, so the pieces meet without a seam.
            cg.fill(CGRect(x: x, y: bar.minY, width: bar.width / Double(pieces) + 0.5, height: bar.height))
        }
        cg.setStrokeColor(RGBAColor.black.cgColor)
        cg.setLineWidth(max(1, bar.height * 0.15))
        cg.stroke(bar)
        label(
            legendText(of: scale), at: CGPoint(x: bar.midX, y: bar.minY - layout.textSize * 0.75),
            size: layout.textSize, in: cg)
    }

    /// "Speed 42–181 km/h": the channel, and the low and high its ramp's ends stand for.
    func legendText(of scale: ChannelScale) -> String {
        let name = ChannelRole(identifier: scale.identifier)?.displayName ?? scale.identifier
        let low = context.units.value(scale.low, of: scale.identifier)
        let high = context.units.value(scale.high, of: scale.identifier)
        let unit = context.units.label(for: scale.identifier) ?? scale.channel.unit.symbol
        let span = abs(high - low)
        let digits = span >= 20 ? 0 : span >= 2 ? 1 : 2
        let range = String(format: "%.\(digits)f–%.\(digits)f", low, high)
        return unit.isEmpty ? "\(name) \(range)" : "\(name) \(range) \(unit)"
    }
}

extension Lap {
    /// Whether `time` falls within the lap; a lap with no end runs on.
    func contains(_ time: Double) -> Bool {
        time >= start && time < (end ?? .infinity)
    }
}
