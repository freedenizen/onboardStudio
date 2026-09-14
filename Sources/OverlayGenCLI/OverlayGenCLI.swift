import ArgumentParser
import ProjectModel

@main
struct OverlayGen: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "overlaygen",
        abstract: "Headless tools for OverlayGen projects: probe data, render, benchmark.",
        version: OverlayGenVersion.marketing,
        subcommands: [Probe.self, Render.self]
    )
}

struct Render: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Render a project or video headlessly.")

    @Option(name: .long, help: "Path to the output .mp4 file.")
    var out: String

    func run() throws {
        print("render: not implemented yet (milestone M2). Output: \(out)")
    }
}
