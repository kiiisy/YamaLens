import Foundation
import SwiftData

@Model
final class UserMountainRecord {
    @Attribute(.unique) var mountainID: String
    var isFavorite: Bool
    var isSummited: Bool
    var beforeNote: String
    var duringNote: String
    var afterNote: String
    @Attribute(.externalStorage) var heroImageData: Data?
    var lastViewedAt: Date?
    var summitedAt: Date?

    init(
        mountainID: String,
        isFavorite: Bool = false,
        isSummited: Bool = false,
        beforeNote: String = "",
        duringNote: String = "",
        afterNote: String = "",
        heroImageData: Data? = nil,
        lastViewedAt: Date? = nil,
        summitedAt: Date? = nil
    ) {
        self.mountainID = mountainID
        self.isFavorite = isFavorite
        self.isSummited = isSummited
        self.beforeNote = beforeNote
        self.duringNote = duringNote
        self.afterNote = afterNote
        self.heroImageData = heroImageData
        self.lastViewedAt = lastViewedAt
        self.summitedAt = summitedAt
    }
}
