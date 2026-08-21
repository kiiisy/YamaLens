import CoreGraphics

struct CameraLabelAnchor: Equatable {
    let id: String
    let point: CGPoint
}

struct CameraLabelPlacement: Equatable {
    let id: String
    let anchor: CGPoint
    let labelCenter: CGPoint
}

struct CameraLabelPlacementResolver {
    private let labelSize: CGSize
    private let minimumSpacing: CGFloat = 8
    private let horizontalMargin: CGFloat = 10
    private let topReservedSpace: CGFloat = 72
    private let bottomReservedSpace: CGFloat = 250

    init(labelSize: CGSize = CGSize(width: 168, height: 54)) {
        self.labelSize = labelSize
    }

    func resolve(
        anchors: [CameraLabelAnchor],
        viewportSize: CGSize
    ) -> [CameraLabelPlacement] {
        guard viewportSize.width > 0, viewportSize.height > 0 else { return [] }

        let availableBounds = labelBounds(in: viewportSize)
        var occupiedFrames: [CGRect] = []
        let markerFrames = anchors.map { anchor in
            CGRect(
                x: anchor.point.x - 8,
                y: anchor.point.y - 8,
                width: 16,
                height: 16
            )
        }

        return anchors.map { anchor in
            let centers = candidateCenters(for: anchor.point).map {
                clamped($0, to: availableBounds)
            }
            let center = centers.first { candidateCenter in
                let frame = labelFrame(centeredAt: candidateCenter)
                return occupiedFrames.allSatisfy { occupiedFrame in
                    !frame.insetBy(dx: -minimumSpacing, dy: -minimumSpacing)
                        .intersects(occupiedFrame)
                }
                    && markerFrames.allSatisfy { !frame.intersects($0) }
            } ?? bestAvailableCenter(from: centers, occupiedFrames: occupiedFrames)

            occupiedFrames.append(labelFrame(centeredAt: center))
            return CameraLabelPlacement(
                id: anchor.id,
                anchor: anchor.point,
                labelCenter: center
            )
        }
    }

    private func labelBounds(in viewportSize: CGSize) -> CGRect {
        let halfWidth = labelSize.width / 2
        let halfHeight = labelSize.height / 2
        let minimumY = topReservedSpace + halfHeight
        let preferredMaximumY = viewportSize.height - bottomReservedSpace - halfHeight
        let maximumY = max(minimumY, preferredMaximumY)

        return CGRect(
            x: horizontalMargin + halfWidth,
            y: minimumY,
            width: max(viewportSize.width - (horizontalMargin + halfWidth) * 2, 0),
            height: max(maximumY - minimumY, 0)
        )
    }

    private func candidateCenters(for anchor: CGPoint) -> [CGPoint] {
        let initialVerticalOffset = labelSize.height / 2 + 18
        let verticalStep = labelSize.height + minimumSpacing
        let horizontalOffset = labelSize.width * 0.62

        return [
            CGPoint(x: anchor.x, y: anchor.y - initialVerticalOffset),
            CGPoint(x: anchor.x, y: anchor.y - initialVerticalOffset - verticalStep),
            CGPoint(x: anchor.x, y: anchor.y + initialVerticalOffset),
            CGPoint(x: anchor.x, y: anchor.y - initialVerticalOffset - verticalStep * 2),
            CGPoint(x: anchor.x, y: anchor.y + initialVerticalOffset + verticalStep),
            CGPoint(x: anchor.x - horizontalOffset, y: anchor.y - verticalStep),
            CGPoint(x: anchor.x + horizontalOffset, y: anchor.y - verticalStep),
            CGPoint(x: anchor.x - horizontalOffset, y: anchor.y + verticalStep),
            CGPoint(x: anchor.x + horizontalOffset, y: anchor.y + verticalStep)
        ]
    }

    private func clamped(_ point: CGPoint, to bounds: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )
    }

    private func labelFrame(centeredAt center: CGPoint) -> CGRect {
        CGRect(
            x: center.x - labelSize.width / 2,
            y: center.y - labelSize.height / 2,
            width: labelSize.width,
            height: labelSize.height
        )
    }

    private func bestAvailableCenter(
        from centers: [CGPoint],
        occupiedFrames: [CGRect]
    ) -> CGPoint {
        guard let firstCenter = centers.first else { return .zero }
        guard !occupiedFrames.isEmpty else { return firstCenter }

        return centers.max { first, second in
            minimumDistance(from: first, to: occupiedFrames)
                < minimumDistance(from: second, to: occupiedFrames)
        } ?? firstCenter
    }

    private func minimumDistance(from center: CGPoint, to frames: [CGRect]) -> CGFloat {
        frames.map { frame in
            hypot(center.x - frame.midX, center.y - frame.midY)
        }.min() ?? 0
    }
}
