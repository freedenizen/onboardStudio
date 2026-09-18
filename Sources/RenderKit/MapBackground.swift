import CoreGraphics
import Foundation
import ProjectModel
import TelemetryKit

/// The geographic window a map background must cover, rounded so repeated loads hit the cache.
public struct MapBackgroundRequest: Hashable, Sendable, Codable {
    public let minLatitude: Double
    public let maxLatitude: Double
    public let minLongitude: Double
    public let maxLongitude: Double
    public let style: MapBackgroundStyle

    public init(
        minLatitude: Double, maxLatitude: Double, minLongitude: Double, maxLongitude: Double, style: MapBackgroundStyle
    ) {
        self.minLatitude = minLatitude
        self.maxLatitude = maxLatitude
        self.minLongitude = minLongitude
        self.maxLongitude = maxLongitude
        self.style = style
    }

    /// The session's GPS bounds grown by 60% on every side (room for rotation), to 0.0001°.
    public init?(session: TelemetrySession, style: MapBackgroundStyle) {
        guard style != .none, let lat = session[.latitude], let lon = session[.longitude],
            let latMin = lat.minValue, let latMax = lat.maxValue, let lonMin = lon.minValue,
            let lonMax = lon.maxValue, latMax > latMin || lonMax > lonMin
        else { return nil }
        let padLat = max(latMax - latMin, 0.0005) * 0.6
        let padLon = max(lonMax - lonMin, 0.0005) * 0.6
        func round4(_ v: Double) -> Double { (v * 10000).rounded() / 10000 }
        self.init(
            minLatitude: round4(latMin - padLat), maxLatitude: round4(latMax + padLat),
            minLongitude: round4(lonMin - padLon), maxLongitude: round4(lonMax + padLon), style: style)
    }

    public var centerLatitude: Double { (minLatitude + maxLatitude) / 2 }
    public var centerLongitude: Double { (minLongitude + maxLongitude) / 2 }
}

/// A map image with a linear latitude/longitude → pixel mapping (accurate over a circuit-sized
/// area). Built by MediaKit from an `MKMapSnapshotter` result, or synthetically in tests.
public struct MapBackground: @unchecked Sendable {
    public let request: MapBackgroundRequest
    public let image: CGImage
    /// Pixel (top-left origin) of the request's centre.
    public let centerPoint: CGPoint
    public let pixelsPerDegreeLongitude: Double
    /// Positive; pixel y decreases as latitude increases.
    public let pixelsPerDegreeLatitude: Double

    public init(
        request: MapBackgroundRequest, image: CGImage, centerPoint: CGPoint, pixelsPerDegreeLongitude: Double,
        pixelsPerDegreeLatitude: Double
    ) {
        self.request = request
        self.image = image
        self.centerPoint = centerPoint
        self.pixelsPerDegreeLongitude = pixelsPerDegreeLongitude
        self.pixelsPerDegreeLatitude = pixelsPerDegreeLatitude
    }

    public func point(latitude: Double, longitude: Double) -> CGPoint {
        CGPoint(
            x: centerPoint.x + (longitude - request.centerLongitude) * pixelsPerDegreeLongitude,
            y: centerPoint.y - (latitude - request.centerLatitude) * pixelsPerDegreeLatitude)
    }
}
