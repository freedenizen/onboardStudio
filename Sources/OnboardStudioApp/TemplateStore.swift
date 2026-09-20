import Foundation
import ProjectModel

/// User templates live as `.onboardtemplate` files in Application Support; built-in ones ship in
/// code.
enum TemplateStore {
    static var directory: URL {
        let base =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
        return base.appending(path: "OnboardStudio/Templates")
    }

    struct Entry: Identifiable, Hashable {
        var id: URL { url }
        let name: String
        let url: URL
    }

    /// User templates sorted by name.
    static func userTemplates() -> [Entry] {
        guard
            let urls = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        else { return [] }
        return
            urls
            .filter {
                $0.pathExtension == ProjectTemplate.fileExtension
                    || $0.pathExtension == ProjectTemplate.legacyFileExtension
            }
            .map { Entry(name: $0.deletingPathExtension().lastPathComponent, url: $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func save(_ template: ProjectTemplate, name: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let safe = name.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespaces)
        let url = directory.appending(path: (safe.isEmpty ? "Template" : safe) + "." + ProjectTemplate.fileExtension)
        var named = template
        named.name = safe.isEmpty ? "Template" : safe
        try named.data().write(to: url)
        return url
    }

    static func load(_ url: URL) throws -> ProjectTemplate {
        try ProjectTemplate(data: Data(contentsOf: url))
    }
}
