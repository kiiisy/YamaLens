import Foundation

nonisolated struct SpatialVector: Equatable, Sendable {
    let x: Double
    let y: Double
    let z: Double

    func dot(_ other: SpatialVector) -> Double {
        x * other.x + y * other.y + z * other.z
    }
}

nonisolated struct ViewportPoint: Equatable, Sendable {
    let x: Double
    let y: Double
}

nonisolated struct ViewportSize: Equatable, Sendable {
    let width: Double
    let height: Double
}

nonisolated struct NormalizedImageTransform: Equatable, Sendable {
    let a: Double
    let b: Double
    let c: Double
    let d: Double
    let translationX: Double
    let translationY: Double

    func applying(to point: ViewportPoint) -> ViewportPoint {
        ViewportPoint(
            x: a * point.x + c * point.y + translationX,
            y: b * point.x + d * point.y + translationY
        )
    }
}

nonisolated struct CameraProjectionGeometry: Equatable, Sendable {
    let cameraRightInWorld: SpatialVector
    let cameraUpInWorld: SpatialVector
    let cameraBackInWorld: SpatialVector
    let focalLengthXPixels: Double
    let focalLengthYPixels: Double
    let principalPointXPixels: Double
    let principalPointYPixels: Double
    let imageSizePixels: ViewportSize
    let normalizedImageToViewport: NormalizedImageTransform
    let viewportSizePoints: ViewportSize
    let horizontalFieldOfViewDegrees: Double
    let verticalFieldOfViewDegrees: Double

    func project(worldDirection: SpatialVector) -> ViewportPoint? {
        guard isValid else { return nil }

        let cameraX = worldDirection.dot(cameraRightInWorld)
        let cameraY = worldDirection.dot(cameraUpInWorld)
        let cameraZ = worldDirection.dot(cameraBackInWorld)
        let depth = -cameraZ
        guard depth.isFinite, depth > 0 else { return nil }

        let imagePoint = ViewportPoint(
            x: focalLengthXPixels * cameraX / depth + principalPointXPixels,
            y: principalPointYPixels - focalLengthYPixels * cameraY / depth
        )
        let normalizedPoint = ViewportPoint(
            x: imagePoint.x / imageSizePixels.width,
            y: imagePoint.y / imageSizePixels.height
        )
        let viewportPoint = normalizedImageToViewport.applying(to: normalizedPoint)
        return ViewportPoint(
            x: viewportPoint.x * viewportSizePoints.width,
            y: viewportPoint.y * viewportSizePoints.height
        )
    }

    private var isValid: Bool {
        let values = [
            focalLengthXPixels,
            focalLengthYPixels,
            principalPointXPixels,
            principalPointYPixels,
            imageSizePixels.width,
            imageSizePixels.height,
            viewportSizePoints.width,
            viewportSizePoints.height,
            horizontalFieldOfViewDegrees,
            verticalFieldOfViewDegrees,
        ]
        return values.allSatisfy(\.isFinite)
            && focalLengthXPixels > 0
            && focalLengthYPixels > 0
            && imageSizePixels.width > 0
            && imageSizePixels.height > 0
            && viewportSizePoints.width > 0
            && viewportSizePoints.height > 0
            && horizontalFieldOfViewDegrees > 0
            && verticalFieldOfViewDegrees > 0
    }
}
