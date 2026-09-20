// Searches the DaVinci Resolve manual that ships inside the application bundle, so the shortcut
// claims in docs/conventions.md can be checked against a primary source rather than a blog post.
// Run from the repository root (there is deliberately no shebang: swift-format folds a comment
// that touches one onto the same line, which stops the script running).
//
//   swift Scripts/resolve-shortcuts.swift "Ripple Delete"   # matching lines, with page numbers
//   swift Scripts/resolve-shortcuts.swift --page 942        # one whole page
//
// The chapter tables headed "Keyboard Shortcuts in This Chapter" are the authoritative lists;
// pages 889 and 942 cover editing and modifying clips.

import Foundation
import PDFKit

let manual = "/Applications/DaVinci Resolve/DaVinci Resolve.app/Contents/Resources/DaVinci Resolve.pdf"

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

guard FileManager.default.fileExists(atPath: manual) else {
    fail("DaVinci Resolve is not installed, or its manual has moved: \(manual)")
}
guard let document = PDFDocument(url: URL(fileURLWithPath: manual)) else {
    fail("could not open the manual")
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard !arguments.isEmpty else { fail("usage: <search text> | --page <n>") }

if arguments[0] == "--page" {
    for number in arguments.dropFirst().compactMap(Int.init) {
        guard let page = document.page(at: number - 1), let text = page.string else { continue }
        print("───── page \(number) ─────\n\(text)")
    }
    exit(0)
}

let needle = arguments.joined(separator: " ")
var reported = Set<Int>()
for selection in document.findString(needle, withOptions: [.caseInsensitive]) {
    guard let page = selection.pages.first else { continue }
    let number = document.index(for: page)
    guard !reported.contains(number), reported.count < 25 else { continue }
    reported.insert(number)
    guard let text = page.string else { continue }
    for line in text.components(separatedBy: .newlines)
    where line.range(of: needle, options: .caseInsensitive) != nil {
        print("p\(number + 1): \(line.trimmingCharacters(in: .whitespaces))")
    }
}
if reported.isEmpty { print("no matches for \"\(needle)\"") }
