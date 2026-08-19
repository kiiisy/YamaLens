import Foundation

protocol MountainRepository: Sendable {
    func fetchMountains() -> [Mountain]
}
