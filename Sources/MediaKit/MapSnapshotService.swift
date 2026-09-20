import CoreGraphics
import Foundation
import ImageIO
import MapKit
import RenderKit
import UniformTypeIdentifiers

/// Fetches Apple Maps imagery for a track map background with `MKMapSnapshotter` and caches
/// the result (image + geographic mapping) under `~/Library/Caches/OnboardStudio/maps`.
public enum MapSnapshotService {
    public static let snapshotSize = 1024
    nonisolated(unsafe) private static var memory: [MapBackgroundRequest: MapBackground] = [:]
    private static let lock = NSLock()

    public static var cacheDirectory: URL {
        let base =
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appending(path: "OnboardStudio/maps")
    }

    /// The background for `request`, from memory, disk, or Apple Maps; `nil` when offline.
    public static func background(for request: MapBackgroundRequest) async -> MapBackground? {
        if let cached = remembered(request) { return cached }
        if let stored = loadFromDisk(request) {
            remember(stored)
            return stored
        }
        guard let fetched = try? await fetch(request) else { return nil }
        remember(fetched)
        try? store(fetched)
        return fetched
    }

    private static func remembered(_ request: MapBackgroundRequest) -> MapBackground? {
        lock.lock()
        defer { lock.unlock() }
        return memory[request]
    }

    private static func remember(_ background: MapBackground) {
        lock.lock()
        memory[background.request] = background
        lock.unlock()
    }

    // MARK: - Apple Maps

    static func fetch(_ request: MapBackgroundRequest) async throws -> MapBackground {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: request.centerLatitude, longitude: request.centerLongitude),
            span: MKCoordinateSpan(
                latitudeDelta: request.maxLatitude - request.minLatitude,
                longitudeDelta: request.maxLongitude - request.minLongitude))
        options.size = CGSize(width: snapshotSize, height: snapshotSize)
        options.preferredConfiguration =
            switch request.style {
            case .satellite: MKImageryMapConfiguration()
            case .hybrid: MKHybridMapConfiguration()
            case .none, .standard: MKStandardMapConfiguration()
            }
        options.showsBuildings = false
        let snapshot = try await MKMapSnapshotter(options: options).start()
        guard let image = snapshot.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw SnapshotError.noImage
        }
        let pointScale = Double(image.width) / snapshot.image.size.width
        let centre = CLLocationCoordinate2D(latitude: request.centerLatitude, longitude: request.centerLongitude)
        let north = CLLocationCoordinate2D(latitude: request.centerLatitude + 0.001, longitude: request.centerLongitude)
        let east = CLLocationCoordinate2D(latitude: request.centerLatitude, longitude: request.centerLongitude + 0.001)
        var centrePoint = snapshot.point(for: centre)
        var northPoint = snapshot.point(for: north)
        var eastPoint = snapshot.point(for: east)
        // AppKit snapshots report points with a bottom-left origin; normalise to top-left.
        if northPoint.y > centrePoint.y {
            let height = snapshot.image.size.height
            centrePoint.y = height - centrePoint.y
            northPoint.y = height - northPoint.y
            eastPoint.y = height - eastPoint.y
        }
        return MapBackground(
            request: request, image: image,
            centerPoint: CGPoint(x: centrePoint.x * pointScale, y: centrePoint.y * pointScale),
            pixelsPerDegreeLongitude: (eastPoint.x - centrePoint.x) * pointScale / 0.001,
            pixelsPerDegreeLatitude: (centrePoint.y - northPoint.y) * pointScale / 0.001)
    }

    enum SnapshotError: Error {
        case noImage
    }

    // MARK: - Disk cache

    struct Record: Codable {
        var request: MapBackgroundRequest
        var centerX: Double
        var centerY: Double
        var pixelsPerDegreeLongitude: Double
        var pixelsPerDegreeLatitude: Double
    }

    static func cacheName(_ request: MapBackgroundRequest) -> String {
        let text =
            "\(request.style.rawValue)|\(request.minLatitude)|\(request.maxLatitude)|\(request.minLongitude)"
            + "|\(request.maxLongitude)|\(snapshotSize)"
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }

    static func loadFromDisk(_ request: MapBackgroundRequest) -> MapBackground? {
        let name = cacheName(request)
        let json = cacheDirectory.appending(path: "\(name).json")
        let png = cacheDirectory.appending(path: "\(name).png")
        guard let data = try? Data(contentsOf: json), let record = try? JSONDecoder().decode(Record.self, from: data),
            record.request == request, let source = CGImageSourceCreateWithURL(png as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        return MapBackground(
            request: request, image: image, centerPoint: CGPoint(x: record.centerX, y: record.centerY),
            pixelsPerDegreeLongitude: record.pixelsPerDegreeLongitude,
            pixelsPerDegreeLatitude: record.pixelsPerDegreeLatitude)
    }

    static func store(_ background: MapBackground) throws {
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let name = cacheName(background.request)
        let png = cacheDirectory.appending(path: "\(name).png")
        guard let destination = CGImageDestinationCreateWithURL(png as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw SnapshotError.noImage }
        CGImageDestinationAddImage(destination, background.image, nil)
        guard CGImageDestinationFinalize(destination) else { throw SnapshotError.noImage }
        let record = Record(
            request: background.request, centerX: background.centerPoint.x, centerY: background.centerPoint.y,
            pixelsPerDegreeLongitude: background.pixelsPerDegreeLongitude,
            pixelsPerDegreeLatitude: background.pixelsPerDegreeLatitude)
        try JSONEncoder().encode(record).write(to: cacheDirectory.appending(path: "\(name).json"))
    }
}
