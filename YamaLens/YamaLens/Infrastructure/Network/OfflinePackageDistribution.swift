import Foundation

nonisolated enum OfflinePackageDistribution {
    static let tanzawaPackageID = "jp.kanagawa.tanzawa"

    static func tanzawaSourceResolver() throws -> any OfflinePackageSourceResolving {
        guard let releaseIndexURL = URL(
            string: "https://packages.yamalens.com/tanzawa/release.json"
        ),
        let releaseSignatureURL = URL(
            string: "https://packages.yamalens.com/tanzawa/release.sig"
        ),
        let packageBaseURL = URL(
            string: "https://packages.yamalens.com/tanzawa/"
        ) else {
            throw OfflinePackageReleaseIndexError.invalidURL
        }
        return try RemoteOfflinePackageSourceResolver(
            releaseIndexURL: releaseIndexURL,
            releaseSignatureURL: releaseSignatureURL,
            expectedPackageID: tanzawaPackageID,
            packageBaseURL: packageBaseURL,
            publicKeys: OfflinePackageVerificationKeys.all
        )
    }
}
