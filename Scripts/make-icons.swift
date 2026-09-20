// Renders the vector sources in Design/ into the app's icon assets. Run it through its
// wrapper, from the repository root:
//
//   Scripts/make-icons.sh
//
// There is deliberately no shebang here: swift-format folds a comment that touches one onto
// the same line, which turns the rest into arguments for `env` and stops the script running.
//
// AppKit rasterises SVG natively (_NSSVGImageRep), so this needs no Homebrew tools —
// only Design/AppIcon.svg and Design/DocumentIcon.svg, which are the editable sources.
// Outputs:
//   App/Assets.xcassets/AppIcon.appiconset/*.png  (+ Contents.json)
//   App/DocumentIcon.icns                         (referenced by CFBundleTypeIconFile)

import AppKit
import Foundation

let repo = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let design = repo.appending(path: "Design")
let appIconSet = repo.appending(path: "App/Assets.xcassets/AppIcon.appiconset")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

/// Rasterises an SVG at an exact pixel size. `NSImage.draw` scales the vector rep, so the
/// output is resolution-independent rather than a resampled bitmap.
func render(_ svg: URL, pixels: Int, to destination: URL) {
    guard let image = NSImage(contentsOf: svg) else { fail("could not read \(svg.lastPathComponent)") }
    guard
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)
    else { fail("could not allocate a \(pixels)px bitmap") }
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(
        in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero,
        operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else { fail("PNG encoding failed") }
    do { try png.write(to: destination) } catch { fail("\(destination.lastPathComponent): \(error)") }
}

// MARK: - App icon

/// The ten slots macOS wants, as (point size, scale).
let slots: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]

/// At 32 px and below the tick marks turn to mush and a thin needle disappears, so those
/// slots come from a simplified source — the same trick Apple's own icons use.
func appIconSource(pixels: Int) -> URL {
    design.appending(path: pixels <= 32 ? "AppIcon-small.svg" : "AppIcon.svg")
}

try? FileManager.default.createDirectory(at: appIconSet, withIntermediateDirectories: true)
var entries: [String] = []
for slot in slots {
    let suffix = slot.scale == 1 ? "" : "@\(slot.scale)x"
    let name = "icon_\(slot.points)x\(slot.points)\(suffix).png"
    let pixels = slot.points * slot.scale
    render(appIconSource(pixels: pixels), pixels: pixels, to: appIconSet.appending(path: name))
    entries.append(
        """
            { "idiom" : "mac", "size" : "\(slot.points)x\(slot.points)", "scale" : "\(slot.scale)x", \
        "filename" : "\(name)" }
        """)
    print("AppIcon  \(slot.points)x\(slot.points)@\(slot.scale)x  →  \(name)")
}

let contents = """
    {
      "images" : [
    \(entries.joined(separator: ",\n"))
      ],
      "info" : { "author" : "xcode", "version" : 1 }
    }

    """
do {
    try contents.write(to: appIconSet.appending(path: "Contents.json"), atomically: true, encoding: .utf8)
} catch {
    fail("Contents.json: \(error)")
}

// MARK: - Document icon

// .icns is what CFBundleTypeIconFile expects, and iconutil only reads a .iconset directory.
let staging = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "DocumentIcon.iconset")
try? FileManager.default.removeItem(at: staging)
do {
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
} catch {
    fail("could not stage the iconset: \(error)")
}
for slot in slots {
    let suffix = slot.scale == 1 ? "" : "@\(slot.scale)x"
    let name = "icon_\(slot.points)x\(slot.points)\(suffix).png"
    render(
        design.appending(path: "DocumentIcon.svg"), pixels: slot.points * slot.scale, to: staging.appending(path: name))
}

let icns = repo.appending(path: "App/DocumentIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", staging.path, "-o", icns.path]
do {
    try iconutil.run()
} catch {
    fail("could not run iconutil: \(error)")
}
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fail("iconutil failed") }
try? FileManager.default.removeItem(at: staging)
print("DocumentIcon  →  App/DocumentIcon.icns")
