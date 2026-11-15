import AVFoundation
import CoreGraphics
import CoreML
import CryptoKit
import Foundation

/// What a video showed ahead (#573): one picture a second, and how wide the nearest car close
/// ahead was in it.
public struct CarSightings: Sendable, Hashable, Codable {
    /// Seconds into the file of each picture read.
    public var times: [Double] = []
    /// The nearest car close ahead in each picture, its width as a fraction of the picture's; 0
    /// when there was none.
    public var widths: [Double] = []
    /// The file's length, seconds: where the next chapter of a recording begins.
    public var duration: Double = 0

    public init(times: [Double] = [], widths: [Double] = [], duration: Double = 0) {
        self.times = times
        self.widths = widths
        self.duration = duration
    }
}

/// Reads an onboard video for a car close ahead (#573), with YOLOX-Nano, a COCO detector, on one
/// keyframe a second: a GoPro writes one every second, so the rest of the frames are never
/// decoded. Measured in `docs/traffic.md` (*The spike*): the input size and a crop of the middle of
/// the picture matter more than the model, and the car's own cabin is a huge "car" on every frame
/// unless boxes that wide are refused.
public enum VideoTraffic {
    /// Which boxes are a car close ahead, as fractions of the upright picture.
    public struct Rule: Sendable, Hashable {
        /// The part of the picture the detector sees, at its own resolution: the middle, where the
        /// road ahead is, from above the horizon to the dashboard.
        public var crop = CGRect(x: 0.15, y: 0.12, width: 0.70, height: 0.50)
        /// Class score times objectness.
        public var minimumScore = 0.4
        /// A box narrower than this is a car too far away to be in the way…
        public var minimumWidth = 30.0 / 2_704
        /// …and one wider is this car's own cabin: the windscreen frame, the dash, the mirror.
        public var maximumWidth = 600.0 / 2_704
        /// The box's centre must be inside this band across the picture…
        public var centre: ClosedRange<Double> = 0.2...0.8
        /// …and its bottom below this fraction of the height: not the sky, nor the rear-view mirror.
        public var lowestTop = 0.30

        public init() {}
    }

    /// COCO's car, motorcycle, bus and truck.
    static let vehicleClasses: Set<Int> = [2, 3, 5, 7]
    /// The model's square input, pixels.
    static let inputSize = 640
    /// Bumped with the model or the rule, so a clip read by an older one is read again.
    static let version = 1

    /// A detection, in fractions of the upright picture.
    struct Box: Equatable {
        var minX: Double
        var minY: Double
        var maxX: Double
        var maxY: Double
        var score: Double
        var category: Int

        var width: Double { maxX - minX }
    }

    // MARK: - Reading a clip

    /// Reads `url`, reporting the fraction done; the stream's last element carries the sightings,
    /// which are kept, so a file is read once.
    public static func analyse(
        _ url: URL, rule: Rule = Rule()
    ) -> AsyncThrowingStream<(Double, CarSightings?), any Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .utility) {
                do {
                    let sightings = try await read(url, rule: rule) { continuation.yield(($0, nil)) }
                    try? save(sightings, for: url)
                    continuation.yield((1, sightings))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func read(_ url: URL, rule: Rule, progress: (Double) -> Void) async throws -> CarSightings {
        let asset = AVURLAsset(url: url)
        guard try await !asset.loadTracks(withMediaType: .video).isEmpty else {
            throw CompositionError.noVideoTrack(url)
        }
        let duration = try await asset.load(.duration).seconds
        let model = try detector()
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        // The keyframe nearest each second, when there is one within half a second.
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
        let times = stride(from: 0.0, to: max(duration, 0), by: 1).map { CMTime(seconds: $0, preferredTimescale: 600) }
        var result = CarSightings(duration: duration)
        var last = -Double.infinity
        for await picture in generator.images(for: times) {
            try Task.checkCancellation()
            guard let image = try? picture.image else { continue }
            let time = (try? picture.actualTime.seconds) ?? picture.requestedTime.seconds
            // A camera with keyframes further apart gives one picture for several seconds.
            guard time > last + 0.25 else { continue }
            last = time
            let width = try autoreleasepool { try nearestCarAhead(in: image, model: model, rule: rule) }
            result.times.append(time)
            result.widths.append(width)
            if result.times.count % 30 == 0 { progress(min(time / max(duration, 1), 1)) }
        }
        return result
    }

    /// The width of the nearest car close ahead in `image`, as a fraction of its width; 0 for none.
    static func nearestCarAhead(in image: CGImage, model: MLModel, rule: Rule) throws -> Double {
        let size = CGSize(width: image.width, height: image.height)
        let crop = CGRect(
            x: rule.crop.minX * size.width, y: rule.crop.minY * size.height, width: rule.crop.width * size.width,
            height: rule.crop.height * size.height
        ).integral
        guard let cropped = image.cropping(to: crop), let input = try letterboxed(cropped) else { return 0 }
        let output = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["images": input]))
        guard let name = model.modelDescription.outputDescriptionsByName.keys.first,
            let head = output.featureValue(for: name)?.multiArrayValue
        else { return 0 }
        let boxes = detections(head: head, crop: crop, picture: size)
        return carsAhead(boxes, rule: rule).map(\.width).max() ?? 0
    }

    /// `image` scaled to the model's input with its width filling it and grey above and below, as
    /// YOLOX was trained: BGR, 0–255, channels first.
    static func letterboxed(_ image: CGImage) throws -> MLMultiArray? {
        let side = inputSize
        guard
            let context = CGContext(
                data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(red: 114 / 255, green: 114 / 255, blue: 114 / 255, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        let height = Double(side) * Double(image.height) / Double(max(image.width, 1))
        context.interpolationQuality = .medium
        context.draw(
            image, in: CGRect(x: 0, y: (Double(side) - height) / 2, width: Double(side), height: height))
        guard let data = context.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: side * side * 4)
        let array = try MLMultiArray(shape: [1, 3, NSNumber(value: side), NSNumber(value: side)], dataType: .float16)
        let plane = side * side
        array.withUnsafeMutableBufferPointer(ofType: Float16.self) { buffer, _ in
            for index in 0..<plane {
                let pixel = index * 4
                buffer[index] = Float16(pixels[pixel + 2])
                buffer[plane + index] = Float16(pixels[pixel + 1])
                buffer[2 * plane + index] = Float16(pixels[pixel])
            }
        }
        return array
    }

    /// The vehicles in the model's raw head (anchors × [x, y, log w, log h, objectness, 80 class
    /// scores], on strides 8, 16 and 32), in fractions of the picture the crop came from, after
    /// non-maximum suppression within each class.
    static func detections(head: MLMultiArray, crop: CGRect, picture: CGSize, minimumScore: Double = 0.15) -> [Box] {
        let strides = head.strides.map(\.intValue)
        let count = head.shape[1].intValue
        let fields = head.shape[2].intValue
        // The head as plain numbers, anchor by anchor; Core ML pads its rows.
        var numbers = [Double](repeating: 0, count: count * fields)
        func copy<Element: BinaryFloatingPoint & MLShapedArrayScalar>(_ type: Element.Type) {
            head.withUnsafeBufferPointer(ofType: type) { buffer in
                for anchor in 0..<count {
                    for field in 0..<fields {
                        numbers[anchor * fields + field] = Double(buffer[anchor * strides[1] + field * strides[2]])
                    }
                }
            }
        }
        switch head.dataType {
        case .float16: copy(Float16.self)
        case .float32: copy(Float.self)
        default: copy(Double.self)
        }
        let value: (Int, Int) -> Double = { anchor, field in numbers[anchor * fields + field] }
        // Letterbox pixels to picture fractions.
        let scale = crop.width / Double(inputSize)
        let top = (Double(inputSize) - crop.height / scale) / 2
        func place(_ x: Double, _ y: Double) -> (Double, Double) {
            ((crop.minX + x * scale) / picture.width, (crop.minY + (y - top) * scale) / picture.height)
        }
        var found: [Box] = []
        var anchor = 0
        for stride in [8, 16, 32] {
            let cells = inputSize / stride
            for row in 0..<cells {
                for column in 0..<cells {
                    defer { anchor += 1 }
                    guard anchor < count else { continue }
                    let objectness = value(anchor, 4)
                    guard objectness >= minimumScore else { continue }
                    let category = vehicleClasses.max { value(anchor, 5 + $0) < value(anchor, 5 + $1) } ?? 2
                    let score = objectness * value(anchor, 5 + category)
                    guard score >= minimumScore else { continue }
                    let s = Double(stride)
                    let x = (value(anchor, 0) + Double(column)) * s
                    let y = (value(anchor, 1) + Double(row)) * s
                    let w = exp(value(anchor, 2)) * s
                    let h = exp(value(anchor, 3)) * s
                    let (minX, minY) = place(x - w / 2, y - h / 2)
                    let (maxX, maxY) = place(x + w / 2, y + h / 2)
                    found.append(
                        Box(minX: minX, minY: minY, maxX: maxX, maxY: maxY, score: score, category: category))
                }
            }
        }
        return suppressed(found)
    }

    /// The boxes left when each overlaps no higher-scoring box of its class by half or more.
    static func suppressed(_ boxes: [Box], overlap: Double = 0.5) -> [Box] {
        var kept: [Box] = []
        for box in boxes.sorted(by: { $0.score > $1.score }) {
            let clashes = kept.contains { other in
                guard other.category == box.category else { return false }
                let width = min(box.maxX, other.maxX) - max(box.minX, other.minX)
                let height = min(box.maxY, other.maxY) - max(box.minY, other.minY)
                guard width > 0, height > 0 else { return false }
                let shared = width * height
                let areas =
                    (box.maxX - box.minX) * (box.maxY - box.minY)
                    + (other.maxX - other.minX) * (other.maxY - other.minY)
                let union = areas - shared
                return shared / union >= overlap
            }
            if !clashes { kept.append(box) }
        }
        return kept
    }

    /// The boxes the rule says are a car close ahead on the circuit.
    static func carsAhead(_ boxes: [Box], rule: Rule) -> [Box] {
        boxes.filter { box in
            box.score >= rule.minimumScore && (rule.minimumWidth...rule.maximumWidth).contains(box.width)
                && rule.centre.contains((box.minX + box.maxX) / 2) && box.maxY >= rule.lowestTop
        }
    }

    /// The bundled detector, on the Neural Engine where there is one.
    static func detector() throws -> MLModel {
        guard let url = Bundle.module.url(forResource: "TrafficDetector", withExtension: "mlmodelc") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        return try MLModel(contentsOf: url, configuration: configuration)
    }

    // MARK: - Kept between runs

    /// Where the reading of `url` is kept: by its path, size and modification date, and the
    /// detector's version, so an edited file or a new detector reads it afresh.
    static func cacheURL(for url: URL, environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            let size = attributes[.size] as? Int, let modified = attributes[.modificationDate] as? Date
        else { return nil }
        let key = "\(url.standardizedFileURL.path)|\(size)|\(modified.timeIntervalSince1970)|\(version)"
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return cacheFolder(environment: environment).appending(path: "\(digest.prefix(32)).json")
    }

    /// Application Support, or the UI tests' own folder for each launch, as the picture's motion.
    static func cacheFolder(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let folder = environment["ONBOARD_TEST_MOTION_DIR"] {
            return URL(fileURLWithPath: folder, isDirectory: true).appending(path: "Traffic")
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appending(path: "OnboardStudio/Traffic")
    }

    /// The reading made earlier of this very file, if there is one.
    public static func saved(for url: URL) -> CarSightings? {
        guard let cache = cacheURL(for: url), let data = try? Data(contentsOf: cache) else { return nil }
        return try? JSONDecoder().decode(CarSightings.self, from: data)
    }

    static func save(_ sightings: CarSightings, for url: URL) throws {
        guard let cache = cacheURL(for: url) else { return }
        let folder = cache.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(sightings).write(to: cache, options: .atomic)
    }
}
