import Foundation

nonisolated enum MountainPointOfInterestType: String, CaseIterable, Sendable {
    case mountainHut
    case trailhead
    case parking
    case publicTransport
    case cableway
    case hotSpring
}

nonisolated struct MountainPointOfInterest: Identifiable, Equatable, Sendable {
    let id: String
    let type: MountainPointOfInterestType
    let name: String
    let coordinate: GeoCoordinate?
    let summary: String
    let officialURL: URL
    let checkedAt: Date
    let sourceProvider: String
}

nonisolated struct TrailheadAccessGuide: Identifiable, Equatable, Sendable {
    let trailhead: MountainPointOfInterest
    let accessPoints: [MountainPointOfInterest]
    let nearbySearchAreas: [NearbySearchArea]

    var id: String { trailhead.id }
}

nonisolated struct NearbySearchArea: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
}
