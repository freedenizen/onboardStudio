import ArgumentParser
import ProjectModel

@main
struct OnboardStudio: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "onboard",
        abstract: "Headless tools for Onboard Studio projects: probe data, render, sync, upload, bench.",
        version: OnboardStudioVersion.marketing,
        subcommands: [Probe.self, Render.self, Sync.self, Upload.self, Bench.self]
    )
}
