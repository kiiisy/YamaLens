import Foundation

nonisolated protocol MountainWeatherCaching: Sendable {
    func forecast(for mountainID: String) async throws -> MountainWeatherForecast?
    func previousDaySummary(for mountainID: String) async throws -> PreviousDayWeatherSummary?
    func save(_ forecast: MountainWeatherForecast) async throws
    func save(_ summary: PreviousDayWeatherSummary) async throws
}

actor FileMountainWeatherCache: MountainWeatherCaching {
    private enum Constants {
        static let maximumFileSize = 512 * 1_024
    }

    private let directoryURL: URL?
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(directoryURL: URL? = nil, fileManager: FileManager = .default) {
        self.directoryURL = directoryURL ?? fileManager.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first?.appending(path: "Weather", directoryHint: .isDirectory)
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func forecast(for mountainID: String) async throws -> MountainWeatherForecast? {
        try read(MountainWeatherForecast.self, from: fileURL(kind: "forecast", mountainID: mountainID))
    }

    func previousDaySummary(for mountainID: String) async throws -> PreviousDayWeatherSummary? {
        try read(
            PreviousDayWeatherSummary.self,
            from: fileURL(kind: "previous", mountainID: mountainID)
        )
    }

    func save(_ forecast: MountainWeatherForecast) async throws {
        try write(forecast, to: fileURL(kind: "forecast", mountainID: forecast.mountainID))
    }

    func save(_ summary: PreviousDayWeatherSummary) async throws {
        try write(summary, to: fileURL(kind: "previous", mountainID: summary.mountainID))
    }

    private func fileURL(kind: String, mountainID: String) throws -> URL {
        guard let directoryURL,
              !mountainID.isEmpty,
              mountainID.count <= 128,
              mountainID.unicodeScalars.allSatisfy({
                  CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
                      .contains($0)
              }) else {
            throw MountainWeatherRepositoryError.storageUnavailable
        }
        return directoryURL.appending(path: "\(kind)-\(mountainID).json")
    }

    private func read<Value: Decodable>(_ type: Value.Type, from url: URL) throws -> Value? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true,
              let fileSize = values.fileSize,
              fileSize <= Constants.maximumFileSize else {
            throw MountainWeatherRepositoryError.invalidData
        }
        do {
            return try decoder.decode(type, from: Data(contentsOf: url, options: .mappedIfSafe))
        } catch {
            throw MountainWeatherRepositoryError.invalidData
        }
    }

    private func write<Value: Encodable>(_ value: Value, to url: URL) throws {
        try prepareDirectory(url.deletingLastPathComponent())
        let data: Data
        do {
            data = try encoder.encode(value)
        } catch {
            throw MountainWeatherRepositoryError.invalidData
        }
        guard data.count <= Constants.maximumFileSize else {
            throw MountainWeatherRepositoryError.invalidData
        }
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: url.path
            )
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            var mutableURL = url
            try mutableURL.setResourceValues(resourceValues)
        } catch {
            throw MountainWeatherRepositoryError.storageUnavailable
        }
    }

    private func prepareDirectory(_ url: URL) throws {
        do {
            try fileManager.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: [
                    .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
                ]
            )
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            var mutableURL = url
            try mutableURL.setResourceValues(resourceValues)
        } catch {
            throw MountainWeatherRepositoryError.storageUnavailable
        }
    }
}
