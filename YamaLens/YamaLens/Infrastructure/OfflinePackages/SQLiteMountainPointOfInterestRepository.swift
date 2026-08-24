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
    private let trailheadAccessGuidesByMountainID: [String: [TrailheadAccessGuide]]

    init(databaseURL: URL) throws {
        let catalog = try Self.loadCatalog(from: databaseURL)
        pointsByMountainID = catalog.pointsByMountainID
        trailheadAccessGuidesByMountainID = catalog.trailheadAccessGuidesByMountainID
    }

    func fetchPointsOfInterest(for mountainID: String) -> [MountainPointOfInterest] {
        pointsByMountainID[mountainID] ?? []
    }

    func fetchTrailheadAccessGuides(for mountainID: String) -> [TrailheadAccessGuide] {
        trailheadAccessGuidesByMountainID[mountainID] ?? []
    }

    private static func loadCatalog(
        from databaseURL: URL
    ) throws -> MountainPointOfInterestCatalog {
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
        let detailsByPointID = try loadDetails(from: database)
        let pointsByMountainID = try loadRows(
            from: database,
            detailsByPointID: detailsByPointID
        )
        let accessPointIDsByTrailheadID = try loadAccessPointIDs(from: database)
        let searchAreasByTrailheadID = try loadSearchAreas(from: database)
        return MountainPointOfInterestCatalog(
            pointsByMountainID: pointsByMountainID,
            trailheadAccessGuidesByMountainID: makeTrailheadAccessGuides(
                pointsByMountainID: pointsByMountainID,
                accessPointIDsByTrailheadID: accessPointIDsByTrailheadID,
                searchAreasByTrailheadID: searchAreasByTrailheadID
            )
        )
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
        from database: OpaquePointer,
        detailsByPointID: [String: [MountainPointOfInterestDetail]]
    ) throws -> [String: [MountainPointOfInterest]] {
        let orderSelection = try hasColumn(
            "display_order",
            in: "mountain_points_of_interest",
            database: database
        ) ? "mountain_points_of_interest.display_order" : "points_of_interest.name"
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
        ORDER BY mountain_points_of_interest.mountain_id, points_of_interest.type, \(orderSelection), points_of_interest.name;
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
                let point = try pointOfInterest(
                    from: statement,
                    details: detailsByPointID[try text(in: statement, column: 1)] ?? []
                )
                result[mountainID, default: []].append(point)
            case SQLITE_DONE:
                return result
            default:
                throw SQLiteMountainPointOfInterestRepositoryError.sqliteFailure(code: stepResult)
            }
        }
    }

    private static func hasColumn(
        _ columnName: String,
        in tableName: String,
        database: OpaquePointer
    ) throws -> Bool {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(database, "PRAGMA table_info(\(tableName));", -1, &statement, nil)
        guard result == SQLITE_OK, let statement else {
            throw SQLiteMountainPointOfInterestRepositoryError.sqliteFailure(code: result)
        }
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            if try text(in: statement, column: 1) == columnName {
                return true
            }
        }
        return false
    }

    private static func pointOfInterest(
        from statement: OpaquePointer,
        details: [MountainPointOfInterestDetail]
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
            sourceProvider: sourceProvider,
            details: details
        )
    }

    private static func loadDetails(
        from database: OpaquePointer
    ) throws -> [String: [MountainPointOfInterestDetail]] {
        guard try hasTable("point_of_interest_details", database: database) else {
            return [:]
        }
        let query = """
        SELECT point_of_interest_id, kind, value
        FROM point_of_interest_details
        ORDER BY point_of_interest_id, display_order;
        """
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(database, query, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else {
            throw SQLiteMountainPointOfInterestRepositoryError.sqliteFailure(code: result)
        }
        defer { sqlite3_finalize(statement) }

        var detailsByPointID: [String: [MountainPointOfInterestDetail]] = [:]
        while true {
            let stepResult = sqlite3_step(statement)
            switch stepResult {
            case SQLITE_ROW:
                let pointID = try text(in: statement, column: 0)
                let kindText = try text(in: statement, column: 1)
                let value = try text(in: statement, column: 2)
                guard
                    let kind = MountainPointOfInterestDetailKind(rawValue: kindText),
                    !value.isEmpty
                else {
                    throw SQLiteMountainPointOfInterestRepositoryError.invalidRecord
                }
                detailsByPointID[pointID, default: []].append(
                    MountainPointOfInterestDetail(kind: kind, value: value)
                )
            case SQLITE_DONE:
                return detailsByPointID
            default:
                throw SQLiteMountainPointOfInterestRepositoryError.sqliteFailure(code: stepResult)
            }
        }
    }

    private static func hasTable(
        _ tableName: String,
        database: OpaquePointer
    ) throws -> Bool {
        var statement: OpaquePointer?
        guard tableName.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else {
            throw SQLiteMountainPointOfInterestRepositoryError.invalidRecord
        }
        let query = "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = '\(tableName)' LIMIT 1;"
        let result = sqlite3_prepare_v2(database, query, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else {
            throw SQLiteMountainPointOfInterestRepositoryError.sqliteFailure(code: result)
        }
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private static func loadAccessPointIDs(
        from database: OpaquePointer
    ) throws -> [String: [String]] {
        let query = """
        SELECT trailhead_id, point_of_interest_id
        FROM trailhead_access_points
        ORDER BY trailhead_id, display_order;
        """
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(database, query, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else {
            throw SQLiteMountainPointOfInterestRepositoryError.sqliteFailure(code: result)
        }
        defer { sqlite3_finalize(statement) }

        var pointIDsByTrailheadID: [String: [String]] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            let trailheadID = try text(in: statement, column: 0)
            let pointID = try text(in: statement, column: 1)
            pointIDsByTrailheadID[trailheadID, default: []].append(pointID)
        }
        return pointIDsByTrailheadID
    }

    private static func loadSearchAreas(
        from database: OpaquePointer
    ) throws -> [String: [NearbySearchArea]] {
        let query = """
        SELECT id, trailhead_id, name
        FROM trailhead_search_areas
        ORDER BY trailhead_id, display_order;
        """
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(database, query, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else {
            throw SQLiteMountainPointOfInterestRepositoryError.sqliteFailure(code: result)
        }
        defer { sqlite3_finalize(statement) }

        var areasByTrailheadID: [String: [NearbySearchArea]] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            let identifier = try text(in: statement, column: 0)
            let trailheadID = try text(in: statement, column: 1)
            let name = try text(in: statement, column: 2)
            areasByTrailheadID[trailheadID, default: []].append(
                NearbySearchArea(
                    id: identifier,
                    name: name
                )
            )
        }
        return areasByTrailheadID
    }

    private static func makeTrailheadAccessGuides(
        pointsByMountainID: [String: [MountainPointOfInterest]],
        accessPointIDsByTrailheadID: [String: [String]],
        searchAreasByTrailheadID: [String: [NearbySearchArea]]
    ) -> [String: [TrailheadAccessGuide]] {
        let pointsByID = pointsByMountainID.values
            .flatMap { $0 }
            .reduce(into: [String: MountainPointOfInterest]()) { result, point in
                result[point.id] = point
            }
        return pointsByMountainID.mapValues { points in
            points.compactMap { trailhead in
                guard trailhead.type == .trailhead else { return nil }
                let accessPoints = (accessPointIDsByTrailheadID[trailhead.id] ?? []).compactMap {
                    pointsByID[$0]
                }
                let searchAreas = searchAreasByTrailheadID[trailhead.id] ?? []
                return TrailheadAccessGuide(
                    trailhead: trailhead,
                    accessPoints: accessPoints,
                    nearbySearchAreas: searchAreas
                )
            }
        }
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

private struct MountainPointOfInterestCatalog {
    let pointsByMountainID: [String: [MountainPointOfInterest]]
    let trailheadAccessGuidesByMountainID: [String: [TrailheadAccessGuide]]
}
