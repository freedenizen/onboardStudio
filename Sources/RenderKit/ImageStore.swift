import CoreGraphics
import Foundation
import ImageIO

/// A decoded still image. `CGImage` is immutable, so sharing it across render queues is safe.
public struct LoadedImage: @unchecked Sendable {
    public let image: CGImage
    public var width: Int { image.width }
    public var height: Int { image.height }

    public init(image: CGImage) { self.image = image }

    public static func load(_ url: URL) throws -> LoadedImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: true] as CFDictionary)
        else { throw ImageLoadError.unreadable(url) }
        return LoadedImage(image: image)
    }
}

public enum ImageLoadError: Error, CustomStringConvertible {
    case unreadable(URL)
    public var description: String {
        switch self {
        case .unreadable(let url): "Cannot read image \(url.lastPathComponent)."
        }
    }
}
