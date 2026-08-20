import Foundation

nonisolated struct Mountain: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let name: String
    let aliases: [String]
    let regionName: String
    let prefectureName: String
    let elevationMeters: Int
    let coordinate: GeoCoordinate

    var searchableText: String {
        ([name] + aliases + [regionName, prefectureName])
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
