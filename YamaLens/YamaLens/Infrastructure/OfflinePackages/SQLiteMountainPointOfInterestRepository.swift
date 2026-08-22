import Foundation
import SQLite3

nonisolated enum SQLiteMountainPointOfInterestRepositoryError: Error, Equatable, Sendable {
    case cannotOpenDatabase(code: Int32)
    case databaseCheckFailed
    case unsupportedSchemaVersion
    case invalidRecord
    case sqliteFailure(code: Int32)
}

nonisolated struct SQLiteMountainPointOfInterestRepository: MountainPointOfInterestRepository {
    private let pointsByMountainID: [String: [MountainPointOfInterest]]

    init(databaseURL: URL) throws {
        pointsByMountainID = try Self.loadPointsOfInterest(from: databaseURL)
    }

    func fetchPointsOfInterest(for mountainID: String) -> [MountainPointOfInterest] {
        pointsByMountainID[mountainID] ?? []
    }

    private static func loadPointsOfInterest(
        from databaseURL: URL
    ) throws -> [String: [MountainPointOfInterest]] {
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard openResult == SQLITE_OK, let database else {
            if let database {
                sqlite3_close(database)
            }
            throw SQLiteMountainPointOfInterestRepositoryError.cannotOpenDatabase(code: openResult)
        }
        defer { sqlite3_close(database) }

        try execute(
            "PRAGMA query_only = ON; PRAGMA foreign_keys = ON; PRAGMA trusted_schema = OFF;",
            in: database
        )
        try validateDatabase(database)
        return try loadRows(from: database)
    }

    private static func validateDatabase(_ database: OpaquePointer) throws {
        guard try singleText(query: "PRAGMA integrity_check;", in: database) == "ok" else {
            throw SQLiteMountainPointOfInterestRepositoryError.databaseCheckFailed
        }
        guard try singleText(
            query: "SELECT value FROM package_metadata WHERE key = 'schema_version';",
            in: database
        ) == "1" else {
            throw SQLiteMountainPointOfInterestRepositoryError.unsupportedSchemaVersion
        }
    }

    private static func loadRows(
        from database: OpaquePointer
    ) throws -> [String: [MountainPointOfInterest]] {
        let query = """
        SELECT
            mountain_points_of_interest.mountain_id,
            points_of_interest.id,
            points_of_interest.type,
            points_of_interest.name,
            points_of_interest.latitude,
            points_of_interest.longitude,
            points_of_interest.summary,
            points_of_interest.official_url,
            points_of_interest.checked_at,
            source_links.provider
        FROM mountain_points_of_interest
        INNER JOIN points_of_interest
            ON points_of_interest.id = mountain_points_of_interest.point_of_interest_id
        INNER JOIN entity_sources
            ON entity_sources.entity_type = 'point_of_interest'
            AND entity_sources.entity_id = points_of_interest.id
        INNER JOIN source_links ON source_links.id = entity_sources.source_id
        ORDER BY mountain_points_of_interest.mountain_id, points_of_interest.type, points_of_interest.name;
        """
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(database, query, -1, &statement, nil)
        guard prepareResult == SQLITE_OK, let statement else {
            throw SQLiteMountainPointOfInterestRepositoryError.sqliteFailure(code: prepareResult)
        }
        defer { sqlite3_finalize(statement) }

        var result: [String: [MountainPointOfInterest]] = [:]
        while true {
            let stepResult = sqlite3_step(statement)
            switch stepResult {
            case SQLITE_ROW:
                let mountainID = try text(in: statement, column: 0)
                let point = try pointOfInterest(from: statement)
                result[mountainID, default: []].append(point)
            case SQLITE_DONE:
                return result
            default:
                throw SQLiteMountainPointOfInterestRepositoryError.sqliteFailure(code: stepResult)
            }
        }
    }

    private static func pointOfInterest(
        from statement: OpaquePointer
    ) throws -> MountainPointOfInterest {
        let identifier = try text(in: statement, column: 1)
        let typeText = try text(in: statement, column: 2)
        let name = try text(in: statement, column: 3)
        let summary = try text(in: statement, column: 6)
        let officialURLText = try text(in: statement, column: 7)
        let checkedAtText = try text(in: statement, column: 8)
        let sourceProvider = try text(in: statement, column: 9)
        guard
            !identifier.isEmpty,
            let type = MountainPointOfInterestType(rawValue: typeText),
            !name.isEmpty,
            !summary.isEmpty,
            !sourceProvider.isEmpty,
            let officialURL = validatedHTTPSURL(officialURLText),
            let checkedAt = calendarDate(checkedAtText)
        else {
            throw SQLiteMountainPointOfInterestRepositoryError.invalidRecord
        }

        let latitudeType = sqlite3_column_type(statement, 4)
        let longitudeType = sqlite3_column_type(statement, 5)
        let coordinate: GeoCoordinate?
        switch (latitudeType == SQLITE_NULL, longitudeType == SQLITE_NULL) {
        case (true, true):
            coordinate = nil
        case (false, false):
            let latitude = sqlite3_column_double(statement, 4)
            let longitude = sqlite3_column_double(statement, 5)
            guard (-90...90).contains(latitude), (-180...180).contains(longitude) else {
                throw SQLiteMountainPointOfInterestRepositoryError.invalidRecord
            }
            coordinate = GeoCoordinate(latitude: latitude, longitude: longitude)
        default:
            throw SQLiteMountainPointOfInterestRepositoryError.invalidRecord
        }

        return MountainPointOfInterest(
            id: identifier,
            type: type,
            name: name,
            coordinate: coordinate,
            summary: summary,
            officialURL: officialURL,
            checkedAt: checkedAt,
            sourceProvider: sourceProvider
        )
    }

    private static func validatedHTTPSURL(_ value: String) -> URL? {
        guard
            value.count <= 2_048,
            let components = URLComponents(string: value),
            components.scheme == "https",
            components.host != nil,
            components.user == nil,
            components.password == nil
        else {
            return nil
        }
        return components.url
    }

    private static func calendarDate(_ value: String) -> Date? {
        let components = value.split(separator: "-", omittingEmptySubsequences: false)
        guard
            components.count == 3,
            let year = Int(components[0]),
            let month = Int(components[1]),
            let day = Int(components[2]),
            let timeZone = TimeZone(identifier: "Asia/Tokyo")
        else {
            return nil
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    private static func execute(_ query: String, in database: OpaquePointer) throws {
        let result = sqlite3_exec(database, query, nil, nil, nil)
        guard result == SQLITE_OK else {
            throw SQLiteMountainPointOfInterestRepositoryError.sqliteFailure(code: result)
        }
    }

    private static func singleText(
        query: String,
        in database: OpaquePointer
    ) throws -> String {
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(database, query, -1, &statement, nil)
        guard prepareResult == SQLITE_OK, let statement else {
            throw SQLiteMountainPointOfInterestRepositoryError.sqliteFailure(code: prepareResult)
        }
        defer { sqlite3_finalize(statement) }
        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_ROW else {
            throw SQLiteMountainPointOfInterestRepositoryError.sqliteFailure(code: stepResult)
        }
        return try text(in: statement, column: 0)
    }

    private static func text(
        in statement: OpaquePointer,
        column: Int32
    ) throws -> String {
        guard
            sqlite3_column_type(statement, column) != SQLITE_NULL,
            let value = sqlite3_column_text(statement, column)
        else {
            throw SQLiteMountainPointOfInterestRepositoryError.invalidRecord
        }
        return String(cString: value)
    }
}
