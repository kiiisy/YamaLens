import Foundation
import Testing
@testable import YamaLens

struct OfflinePackageDistributionTests {
    @Test("個人利用MVPの丹沢パック更新を確認できる")
    func offersUpdateForRemoteDistribution() {
        #expect(OfflinePackageDistributionAvailability.available.canUpdate)
    }
}
