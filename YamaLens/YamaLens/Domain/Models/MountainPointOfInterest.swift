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
    let details: [MountainPointOfInterestDetail]

    init(
        id: String,
        type: MountainPointOfInterestType,
        name: String,
        coordinate: GeoCoordinate?,
        summary: String,
        officialURL: URL,
        checkedAt: Date,
        sourceProvider: String,
        details: [MountainPointOfInterestDetail] = []
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.coordinate = coordinate
        self.summary = summary
        self.officialURL = officialURL
        self.checkedAt = checkedAt
        self.sourceProvider = sourceProvider
        self.details = details
    }
}

nonisolated enum MountainPointOfInterestDetailKind: String, CaseIterable, Sendable {
    case operatingPeriod
    case reservation
    case capacity
    case fee
    case openingHours
    case closedDays
    case access
    case transportOperator

    var displayName: String {
        switch self {
        case .operatingPeriod: "営業期間"
        case .reservation: "予約"
        case .capacity: "収容台数"
        case .fee: "料金"
        case .openingHours: "利用時間"
        case .closedDays: "休業日"
        case .access: "アクセス"
        case .transportOperator: "運行事業者"
        }
    }
}

nonisolated struct MountainPointOfInterestDetail: Equatable, Sendable {
    let kind: MountainPointOfInterestDetailKind
    let value: String
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
