/// The geometry of framing on the preview (#275): where the framed window sits on the whole shot,
/// and how moving or resizing it changes the project's `CameraFraming`. All rectangles are unit
/// fractions of the picture as it is shown while framing — every video's own crop applied, the
/// framing not — which is the picture `CameraFraming` is expressed against.
public enum FramingEditing {
    /// The least and most the frame may be zoomed from the preview, as the inspector allows.
    public static let zoomRange: ClosedRange<Double> = 1...4

    /// The part of the shot the finished video shows.
    public static func region(of framing: CameraFraming) -> UnitRect {
        let crop = framing.effectiveCrop(over: .none)
        return UnitRect(
            x: crop.left, y: crop.top, width: max(0, 1 - crop.left - crop.right),
            height: max(0, 1 - crop.top - crop.bottom))
    }

    /// The framing with its window moved by `dx`, `dy` (fractions of the shown picture), kept
    /// inside the picture so there is never a stretch of drag that does nothing.
    public static func moved(_ framing: CameraFraming, dx: Double, dy: Double) -> CameraFraming {
        var result = framing
        let trimmedWidth = max(1 - framing.crop.left - framing.crop.right, 0.0001)
        let trimmedHeight = max(1 - framing.crop.top - framing.crop.bottom, 0.0001)
        let half = 0.5 / max(framing.zoom, 1)
        result.centerX = min(max(framing.centerX + dx / trimmedWidth, half), 1 - half)
        result.centerY = min(max(framing.centerY + dy / trimmedHeight, half), 1 - half)
        return result
    }

    /// The framing zoomed by `factor` about its centre (2 = twice as close), within `zoomRange`,
    /// with the centre pulled back inside the picture if the wider window would overhang it.
    public static func zoomed(_ framing: CameraFraming, by factor: Double) -> CameraFraming {
        guard factor.isFinite, factor > 0 else { return framing }
        var result = framing
        result.zoom = min(max(framing.zoom * factor, zoomRange.lowerBound), zoomRange.upperBound)
        return moved(result, dx: 0, dy: 0)
    }

    /// The framing whose window is `width` wide (a fraction of the shown picture), as dragging a
    /// corner of it asks for; the window keeps its centre and its shape.
    public static func resized(_ framing: CameraFraming, toWidth width: Double) -> CameraFraming {
        let trimmedWidth = max(1 - framing.crop.left - framing.crop.right, 0.0001)
        guard width > 0 else { return zoomed(framing, by: zoomRange.upperBound / framing.zoom) }
        return zoomed(framing, by: (trimmedWidth / width) / framing.zoom)
    }
}
