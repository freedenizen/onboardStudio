import Foundation

/// Where a distance axis puts its marks, so that they are round in the unit shown.
public enum DistanceTicks {
    /// The marks across `span` (metres), as positions in metres that are round numbers of the unit
    /// shown: every 500 or 1,000 ft, not every kilometre written in feet. The charts chose their
    /// own marks in metres and the labels converted them, which gave 3,281, 6,562 and 9,843 (#669).
    ///
    /// `metresPerUnit` is 1 for metres and 0.3048 for feet; about `target` marks are made, at a
    /// step of 1, 2 or 5 times a power of ten.
    public static func positions(in span: ClosedRange<Double>, metresPerUnit: Double, target: Int = 6) -> [Double] {
        guard metresPerUnit > 0, target > 0 else { return [] }
        let lower = span.lowerBound / metresPerUnit
        let upper = span.upperBound / metresPerUnit
        guard upper > lower, (upper - lower).isFinite else { return [] }
        let rough = (upper - lower) / Double(target)
        let magnitude = pow(10, floor(log10(rough)))
        let step = [1.0, 2, 5, 10].map { $0 * magnitude }.first { $0 >= rough } ?? 10 * magnitude
        var marks: [Double] = []
        var index = (lower / step).rounded(.up)
        while index * step <= upper + step * 1e-9 {
            marks.append(index * step * metresPerUnit)
            index += 1
        }
        return marks
    }
}
