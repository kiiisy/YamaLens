import Foundation

nonisolated enum OfflinePackageDownloadError: Error, Equatable, Sendable {
    case temporaryFailure
    case permanentFailure
    case cancelled
    case responseTooLarge
    case invalidResponse
    case invalidDownloadedFile
}

nonisolated protocol OfflinePackageFileDownloading: Sendable {
    func download(
        from sourceURL: URL,
        to destinationURL: URL,
        maximumBytes: Int64,
        requestTimeoutSeconds: TimeInterval
    ) async throws
}

actor BackgroundOfflinePackageFileDownloader: OfflinePackageFileDownloading {
    private let session: URLSession
    private let fileManager: FileManager

    init(
        identifier: String = "com.kiiisy.YamaLens.offline-packages",
        policy: OfflinePackageNetworkPolicy = .default,
        fileManager: FileManager = .default
    ) {
        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = policy.packageRequestTimeoutSeconds
        configuration.timeoutIntervalForResource = policy.resourceTimeoutSeconds
        configuration.allowsCellularAccess = policy.allowsCellularAccess
        session = URLSession(configuration: configuration)
        self.fileManager = fileManager
    }

    func download(
        from sourceURL: URL,
        to destinationURL: URL,
        maximumBytes: Int64,
        requestTimeoutSeconds: TimeInterval
    ) async throws {
        guard maximumBytes > 0 else {
            throw OfflinePackageDownloadError.invalidDownloadedFile
        }
        var request = URLRequest(url: sourceURL)
        request.timeoutInterval = requestTimeoutSeconds

        let temporaryURL: URL
        let response: URLResponse
        do {
            (temporaryURL, response) = try await session.download(for: request)
        } catch is CancellationError {
            throw OfflinePackageDownloadError.cancelled
        } catch let error as URLError {
            throw mapped(error)
        } catch {
            throw OfflinePackageDownloadError.permanentFailure
        }

        guard let HTTPResponse = response as? HTTPURLResponse else {
            throw OfflinePackageDownloadError.invalidResponse
        }
        guard let responseURL = HTTPResponse.url, isAllowedResponseURL(responseURL) else {
            throw OfflinePackageDownloadError.invalidResponse
        }
        guard (200..<300).contains(HTTPResponse.statusCode) else {
            if (500..<600).contains(HTTPResponse.statusCode) {
                throw OfflinePackageDownloadError.temporaryFailure
            }
            throw OfflinePackageDownloadError.permanentFailure
        }
        if response.expectedContentLength > maximumBytes {
            throw OfflinePackageDownloadError.responseTooLarge
        }

        let values = try temporaryURL.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
        ])
        guard
            values.isRegularFile == true,
            values.isSymbolicLink != true,
            let fileSize = values.fileSize,
            fileSize > 0,
            Int64(fileSize) <= maximumBytes,
            !fileManager.fileExists(atPath: destinationURL.path)
        else {
            throw OfflinePackageDownloadError.invalidDownloadedFile
        }
        do {
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: destinationURL.path
            )
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            var mutableURL = destinationURL
            try mutableURL.setResourceValues(resourceValues)
        } catch {
            throw OfflinePackageDownloadError.invalidDownloadedFile
        }
    }

    private func mapped(_ error: URLError) -> OfflinePackageDownloadError {
        switch error.code {
        case .cancelled:
            return .cancelled
        case .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .networkConnectionLost,
             .notConnectedToInternet,
             .internationalRoamingOff,
             .callIsActive,
             .dataNotAllowed:
            return .temporaryFailure
        default:
            return .permanentFailure
        }
    }

    private func isAllowedResponseURL(_ url: URL) -> Bool {
        guard
            url.absoluteString.utf8.count <= 2_048,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return false
        }
        return components.scheme?.lowercased() == "https"
            && components.host?.isEmpty == false
            && components.user == nil
            && components.password == nil
    }
}
