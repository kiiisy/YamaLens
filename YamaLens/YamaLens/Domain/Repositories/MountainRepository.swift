import Foundation

nonisolated protocol MountainRepository: Sendable {
    func fetchMountains() -> [Mountain]
}
