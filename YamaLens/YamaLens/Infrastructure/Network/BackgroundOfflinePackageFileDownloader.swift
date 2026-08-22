import Foundation
import Synchronization

nonisolated enum OfflinePackageDownloadError: Error, Equatable, Sendable {
    case temporaryFailure
    case permanentFailure
    case cancelled
    case insufficientStorage
    case responseTooLarge
    case invalidResponse
    case invalidDownloadedFile
}

nonisolated protocol OfflinePackageFileDownloading: Sendable {
    func download(
        from sourceURL: URL,
        to destinationURL: URL,
        maximumBytes: Int64,
        requestTimeoutSeconds: TimeInterval,
        progress: @escaping @Sendable (_ receivedBytes: Int64, _ totalBytes: Int64?) -> Void
    ) async throws

    func activeStagingIdentifiers() async -> Set<String>
}

extension OfflinePackageFileDownloading {
    func download(
        from sourceURL: URL,
        to destinationURL: URL,
        maximumBytes: Int64,
        requestTimeoutSeconds: TimeInterval
    ) async throws {
        try await download(
            from: sourceURL,
            to: destinationURL,
            maximumBytes: maximumBytes,
            requestTimeoutSeconds: requestTimeoutSeconds,
            progress: { _, _ in }
        )
    }

    func activeStagingIdentifiers() async -> Set<String> {
        []
    }
}

actor BackgroundOfflinePackageFileDownloader: OfflinePackageFileDownloading {
    static let sessionIdentifier = "com.kiiisy.YamaLens.offline-packages"

    private let session: URLSession
    private let delegate: BackgroundOfflinePackageDownloadDelegate
    private let rootURL: URL

    init(
        rootURL: URL,
        identifier: String = BackgroundOfflinePackageFileDownloader.sessionIdentifier,
        policy: OfflinePackageNetworkPolicy = .default,
        backgroundEventsDidFinish: @escaping @Sendable (String) async -> Void = { _ in }
    ) {
        let standardizedRootURL = rootURL.standardizedFileURL
        let delegate = BackgroundOfflinePackageDownloadDelegate(
            rootURL: standardizedRootURL,
            backgroundEventsDidFinish: backgroundEventsDidFinish
        )
        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = policy.packageRequestTimeoutSeconds
        configuration.timeoutIntervalForResource = policy.resourceTimeoutSeconds
        configuration.allowsCellularAccess = policy.allowsCellularAccess
        configuration.sessionSendsLaunchEvents = true
        session = URLSession(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: nil
        )
        self.delegate = delegate
        self.rootURL = standardizedRootURL
    }

    func download(
        from sourceURL: URL,
        to destinationURL: URL,
        maximumBytes: Int64,
        requestTimeoutSeconds: TimeInterval,
        progress: @escaping @Sendable (Int64, Int64?) -> Void
    ) async throws {
        guard maximumBytes > 0 else {
            throw OfflinePackageDownloadError.invalidDownloadedFile
        }
        let descriptor = try BackgroundDownloadTaskDescriptor(
            destinationURL: destinationURL,
            rootURL: rootURL,
            maximumBytes: maximumBytes
        )
        let encodedDescriptor = try descriptor.encoded()
        if try Self.isValidExistingFile(at: destinationURL, maximumBytes: maximumBytes) {
            progress(maximumBytes, maximumBytes)
            return
        }

        var request = URLRequest(url: sourceURL)
        request.timeoutInterval = requestTimeoutSeconds
        let tasks = await session.allTasks
        let task: URLSessionDownloadTask
        if let existingTask = tasks.compactMap({ $0 as? URLSessionDownloadTask }).first(
            where: {
                $0.taskDescription == encodedDescriptor
                    && $0.originalRequest?.url == sourceURL
            }
        ) {
            task = existingTask
        } else {
            let newTask = session.downloadTask(with: request)
            newTask.taskDescription = encodedDescriptor
            newTask.countOfBytesClientExpectsToReceive = maximumBytes
            task = newTask
        }

        try await withTaskCancellationHandler {
            try await delegate.waitForCompletion(of: task, progress: progress)
        } onCancel: {
            task.cancel()
        }
        _ = try Self.isValidExistingFile(at: destinationURL, maximumBytes: maximumBytes)
    }

    func activeStagingIdentifiers() async -> Set<String> {
        let tasks = await session.allTasks
        return Set(
            tasks.compactMap { task in
                guard let description = task.taskDescription,
                      let descriptor = BackgroundDownloadTaskDescriptor(encoded: description)
                else {
                    return nil
                }
                return descriptor.stagingIdentifier
            }
        )
    }

    private nonisolated static func isValidExistingFile(
        at fileURL: URL,
        maximumBytes: Int64
    ) throws -> Bool {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return false }
        let values = try fileURL.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
        ])
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              let fileSize = values.fileSize,
              fileSize > 0,
              Int64(fileSize) <= maximumBytes else {
            throw OfflinePackageDownloadError.invalidDownloadedFile
        }
        return true
    }
}

nonisolated struct BackgroundDownloadTaskDescriptor: Codable, Equatable, Sendable {
    private static let allowedFileNames = Set([
        "manifest.json",
        "manifest.sig",
        "catalog.sqlite",
        "terrain.lzfse",
    ])

    let version: Int
    let stagingIdentifier: String
    let fileName: String
    let maximumBytes: Int64

    init(destinationURL: URL, rootURL: URL, maximumBytes: Int64) throws {
        let destination = destinationURL.standardizedFileURL
        let stagingDirectory = destination.deletingLastPathComponent()
        let expectedStagingRoot = rootURL.standardizedFileURL
            .appending(path: "Staging", directoryHint: .isDirectory)
        guard stagingDirectory.deletingLastPathComponent() == expectedStagingRoot,
              Self.isSafePathComponent(stagingDirectory.lastPathComponent),
              Self.allowedFileNames.contains(destination.lastPathComponent),
              maximumBytes > 0 else {
            throw OfflinePackageDownloadError.invalidDownloadedFile
        }
        version = 1
        stagingIdentifier = stagingDirectory.lastPathComponent
        fileName = destination.lastPathComponent
        self.maximumBytes = maximumBytes
    }

    init?(encoded: String) {
        guard let data = Data(base64Encoded: encoded), data.count <= 1_024 else {
            return nil
        }
        let decoded: Self
        do {
            decoded = try JSONDecoder().decode(Self.self, from: data)
        } catch {
            return nil
        }
        guard decoded.version == 1,
              Self.isSafePathComponent(decoded.stagingIdentifier),
              Self.allowedFileNames.contains(decoded.fileName),
              decoded.maximumBytes > 0,
              decoded.maximumBytes <= 1_000_000_000 else {
            return nil
        }
        self = decoded
    }

    func encoded() throws -> String {
        let data = try JSONEncoder().encode(self)
        return data.base64EncodedString()
    }

    func destinationURL(rootURL: URL) -> URL {
        rootURL.standardizedFileURL
            .appending(path: "Staging", directoryHint: .isDirectory)
            .appending(path: stagingIdentifier, directoryHint: .isDirectory)
            .appending(path: fileName, directoryHint: .notDirectory)
    }

    private static func isSafePathComponent(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 128 else { return false }
        let allowed = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_"
        )
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
            && !value.contains("..")
            && value != "."
    }
}

private final class BackgroundOfflinePackageDownloadDelegate: NSObject,
    URLSessionDownloadDelegate,
    URLSessionTaskDelegate,
    Sendable {
    private struct State: Sendable {
        var continuations: [Int: CheckedContinuation<Void, Error>] = [:]
        var outcomes: [Int: DownloadOutcome] = [:]
        var progressHandlers: [Int: @Sendable (Int64, Int64?) -> Void] = [:]
    }

    private enum DownloadOutcome: Sendable {
        case success
        case failure(OfflinePackageDownloadError)
    }

    private let rootURL: URL
    private let state = Mutex(State())
    private let backgroundEventsDidFinish: @Sendable (String) async -> Void

    init(
        rootURL: URL,
        backgroundEventsDidFinish: @escaping @Sendable (String) async -> Void
    ) {
        self.rootURL = rootURL
        self.backgroundEventsDidFinish = backgroundEventsDidFinish
    }

    func waitForCompletion(
        of task: URLSessionDownloadTask,
        progress: @escaping @Sendable (Int64, Int64?) -> Void
    ) async throws {
        let immediateOutcome: DownloadOutcome? = state.withLock { state in
            state.outcomes.removeValue(forKey: task.taskIdentifier)
        }
        if let immediateOutcome {
            try Self.resolve(immediateOutcome)
            return
        }

        try await withCheckedThrowingContinuation { continuation in
            state.withLock { state in
                state.continuations[task.taskIdentifier] = continuation
                state.progressHandlers[task.taskIdentifier] = progress
            }
            task.resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let handler = state.withLock { state in
            state.progressHandlers[downloadTask.taskIdentifier]
        }
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil
        handler?(totalBytesWritten, total)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let outcome = moveDownloadedFile(from: location, task: downloadTask)
        state.withLock { state in
            state.outcomes[downloadTask.taskIdentifier] = outcome
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        let outcome: DownloadOutcome
        if let URLRequestError = error as? URLError {
            outcome = .failure(Self.map(URLRequestError))
        } else if error != nil {
            outcome = .failure(.permanentFailure)
        } else {
            outcome = state.withLock { state in
                state.outcomes.removeValue(forKey: task.taskIdentifier)
                    ?? .failure(.invalidDownloadedFile)
            }
        }
        let continuation = state.withLock { state in
            state.progressHandlers[task.taskIdentifier] = nil
            return state.continuations.removeValue(forKey: task.taskIdentifier)
        }
        if let continuation {
            switch outcome {
            case .success:
                continuation.resume()
            case .failure(let error):
                continuation.resume(throwing: error)
            }
        } else {
            state.withLock { state in
                state.outcomes[task.taskIdentifier] = outcome
            }
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        guard let identifier = session.configuration.identifier else { return }
        Task {
            await backgroundEventsDidFinish(identifier)
        }
    }

    private func moveDownloadedFile(
        from temporaryURL: URL,
        task: URLSessionDownloadTask
    ) -> DownloadOutcome {
        guard let description = task.taskDescription,
              let descriptor = BackgroundDownloadTaskDescriptor(encoded: description),
              let HTTPResponse = task.response as? HTTPURLResponse,
              let responseURL = HTTPResponse.url,
              Self.isAllowedResponseURL(responseURL),
              (200..<300).contains(HTTPResponse.statusCode) else {
            if let HTTPResponse = task.response as? HTTPURLResponse,
               (500..<600).contains(HTTPResponse.statusCode) {
                return .failure(.temporaryFailure)
            }
            return .failure(.invalidResponse)
        }
        guard HTTPResponse.expectedContentLength <= descriptor.maximumBytes
            || HTTPResponse.expectedContentLength == NSURLSessionTransferSizeUnknown else {
            return .failure(.responseTooLarge)
        }
        let destinationURL = descriptor.destinationURL(rootURL: rootURL)
        do {
            let values = try temporaryURL.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
            ])
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  let fileSize = values.fileSize,
                  fileSize > 0,
                  Int64(fileSize) <= descriptor.maximumBytes,
                  !FileManager.default.fileExists(atPath: destinationURL.path) else {
                return .failure(.invalidDownloadedFile)
            }
            try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: destinationURL.path
            )
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            var mutableURL = destinationURL
            try mutableURL.setResourceValues(resourceValues)
            return .success
        } catch let cocoaError as CocoaError where cocoaError.code == .fileWriteOutOfSpace {
            return .failure(.insufficientStorage)
        } catch {
            return .failure(.invalidDownloadedFile)
        }
    }

    private static func resolve(_ outcome: DownloadOutcome) throws {
        switch outcome {
        case .success:
            return
        case .failure(let error):
            throw error
        }
    }

    private static func map(_ error: URLError) -> OfflinePackageDownloadError {
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

    private static func isAllowedResponseURL(_ url: URL) -> Bool {
        guard url.absoluteString.utf8.count <= 2_048,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        return components.scheme?.lowercased() == "https"
            && components.host?.isEmpty == false
            && components.user == nil
            && components.password == nil
    }
}
