import Foundation

nonisolated enum MountainCoverageRole: String, Equatable, Hashable, Sendable {
    case core
    case surroundingCandidate
}

nonisolated struct Mountain: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let name: String
    let aliases: [String]
    let regionName: String
    let prefectureName: String
    let elevationMeters: Int
    let coordinate: GeoCoordinate
    let coverageRole: MountainCoverageRole

    init(
        id: String,
        name: String,
        aliases: [String],
        regionName: String,
        prefectureName: String,
        elevationMeters: Int,
        coordinate: GeoCoordinate,
        coverageRole: MountainCoverageRole = .core
    ) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.regionName = regionName
        self.prefectureName = prefectureName
        self.elevationMeters = elevationMeters
        self.coordinate = coordinate
        self.coverageRole = coverageRole
    }

    var searchableText: String {
        ([name] + aliases + [regionName, prefectureName])
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
