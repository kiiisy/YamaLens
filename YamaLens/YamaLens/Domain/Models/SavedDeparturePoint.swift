import Foundation
import SwiftData

@Model
final class SavedDeparturePoint {
    @Attribute(.unique) var identifier: String
    var name: String
    var updatedAt: Date

    init(
        name: String,
        updatedAt: Date = .now
    ) {
        identifier = "frequent-departure-station"
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.updatedAt = updatedAt
    }

    func replace(
        name: String,
        updatedAt: Date = .now
    ) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.updatedAt = updatedAt
    }
}
