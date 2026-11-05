import CoreGraphics
import Foundation
import ProjectModel
import SceneKit
import simd

/// `MeshArrays` as SceneKit geometry (#414), through the raw-data sources so nothing is copied
/// into `SCNVector3`s on the way.
extension MeshArrays {
    public func geometry() -> SCNGeometry {
        let stride3 = MemoryLayout<SIMD3<Float>>.stride
        let stride2 = MemoryLayout<SIMD2<Float>>.stride
        let positionSource = positions.withUnsafeBytes { bytes in
            SCNGeometrySource(
                data: Data(bytes), semantic: .vertex, vectorCount: positions.count, usesFloatComponents: true,
                componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: stride3)
        }
        let normalSource = normals.withUnsafeBytes { bytes in
            SCNGeometrySource(
                data: Data(bytes), semantic: .normal, vectorCount: normals.count, usesFloatComponents: true,
                componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: stride3)
        }
        let uvSource = uvs.withUnsafeBytes { bytes in
            SCNGeometrySource(
                data: Data(bytes), semantic: .texcoord, vectorCount: uvs.count, usesFloatComponents: true,
                componentsPerVector: 2, bytesPerComponent: 4, dataOffset: 0, dataStride: stride2)
        }
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        return SCNGeometry(sources: [positionSource, normalSource, uvSource], elements: [element])
    }
}

/// Small pictures the scene needs: a kerb's stripes, a label's text.
enum SceneImages {
    /// Two pixels, red then white, tiled along a kerb.
    static func kerbStripes() -> CGImage? {
        let space = CGColorSpaceCreateDeviceRGB()
        guard
            let context = CGContext(
                data: nil, width: 1, height: 2, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(red: 0.85, green: 0.12, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        context.setFillColor(CGColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1))
        context.fill(CGRect(x: 0, y: 1, width: 1, height: 1))
        return context.makeImage()
    }

    /// `text` on a rounded dark pill in `color`'s hue, sized to fit; `nil` for empty text.
    static func label(_ text: String, color: RGBAColor, pointSize: Double = 28) -> CGImage? {
        guard !text.isEmpty else { return nil }
        let style = TextDrawing.Style(fontName: "Helvetica Neue", pointSize: pointSize, color: .white, weightBold: true)
        let measured = TextDrawing.size(of: text, style: style)
        let padding = pointSize * 0.5
        let width = Int((measured.width + padding * 2).rounded(.up))
        let height = Int((measured.height + padding).rounded(.up))
        let space = CGColorSpaceCreateDeviceRGB()
        guard
            let context = CGContext(
                data: nil, width: max(width, 2), height: max(height, 2), bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        let pill = CGPath(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerWidth: 6, cornerHeight: 6, transform: nil)
        context.addPath(pill)
        context.setFillColor(CGColor(red: 0.08, green: 0.08, blue: 0.1, alpha: 0.85))
        context.fillPath()
        context.addPath(pill)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(2)
        context.strokePath()
        // Core Graphics draws text with the origin at the bottom; `TextDrawing` assumes a context
        // flipped to top-left, as the overlay buffer is.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        TextDrawing.drawCentered(
            text, at: CGPoint(x: Double(width) / 2, y: Double(height) / 2), style: style, in: context)
        return context.makeImage()
    }
}
