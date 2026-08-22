import Foundation

nonisolated struct OfflinePackageNetworkPolicy: Equatable, Sendable {
    let metadataRequestTimeoutSeconds: TimeInterval
    let packageRequestTimeoutSeconds: TimeInterval
    let resourceTimeoutSeconds: TimeInterval
    let retryDelaySeconds: TimeInterval
    let maximumManifestBytes: Int64
    let signatureBytes: Int64
    let allowsCellularAccess: Bool

    static let `default` = OfflinePackageNetworkPolicy(
        metadataRequestTimeoutSeconds: 15,
        packageRequestTimeoutSeconds: 30,
        resourceTimeoutSeconds: 2 * 60 * 60,
        retryDelaySeconds: 2,
        maximumManifestBytes: 256 * 1_024,
        signatureBytes: 64,
        allowsCellularAccess: false
    )
}
