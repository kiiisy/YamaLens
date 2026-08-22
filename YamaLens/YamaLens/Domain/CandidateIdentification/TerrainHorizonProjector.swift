import Foundation

nonisolated struct TerrainHorizonProjector: Sendable {
    func project(
        _ samples: [TerrainHorizonSample],
        camera: CameraPoseObservation,
        manualHeadingCorrectionDegrees: Double
    ) -> [[ViewportPoint]] {
        guard manualHeadingCorrectionDegrees.isFinite else { return [] }
        var segments: [[ViewportPoint]] = []
        var currentSegment: [ViewportPoint] = []

        for sample in samples {
            guard
                sample.bearingDegrees.isFinite,
                let elevationAngleDegrees = sample.elevationAngleDegrees,
                elevationAngleDegrees.isFinite,
                let point = camera.projectionGeometry.project(
                    worldDirection: corrected(
                        direction(
                            bearingDegrees: sample.bearingDegrees,
                            elevationAngleDegrees: elevationAngleDegrees
                        ),
                        byDegrees: manualHeadingCorrectionDegrees
                    )
                ),
                isInsideViewport(point, geometry: camera.projectionGeometry)
            else {
                appendIfDrawable(currentSegment, to: &segments)
                currentSegment = []
                continue
            }
            currentSegment.append(point)
        }
        appendIfDrawable(currentSegment, to: &segments)
        return segments
    }

    private func direction(
        bearingDegrees: Double,
        elevationAngleDegrees: Double
    ) -> SpatialVector {
        let bearing = bearingDegrees * .pi / 180
        let elevation = elevationAngleDegrees * .pi / 180
        let horizontal = cos(elevation)
        return SpatialVector(
            x: horizontal * sin(bearing),
            y: sin(elevation),
            z: -horizontal * cos(bearing)
        )
    }

    private func corrected(
        _ direction: SpatialVector,
        byDegrees correctionDegrees: Double
    ) -> SpatialVector {
        let radians = correctionDegrees * .pi / 180
        let cosine = cos(radians)
        let sine = sin(radians)
        return SpatialVector(
            x: direction.x * cosine - direction.z * sine,
            y: direction.y,
            z: direction.x * sine + direction.z * cosine
        )
    }

    private func isInsideViewport(
        _ point: ViewportPoint,
        geometry: CameraProjectionGeometry
    ) -> Bool {
        point.x >= 0
            && point.x <= geometry.viewportSizePoints.width
            && point.y >= 0
            && point.y <= geometry.viewportSizePoints.height
    }

    private func appendIfDrawable(
        _ segment: [ViewportPoint],
        to segments: inout [[ViewportPoint]]
    ) {
        guard segment.count >= 2 else { return }
        segments.append(segment)
    }
}
