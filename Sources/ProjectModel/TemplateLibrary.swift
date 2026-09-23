import Foundation

/// The user's own templates (#44): `.onboardtemplate` files in
/// `~/Library/Application Support/OnboardStudio/Templates`, listed beside the built-in ones.
///
/// A template's file name and the name inside it are kept the same, so what Finder shows and what
/// the welcome window shows never disagree.
public struct TemplateLibrary: Sendable {
    public struct Entry: Identifiable, Hashable, Sendable {
        public var id: URL { url }
        public let name: String
        public let url: URL
    }

    public let directory: URL
    /// Whether removing a template moves it to the Trash, where it can be put back. Tests turn it
    /// off rather than fill the Trash of whoever runs them.
    public let trashesRemovedFiles: Bool

    /// Defaults to `~/Library/Application Support/OnboardStudio/Templates`. Tests pass their own.
    public init(directory: URL? = nil, trashesRemovedFiles: Bool = true) {
        self.directory =
            directory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "OnboardStudio/Templates")
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "OnboardStudio/Templates")
        self.trashesRemovedFiles = trashesRemovedFiles
    }

    /// Every template, by name. Files that are not templates are left out; a file that turns out
    /// not to read is found when it is opened, not here, so a list never costs a parse per file.
    public func entries() -> [Entry] {
        let contents =
            (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return
            contents
            .filter {
                $0.pathExtension == ProjectTemplate.fileExtension
                    || $0.pathExtension == ProjectTemplate.legacyFileExtension
            }
            .map { Entry(name: $0.deletingPathExtension().lastPathComponent, url: $0) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func entry(named name: String) -> Entry? {
        entries().first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    public func load(_ entry: Entry) throws -> ProjectTemplate {
        try ProjectTemplate(data: Data(contentsOf: entry.url))
    }

    /// A name a file can carry: no slashes or colons, no surrounding space.
    public static func cleaned(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Saves `template` under `name`, replacing a template of that name. The Save as Template
    /// sheet says so before it happens.
    @discardableResult
    public func save(_ template: ProjectTemplate, name: String) throws -> Entry {
        let name = Self.cleaned(name)
        guard !name.isEmpty else { throw TemplateLibraryError.emptyName }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let existing = entry(named: name) { try FileManager.default.removeItem(at: existing.url) }
        var named = template
        named.name = name
        let url = directory.appending(path: "\(name).\(ProjectTemplate.fileExtension)")
        try named.data().write(to: url, options: .atomic)
        return Entry(name: name, url: url)
    }

    /// Renames `entry`, file and all. Refuses a name another template already has.
    @discardableResult
    public func rename(_ entry: Entry, to newName: String) throws -> Entry {
        let name = Self.cleaned(newName)
        guard !name.isEmpty else { throw TemplateLibraryError.emptyName }
        if let other = self.entry(named: name), !Self.sameFile(other.url, entry.url) {
            throw TemplateLibraryError.nameTaken(other.name)
        }
        let template = try load(entry)
        let renamed = try saveNew(template, name: name, replacing: entry.url)
        return renamed
    }

    /// A copy of `entry` named "Name copy", "Name copy 2", … as Finder names duplicates.
    @discardableResult
    public func duplicate(_ entry: Entry) throws -> Entry {
        try saveNew(load(entry), name: availableName("\(entry.name) copy"), replacing: nil)
    }

    /// Adds the template file at `url` to the library under the file's name — what the user saw in
    /// the Finder — or the next free one. A file that does not read as a template is refused
    /// before anything is copied.
    @discardableResult
    public func importTemplate(from url: URL) throws -> Entry {
        let template = try ProjectTemplate(data: Data(contentsOf: url))
        let fileName = Self.cleaned(url.deletingPathExtension().lastPathComponent)
        return try saveNew(template, name: availableName(fileName.isEmpty ? template.name : fileName), replacing: nil)
    }

    /// Writes `entry` to `url` for sharing, under the name the destination was given.
    public func export(_ entry: Entry, to url: URL) throws {
        var template = try load(entry)
        template.name = url.deletingPathExtension().lastPathComponent
        try template.data().write(to: url, options: .atomic)
    }

    /// Moves `entry` to the Trash (or deletes it where the library does not use one).
    public func remove(_ entry: Entry) throws {
        if trashesRemovedFiles {
            try FileManager.default.trashItem(at: entry.url, resultingItemURL: nil)
        } else {
            try FileManager.default.removeItem(at: entry.url)
        }
    }

    /// `base`, or `base 2`, `base 3`… — the first no template has.
    public func availableName(_ base: String) -> String {
        let base = Self.cleaned(base)
        guard entry(named: base) != nil else { return base }
        var number = 2
        while entry(named: "\(base) \(number)") != nil { number += 1 }
        return "\(base) \(number)"
    }

    private func saveNew(_ template: ProjectTemplate, name: String, replacing old: URL?) throws -> Entry {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var named = template
        named.name = name
        let url = directory.appending(path: "\(name).\(ProjectTemplate.fileExtension)")
        try named.data().write(to: url, options: .atomic)
        // A rename that only changes case writes over the same file on a case-insensitive disk.
        if let old, !Self.sameFile(old, url) {
            try FileManager.default.removeItem(at: old)
        }
        return Entry(name: name, url: url)
    }

    /// Whether two URLs name one file on a Mac's case-insensitive disk, through `/var` → `/private/var`.
    private static func sameFile(_ a: URL, _ b: URL) -> Bool {
        a.resolvingSymlinksInPath().path.lowercased() == b.resolvingSymlinksInPath().path.lowercased()
    }
}

public enum TemplateLibraryError: Error, Equatable, CustomStringConvertible {
    case emptyName
    case nameTaken(String)

    public var description: String {
        switch self {
        case .emptyName: "A template needs a name."
        case .nameTaken(let name): "You already have a template called “\(name)”. Choose another name."
        }
    }
}
