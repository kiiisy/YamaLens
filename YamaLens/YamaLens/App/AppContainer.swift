import Foundation

struct AppContainer: Sendable {
    let mountainRepository: any MountainRepository

    init(mountainRepository: any MountainRepository = BootstrapMountainRepository()) {
        self.mountainRepository = mountainRepository
    }
}
