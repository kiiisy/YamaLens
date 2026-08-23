import Foundation
import SQLite3

nonisolated enum SQLiteMountainRepositoryError: Error, Equatable, Sendable {
    case cannotOpenDatabase(code: Int32)
    case databaseCheckFailed
    case unsupportedSchemaVersion
    case invalidRecord
    case sqliteFailure(code: Int32)
}

nonisolated struct SQLiteMountainRepository: MountainRepository {
    private let mountains: [Mountain]

    init(databaseURL: URL) throws {
        mountains = try Self.loadMountains(from: databaseURL)
    }

    func fetchMountains() -> [Mountain] {
        mountains
    }

    private static func loadMountains(from databaseURL: URL) throws -> [Mountain] {
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
            throw SQLiteMountainRepositoryError.cannotOpenDatabase(code: openResult)
        }
        defer { sqlite3_close(database) }

        try execute(
            "PRAGMA query_only = ON; PRAGMA foreign_keys = ON; PRAGMA trusted_schema = OFF;",
            in: database
        )
        try validateDatabase(database)
        let aliases = try loadAliases(from: database)
        return try loadMountainRows(from: database, aliases: aliases)
    }

    private static func validateDatabase(_ database: OpaquePointer) throws {
        let integrityResult = try singleText(
            query: "PRAGMA integrity_check;",
            in: database
        )
        guard integrityResult == "ok" else {
            throw SQLiteMountainRepositoryError.databaseCheckFailed
        }

        let schemaVersion = try singleText(
            query: "SELECT value FROM package_metadata WHERE key = 'schema_version';",
            in: database
        )
        guard schemaVersion == "1" else {
            throw SQLiteMountainRepositoryError.unsupportedSchemaVersion
        }
    }

    private static func loadAliases(
        from database: OpaquePointer
    ) throws -> [String: [String]] {
        let query = """
        SELECT mountain_id, name
        FROM mountain_names
        WHERE kind = 'alias'
        ORDER BY mountain_id, name;
        """
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(database, query, -1, &statement, nil)
        guard prepareResult == SQLITE_OK, let statement else {
            throw SQLiteMountainRepositoryError.sqliteFailure(code: prepareResult)
        }
        defer { sqlite3_finalize(statement) }

        var aliases: [String: [String]] = [:]
        while true {
            let stepResult = sqlite3_step(statement)
            switch stepResult {
            case SQLITE_ROW:
                let mountainID = try text(in: statement, column: 0)
                let alias = try text(in: statement, column: 1)
                aliases[mountainID, default: []].append(alias)
            case SQLITE_DONE:
                return aliases
            default:
                throw SQLiteMountainRepositoryError.sqliteFailure(code: stepResult)
            }
        }
    }

    private static func loadMountainRows(
        from database: OpaquePointer,
        aliases: [String: [String]]
    ) throws -> [Mountain] {
        let yamapURLSelection = try hasColumn(
            "yamap_url",
            inTable: "mountains",
            database: database
        ) ? "mountains.yamap_url" : "NULL"
        let query = """
        SELECT
            mountains.id,
            mountains.canonical_name,
            regions.name,
            regions.prefecture_name,
            mountains.coverage_role,
            mountains.elevation_m,
            mountains.latitude,
            mountains.longitude,
            \(yamapURLSelection) AS yamap_url
        FROM mountains
        INNER JOIN regions ON regions.id = mountains.region_id
        ORDER BY mountains.canonical_name;
        """
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(database, query, -1, &statement, nil)
        guard prepareResult == SQLITE_OK, let statement else {
            throw SQLiteMountainRepositoryError.sqliteFailure(code: prepareResult)
        }
        defer { sqlite3_finalize(statement) }

        var mountains: [Mountain] = []
        while true {
            let stepResult = sqlite3_step(statement)
            switch stepResult {
            case SQLITE_ROW:
                let mountainID = try text(in: statement, column: 0)
                let name = try text(in: statement, column: 1)
                let regionName = try text(in: statement, column: 2)
                let prefectureName = try text(in: statement, column: 3)
                let coverageRoleText = try text(in: statement, column: 4)
                guard let coverageRole = MountainCoverageRole(rawValue: coverageRoleText) else {
                    throw SQLiteMountainRepositoryError.invalidRecord
                }
                let elevation = sqlite3_column_int64(statement, 5)
                let latitude = sqlite3_column_double(statement, 6)
                let longitude = sqlite3_column_double(statement, 7)
                let yamapURL = optionalText(in: statement, column: 8)
                    .flatMap(validatedYAMAPMountainURL)
                guard
                    !mountainID.isEmpty,
                    !name.isEmpty,
                    !regionName.isEmpty,
                    !prefectureName.isEmpty,
                    (-500...9_000).contains(elevation),
                    (-90...90).contains(latitude),
                    (-180...180).contains(longitude)
                else {
                    throw SQLiteMountainRepositoryError.invalidRecord
                }
                mountains.append(
                    Mountain(
                        id: mountainID,
                        name: name,
                        aliases: aliases[mountainID] ?? [],
                        regionName: regionName,
                        prefectureName: prefectureName,
                        elevationMeters: Int(elevation),
                        coordinate: GeoCoordinate(
                            latitude: latitude,
                            longitude: longitude
                        ),
                        coverageRole: coverageRole,
                        yamapURL: yamapURL
                    )
                )
            case SQLITE_DONE:
                guard !mountains.isEmpty else {
                    throw SQLiteMountainRepositoryError.invalidRecord
                }
                return mountains
            default:
                throw SQLiteMountainRepositoryError.sqliteFailure(code: stepResult)
            }
        }
    }

    private static func execute(
        _ query: String,
        in database: OpaquePointer
    ) throws {
        let result = sqlite3_exec(database, query, nil, nil, nil)
        guard result == SQLITE_OK else {
            throw SQLiteMountainRepositoryError.sqliteFailure(code: result)
        }
    }

    private static func singleText(
        query: String,
        in database: OpaquePointer
    ) throws -> String {
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(database, query, -1, &statement, nil)
        guard prepareResult == SQLITE_OK, let statement else {
            throw SQLiteMountainRepositoryError.sqliteFailure(code: prepareResult)
        }
        defer { sqlite3_finalize(statement) }

        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_ROW else {
            throw SQLiteMountainRepositoryError.sqliteFailure(code: stepResult)
        }
        return try text(in: statement, column: 0)
    }

    private static func hasColumn(
        _ columnName: String,
        inTable tableName: String,
        database: OpaquePointer
    ) throws -> Bool {
        let query = "PRAGMA table_info(\(tableName));"
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(database, query, -1, &statement, nil)
        guard prepareResult == SQLITE_OK, let statement else {
            throw SQLiteMountainRepositoryError.sqliteFailure(code: prepareResult)
        }
        defer { sqlite3_finalize(statement) }

        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                if try text(in: statement, column: 1) == columnName {
                    return true
                }
            case SQLITE_DONE:
                return false
            default:
                throw SQLiteMountainRepositoryError.sqliteFailure(code: sqlite3_errcode(database))
            }
        }
    }

    private static func optionalText(
        in statement: OpaquePointer,
        column: Int32
    ) -> String? {
        guard
            sqlite3_column_type(statement, column) != SQLITE_NULL,
            let value = sqlite3_column_text(statement, column)
        else {
            return nil
        }
        return String(cString: value)
    }

    private static func validatedYAMAPMountainURL(_ text: String) -> URL? {
        guard let components = URLComponents(string: text) else {
            return nil
        }
        let pathComponents = components.path.split(separator: "/")
        guard
            components.scheme == "https",
            components.host == "yamap.com",
            components.user == nil,
            components.password == nil,
            components.port == nil,
            components.query == nil,
            components.fragment == nil,
            pathComponents.count == 2,
            pathComponents[0] == "mountains",
            let mountainID = Int(pathComponents[1]),
            mountainID > 0
        else {
            return nil
        }
        return components.url
    }

    private static func text(
        in statement: OpaquePointer,
        column: Int32
    ) throws -> String {
        guard
            sqlite3_column_type(statement, column) != SQLITE_NULL,
            let value = sqlite3_column_text(statement, column)
        else {
            throw SQLiteMountainRepositoryError.invalidRecord
        }
        return String(cString: value)
    }
}
