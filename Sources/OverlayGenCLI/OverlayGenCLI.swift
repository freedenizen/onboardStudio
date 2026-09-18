import ArgumentParser
import ProjectModel

@main
struct OverlayGen: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "overlaygen",
        abstract: "Headless tools for OverlayGen projects: probe data, render, sync, upload, bench.",
        version: OverlayGenVersion.marketing,
        subcommands: [Probe.self, Render.self, Sync.self, Upload.self, Bench.self]
    )
}
