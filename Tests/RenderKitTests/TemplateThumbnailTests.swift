import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import ProjectModel
@testable import RenderKit

@Suite("Template thumbnails (#44)")
struct TemplateThumbnailTests {
    @Test(arguments: ProjectTemplate.builtIn.map(\.name))
    func everyBuiltInTemplateHasAPicture(_ name: String) throws {
        let template = try #require(ProjectTemplate.builtIn.first { $0.name == name })
        let image = try #require(TemplateThumbnail.image(of: template, width: 320))
        #expect(image.width == 320)
        // The template's own shape: 180 for 16:9, 569 for the 9:16 Social template.
        let aspect = Double(template.settings.outputHeight) / Double(template.settings.outputWidth)
        #expect(image.height == Int((320 * aspect).rounded()))
        // Something other than the backdrop was drawn: the overlays are there to be seen.
        #expect(brightPixels(in: image) > 20)
        if let folder = ProcessInfo.processInfo.environment["THUMBNAIL_DIR"] {
            try write(image, to: URL(fileURLWithPath: folder).appending(path: "\(name).png"))
        }
    }

    @Test func anEmptyTemplateIsJustTheBackdrop() throws {
        let template = ProjectTemplate(name: "Empty", project: Project())
        let image = try #require(TemplateThumbnail.image(of: template, width: 160))
        #expect(image.height == 90)
        #expect(brightPixels(in: image) == 0)
    }

    func brightPixels(in image: CGImage) -> Int {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard
            let context = CGContext(
                data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: PixelBuffers.colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return 0 }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return stride(from: 0, to: pixels.count, by: 4).filter { pixels[$0] > 180 && pixels[$0 + 1] > 180 }.count
    }

    func write(_ image: CGImage, to url: URL) throws {
        let destination = try #require(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }
}
