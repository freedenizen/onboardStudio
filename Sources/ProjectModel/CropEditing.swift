import Foundation

/// The shapes a crop can be held to on the preview (#276), as Photos offers them.
public enum CropAspect: String, CaseIterable, Sendable, Identifiable {
    case free, original, wide, tall, standard, square

    public var id: Self { self }

    /// Width over height, or `nil` when the crop may take any shape; `original` is the picture's.
    public func ratio(picture: Double) -> Double? {
        switch self {
        case .free: nil
        case .original: picture
        case .wide: 16.0 / 9
        case .tall: 9.0 / 16
        case .standard: 4.0 / 3
        case .square: 1
        }
    }

    public var displayName: String {
        switch self {
        case .free: "Freeform"
        case .original: "Original"
        case .wide: "16:9"
        case .tall: "9:16"
        case .standard: "4:3"
        case .square: "Square"
        }
    }
}

/// The geometry of cropping a video on the preview (#276). A video's crop is stored against its
/// source picture, before it is flipped and turned (`VideoTransform`); the preview shows it flipped
/// and turned, so the crop is carried across both ways. Insets and rectangles are unit fractions.
public enum CropEditing {
    /// Each edge may be cut back this far, as in the inspector.
    public static let maximumInset = 0.45
    /// The least of the picture a crop leaves, across and down.
    public static let minimumSize = 0.1

    /// The crop as it looks on the preview: flipped, then turned clockwise by `rotation`.
    public static func displayed(_ crop: CropInsets, rotation: Double, mirror: Mirror) -> CropInsets {
        var c = crop
        if mirror.horizontal { swap(&c.left, &c.right) }
        if mirror.vertical { swap(&c.top, &c.bottom) }
        for _ in 0..<quarterTurns(rotation) {
            // Clockwise: what was on the left is now on top.
            c = CropInsets(top: c.left, left: c.bottom, bottom: c.right, right: c.top)
        }
        return c
    }

    /// The source crop for one drawn on the preview: `displayed` undone.
    public static func source(_ shown: CropInsets, rotation: Double, mirror: Mirror) -> CropInsets {
        var c = shown
        for _ in 0..<quarterTurns(rotation) {
            c = CropInsets(top: c.right, left: c.top, bottom: c.left, right: c.bottom)
        }
        if mirror.vertical { swap(&c.top, &c.bottom) }
        if mirror.horizontal { swap(&c.left, &c.right) }
        return c
    }

    static func quarterTurns(_ rotation: Double) -> Int { Int((rotation / 90).rounded()) & 3 }

    public static func region(of crop: CropInsets) -> UnitRect {
        UnitRect(
            x: crop.left, y: crop.top, width: max(0, 1 - crop.left - crop.right),
            height: max(0, 1 - crop.top - crop.bottom))
    }

    /// Which part of the crop rectangle a point is on: a corner, an edge anywhere along it, or
    /// inside. `tolerance` is in the same unit fractions, across and down.
    public static func handle(at point: CGPoint, in rect: UnitRect, tolerance: CGSize) -> ObjectHandle? {
        let nearLeft = abs(point.x - rect.x) <= tolerance.width
        let nearRight = abs(point.x - (rect.x + rect.width)) <= tolerance.width
        let nearTop = abs(point.y - rect.y) <= tolerance.height
        let nearBottom = abs(point.y - (rect.y + rect.height)) <= tolerance.height
        let across = point.x >= rect.x - tolerance.width && point.x <= rect.x + rect.width + tolerance.width
        let down = point.y >= rect.y - tolerance.height && point.y <= rect.y + rect.height + tolerance.height
        guard across, down else { return nil }
        switch (nearLeft, nearRight, nearTop, nearBottom) {
        case (true, _, true, _): return .topLeft
        case (_, true, true, _): return .topRight
        case (true, _, _, true): return .bottomLeft
        case (_, true, _, true): return .bottomRight
        case (true, _, _, _): return .left
        case (_, true, _, _): return .right
        case (_, _, true, _): return .top
        case (_, _, _, true): return .bottom
        default: return .body
        }
    }

    /// `crop` (as shown) with `handle` dragged by `dx`, `dy`. Edges stop at `maximumInset` and at
    /// `minimumSize`; the body moves the whole window, keeping its size. With `ratio` (width over
    /// height in pixels, the picture being `pictureAspect`), a corner keeps that shape.
    public static func dragged(
        _ crop: CropInsets, handle: ObjectHandle, dx: Double, dy: Double, ratio: Double? = nil,
        pictureAspect: Double = 16.0 / 9
    ) -> CropInsets {
        var c = crop
        if handle == .body {
            let x = min(max(dx, -c.left), c.right)
            let y = min(max(dy, -c.top), c.bottom)
            c.left += x
            c.right -= x
            c.top += y
            c.bottom -= y
            return clampedInsets(c)
        }
        if handle.movesLeftEdge { c.left = limit(c.left + dx, opposite: c.right) }
        if [.topRight, .right, .bottomRight].contains(handle) { c.right = limit(c.right - dx, opposite: c.left) }
        if handle.movesTopEdge { c.top = limit(c.top + dy, opposite: c.bottom) }
        if [.bottomLeft, .bottom, .bottomRight].contains(handle) { c.bottom = limit(c.bottom - dy, opposite: c.top) }
        guard let ratio, handle.resizesHorizontally, handle.resizesVertically else { return c }
        // A corner held to a shape: the width leads and the height follows, unless that would run
        // past the picture, when the height stops there and the width follows it instead.
        let fixedAcross = handle.movesLeftEdge ? c.right : c.left
        let fixedDown = handle.movesTopEdge ? c.bottom : c.top
        var width = 1 - c.left - c.right
        var height = width * pictureAspect / ratio
        if height > 1 - fixedDown {
            height = 1 - fixedDown
            width = height * ratio / pictureAspect
        }
        if handle.movesLeftEdge { c.left = 1 - fixedAcross - width } else { c.right = 1 - fixedAcross - width }
        if handle.movesTopEdge { c.top = 1 - fixedDown - height } else { c.bottom = 1 - fixedDown - height }
        return c
    }

    /// The largest crop of shape `ratio` (width over height in pixels) centred in a picture of
    /// `pictureAspect`, within the insets allowed.
    public static func fitted(ratio: Double, pictureAspect: Double) -> CropInsets {
        guard ratio > 0, pictureAspect > 0 else { return .none }
        var width = 1.0
        var height = pictureAspect / ratio
        if height > 1 {
            width = ratio / pictureAspect
            height = 1
        }
        width = max(width, 1 - 2 * maximumInset)
        height = max(height, 1 - 2 * maximumInset)
        return CropInsets(
            top: (1 - height) / 2, left: (1 - width) / 2, bottom: (1 - height) / 2, right: (1 - width) / 2)
    }

    static func limit(_ inset: Double, opposite: Double) -> Double {
        min(max(inset, 0), maximumInset, 1 - opposite - minimumSize)
    }

    static func clampedInsets(_ c: CropInsets) -> CropInsets {
        CropInsets(
            top: min(max(c.top, 0), maximumInset), left: min(max(c.left, 0), maximumInset),
            bottom: min(max(c.bottom, 0), maximumInset), right: min(max(c.right, 0), maximumInset))
    }
}
