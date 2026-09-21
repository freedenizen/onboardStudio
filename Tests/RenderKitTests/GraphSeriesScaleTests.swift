import CoreGraphics
import Foundation
import ProjectModel
import TelemetryKit
import Testing

@testable import RenderKit

/// #145: two channels whose ranges differ by orders of magnitude, on one graph.
///
/// The case is from the reference RaceChrono session: `throttle` is 0–100%, and
/// `canbus:brake_pressure_front` is 0–14,470 kPa. On one shared scale the pressure fills the plot
/// and throttle is a flat line along the bottom, which is exactly the graph people most want.
@Suite("Graph series scales")
struct GraphSeriesScaleTests {
    let plot = GraphRenderer.Plot(
        rect: CGRect(x: 0, y: 0, width: 100, height: 100), xRange: 0...1, yRange: 0...100, scale: 1)

    func trace(_ ys: [Double], ownRange: ClosedRange<Double>? = nil) -> GraphRenderer.Trace {
        GraphRenderer.Trace(
            points: ys.enumerated().map { CGPoint(x: Double($0.offset), y: $0.element) },
            color: .accent, lineWidth: 1, isGhost: false, ownRange: ownRange)
    }

    @Test("A series on its own scale is kept out of the shared fit")
    func ownScaleIsExcludedFromTheSharedFit() {
        var params = GraphParams(series: [GraphSeries(channel: "throttle")], axis: .time)
        params.minValue = nil
        params.maxValue = nil
        let renderer = GraphRenderer(
            context: ObjectContext(
                objectID: DisplayObjectID(), frame: .full, opacity: 1, sampler: nil, sync: .identity,
                cache: RenderCache()),
            params: params)

        // Throttle 0–100 sharing with brake pressure 0–14,470: the fit is ruined.
        let shared = renderer.verticalRange(
            of: GraphRenderer.Layout(xRange: 0...1, traces: [trace([0, 100]), trace([0, 14470])]))
        #expect(shared.upperBound > 14000, "both on the shared scale, so it fits the larger one")

        // The same pair with the pressure on its own scale: the shared range is throttle's again,
        // which is the point of taking it off.
        let split = renderer.verticalRange(
            of: GraphRenderer.Layout(
                xRange: 0...1, traces: [trace([0, 100]), trace([0, 14470], ownRange: 0...14470)]))
        #expect(split.upperBound < 120, "the shared fit is throttle's own, got \(split)")
        #expect(split.lowerBound > -20)
    }

    @Test("Both traces fill the plot, so their shapes can be compared")
    func bothFillThePlot() {
        // What the feature is for. Full throttle and full brake pressure must land at the same
        // height even though the numbers differ by two orders of magnitude.
        let throttleTop = plot.map(CGPoint(x: 0, y: 100))
        let pressureTop = plot.map(CGPoint(x: 0, y: 14470), using: 0...14470)
        #expect(abs(throttleTop.y - pressureTop.y) < 1e-9)

        let throttleZero = plot.map(CGPoint(x: 0, y: 0))
        let pressureZero = plot.map(CGPoint(x: 0, y: 0), using: 0...14470)
        #expect(abs(throttleZero.y - pressureZero.y) < 1e-9)

        // Half of each range is half the plot height, for both.
        #expect(abs(plot.map(CGPoint(x: 0, y: 50)).y - plot.map(CGPoint(x: 0, y: 7235), using: 0...14470).y) < 1e-9)

        // And without the override, the pressure is off the top of a 0–100 plot.
        #expect(plot.map(CGPoint(x: 0, y: 14470)).y < plot.rect.minY - 1000)
    }

    @Test("A series fits its own data when it is not given bounds")
    func fitsItsOwnDataWhenUnbounded() {
        var series = GraphSeries(channel: "canbus:brake_pressure_rear", usesOwnScale: true)
        // `brake_pressure_rear` never goes near zero — 160–276 kPa on the reference session — so a
        // fit to its own data is the only way its shape is visible at all.
        let points = [160.0, 200, 276].enumerated().map { CGPoint(x: Double($0.offset), y: $0.element) }
        let fitted = try? #require(GraphRenderer.ownRange(of: series, points: points))
        #expect((fitted?.lowerBound ?? 0) < 160)
        #expect((fitted?.upperBound ?? 0) > 276)
        #expect((fitted?.lowerBound ?? 0) > 140, "padded, not zero-based")

        // An explicit bound is taken as given, and the other still fits.
        series.minValue = 0
        let halfFixed = GraphRenderer.ownRange(of: series, points: points)
        #expect(halfFixed?.lowerBound == 0)
        #expect((halfFixed?.upperBound ?? 0) > 276)

        // A series that does not ask for its own scale has none, and follows the graph.
        #expect(GraphRenderer.ownRange(of: GraphSeries(channel: "throttle"), points: points) == nil)
    }

    @Test("A flat series still gets a usable range")
    func handlesAFlatSeries() {
        let series = GraphSeries(channel: "brake", usesOwnScale: true)
        let flat = (0..<3).map { CGPoint(x: Double($0), y: 42) }
        let range = GraphRenderer.ownRange(of: series, points: flat)
        #expect((range?.upperBound ?? 0) > (range?.lowerBound ?? 0), "a zero-span range divides by zero when mapped")
        #expect(GraphRenderer.ownRange(of: series, points: [])?.isEmpty == false)
    }

    @Test("Graphs saved before this keep one shared scale")
    func olderGraphsAreUnchanged() throws {
        let decoded = try JSONDecoder().decode(GraphSeries.self, from: Data(#"{"channel":"throttle"}"#.utf8))
        #expect(!decoded.usesOwnScale)
        #expect(decoded.minValue == nil && decoded.maxValue == nil)
        #expect(GraphRenderer.ownRange(of: decoded, points: [CGPoint(x: 0, y: 5)]) == nil)
    }
}
