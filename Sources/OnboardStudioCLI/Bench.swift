import ArgumentParser
import Darwin
import Foundation
import MediaKit
import ProjectModel
import RenderKit

struct Bench: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Measure the render pipeline: overlay drawing per frame, export throughput, memory.")

    @Option(name: .long, help: "Project package to benchmark (default: the test fixture slice).")
    var project: String?

    @Option(name: .long, help: "Frames to draw for the overlay timing.")
    var frames: Int = 300

    @Option(name: .long, help: "Output size for the overlay timing as WxH (default: the project's).")
    var size: String?

    @Flag(name: .long, help: "Also run a real export of the project and report its speed relative to real time.")
    var export = false

    @Option(name: .long, help: "Export codec (h264 or hevc) with --export.")
    var codec: ExportSettings.VideoCodec = .hevc

    @Option(name: .long, help: "Seconds of the project to export with --export (default: everything).")
    var seconds: Double?

    @Flag(name: .long, help: "Print the results as JSON.")
    var json = false

    struct Report {
        var values: [String: Any] = [:]
        subscript(key: String) -> Any? {
            get { values[key] }
            set { values[key] = newValue }
        }
    }

    func run() async throws {
        let url = URL(fileURLWithPath: project ?? Self.fixture)
        let loaded = try await ProjectCompiler.load(url)
        let compiled = try await ProjectCompiler.compile(loaded)
        var report = Report()
        report["project"] = url.lastPathComponent
        report["frames"] = frames
        let (width, height) = try outputSize(default: compiled.plan)
        report["width"] = width
        report["height"] = height
        try benchmarkOverlays(compiled, width: width, height: height, report: &report)
        if export { try await benchmarkExport(loaded, compiled, width: width, height: height, report: &report) }
        if json {
            let data = try JSONSerialization.data(
                withJSONObject: report.values, options: [.prettyPrinted, .sortedKeys])
            print(String(bytes: data, encoding: .utf8) ?? "")
        } else {
            printReport(report, url: url, overlays: compiled.plan.overlays.count)
        }
    }

    /// Draws every plan's overlays (no video) into one buffer and times each frame.
    func benchmarkOverlays(_ compiled: CompiledComposition, width: Int, height: Int, report: inout Report) throws {
        let memoryStart = Self.residentMemory()
        var worst = 0.0
        var total = 0.0
        var drawn = 0
        for timed in compiled.plans {
            let plan = RenderPlan(
                outputWidth: width, outputHeight: height, frameRate: compiled.plan.frameRate, videoLayers: [],
                overlays: timed.plan.overlays)
            let compositor = try FrameCompositor(plan: plan)
            let output = try PixelBuffers.makeBuffer(width: width, height: height)
            let perPlan = max(1, frames / max(1, compiled.plans.count))
            for index in 0..<perPlan {
                let time = timed.start + Double(index) / plan.frameRate
                let started = DispatchTime.now().uptimeNanoseconds
                try autoreleasepool { try compositor.render(sources: [:], time: time, into: output) }
                let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1e6
                total += elapsed
                worst = max(worst, elapsed)
                drawn += 1
            }
        }
        let average = total / Double(max(1, drawn))
        report["overlayMsPerFrame"] = average
        report["overlayWorstMs"] = worst
        report["overlayFps"] = average > 0 ? 1000 / average : 0
        report["overlays"] = compiled.plan.overlays.count
        report["residentMBStart"] = Double(memoryStart) / 1e6
        report["residentMBAfterOverlays"] = Double(Self.residentMemory()) / 1e6
    }

    /// Runs a real export and reports its speed relative to real time.
    func benchmarkExport(
        _ loaded: ProjectCompiler.LoadedProject, _ compiled: CompiledComposition, width: Int, height: Int,
        report: inout Report
    ) async throws {
        let out = FileManager.default.temporaryDirectory.appending(path: "onboard-bench-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: out) }
        var settings = loaded.project.export
        settings.codec = codec
        settings.width = width
        settings.height = height
        settings.frameRate = compiled.plan.frameRate
        let range: ClosedRange<Double>? = seconds.map { 0...min($0, compiled.duration) }
        let exportedSeconds = (range?.upperBound ?? compiled.duration) - (range?.lowerBound ?? 0)
        let started = Date()
        var framesWritten = 0
        for try await progress in Exporter.export(compiled, settings: settings, range: range, to: out) {
            framesWritten = progress.framesWritten
        }
        let wall = Date().timeIntervalSince(started)
        report["exportSeconds"] = exportedSeconds
        report["exportWallSeconds"] = wall
        report["exportRealtimeFactor"] = wall > 0 ? exportedSeconds / wall : 0
        report["exportFps"] = wall > 0 ? Double(framesWritten) / wall : 0
        report["exportCodec"] = codec.rawValue
        report["residentMBAfterExport"] = Double(Self.residentMemory()) / 1e6
    }

    func printReport(_ report: Report, url: URL, overlays: Int) {
        func number(_ key: String) -> Double { report[key] as? Double ?? 0 }
        let width = report["width"] as? Int ?? 0
        let height = report["height"] as? Int ?? 0
        print("Project:   \(url.lastPathComponent)  \(width)x\(height), \(overlays) overlays")
        let average = number("overlayMsPerFrame")
        print(
            "Overlays:  \(fmt(average)) ms/frame average, \(fmt(number("overlayWorstMs"))) ms worst → "
                + "\(fmt(1000 / max(average, 0.001))) fps")
        print(
            "Memory:    \(fmt(number("residentMBStart"))) MB → \(fmt(number("residentMBAfterOverlays"))) MB resident")
        if report["exportRealtimeFactor"] != nil {
            let took = "\(fmt(number("exportSeconds"))) s in \(fmt(number("exportWallSeconds"))) s"
            print(
                "Export:    \(codec.rawValue) \(took) → \(fmt(number("exportRealtimeFactor")))× real time, "
                    + "\(fmt(number("exportFps"))) fps")
        }
    }

    static var fixture: String {
        // Sources/OnboardStudioCLI/Bench.swift → Tests/Fixtures/slice.onboardproj
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Tests/Fixtures/slice.onboardproj").path
    }

    func outputSize(default plan: RenderPlan) throws -> (Int, Int) {
        guard let size else { return (plan.outputWidth, plan.outputHeight) }
        let parts = size.lowercased().split(separator: "x").compactMap { Int($0) }
        guard parts.count == 2, parts[0] > 0, parts[1] > 0 else { throw ValidationError("--size must be WxH.") }
        return (parts[0], parts[1])
    }

    /// Resident memory of this process in bytes.
    static func residentMemory() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.resident_size) : 0
    }

    func fmt(_ value: Double) -> String { String(format: value >= 100 ? "%.0f" : "%.2f", value) }
}
