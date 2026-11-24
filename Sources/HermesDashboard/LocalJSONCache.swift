import CSQLite
import Foundation

struct StoredQuote: Equatable {
    let code: String
    let name: String
    let price: Double
    let changePct: Double
    let open: Double?
    let high: Double?
    let low: Double?
    let prevClose: Double
    let time: String
    let volume: Double?
}

struct StoredQuoteSnapshot {
    let fetchedAt: Date
    let quotes: [StoredQuote]
}

struct StoredGMBar {
    let date: String
    let open: Double
    let close: Double
    let high: Double
    let low: Double
}

final class LocalSQLiteStore {
    let databaseURL: URL
    private var database: OpaquePointer?

    init(fileManager: FileManager = .default) throws {
        guard let supportDirectory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw SQLiteStoreError.applicationSupportUnavailable
        }
        let directory = supportDirectory.appendingPathComponent("HermesDashboard", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        databaseURL = directory.appendingPathComponent("dashboard.sqlite3", isDirectory: false)

        var connection: OpaquePointer?
        let result = sqlite3_open_v2(
            databaseURL.path,
            &connection,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard result == SQLITE_OK, let connection else {
            let message = connection.map { String(cString: sqlite3_errmsg($0)) } ?? "无法打开数据库"
            if let connection { sqlite3_close(connection) }
            throw SQLiteStoreError.database(message)
        }
        database = connection
        try execute("PRAGMA foreign_keys = ON")
        try execute("PRAGMA journal_mode = WAL")
        try execute("""
            CREATE TABLE IF NOT EXISTS quote_snapshots (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                fetched_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS quotes (
                snapshot_id INTEGER NOT NULL REFERENCES quote_snapshots(id) ON DELETE CASCADE,
                code TEXT NOT NULL,
                name TEXT NOT NULL,
                price REAL NOT NULL,
                change_pct REAL NOT NULL,
                open REAL,
                high REAL,
                low REAL,
                prev_close REAL NOT NULL,
                quote_time TEXT NOT NULL,
                volume REAL,
                PRIMARY KEY (snapshot_id, code)
            );
            CREATE INDEX IF NOT EXISTS quotes_by_code ON quotes(code, snapshot_id);
            CREATE TABLE IF NOT EXISTS gm_bars (
                date TEXT PRIMARY KEY,
                open REAL NOT NULL,
                close REAL NOT NULL,
                high REAL NOT NULL,
                low REAL NOT NULL,
                updated_at TEXT NOT NULL
            );
        """)
    }

    deinit {
        if let database { sqlite3_close(database) }
    }

    func latestQuoteSnapshot() throws -> StoredQuoteSnapshot? {
        let snapshotSQL = """
            SELECT id, fetched_at FROM quote_snapshots
            ORDER BY fetched_at DESC, id DESC LIMIT 1
        """
        var snapshotStatement = try prepare(snapshotSQL)
        defer { sqlite3_finalize(snapshotStatement) }
        let snapshotResult = sqlite3_step(snapshotStatement)
        if snapshotResult == SQLITE_DONE { return nil }
        guard snapshotResult == SQLITE_ROW else { throw databaseError() }
        guard let dateText = columnText(snapshotStatement, 1),
              let fetchedAt = Self.parseDate(dateText) else { throw SQLiteStoreError.invalidRow }
        let snapshotID = sqlite3_column_int64(snapshotStatement, 0)
        var quoteStatement = try prepare("""
            SELECT code, name, price, change_pct, open, high, low, prev_close, quote_time, volume
            FROM quotes WHERE snapshot_id = ? ORDER BY code
        """)
        defer { sqlite3_finalize(quoteStatement) }
        sqlite3_bind_int64(quoteStatement, 1, snapshotID)
        var quotes: [StoredQuote] = []
        while true {
            let result = sqlite3_step(quoteStatement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw databaseError() }
            guard let code = columnText(quoteStatement, 0),
                  let name = columnText(quoteStatement, 1),
                  let quoteTime = columnText(quoteStatement, 8) else {
                throw SQLiteStoreError.invalidRow
            }
            quotes.append(StoredQuote(
                code: code,
                name: name,
                price: sqlite3_column_double(quoteStatement, 2),
                changePct: sqlite3_column_double(quoteStatement, 3),
                open: optionalDouble(quoteStatement, 4),
                high: optionalDouble(quoteStatement, 5),
                low: optionalDouble(quoteStatement, 6),
                prevClose: sqlite3_column_double(quoteStatement, 7),
                time: quoteTime,
                volume: optionalDouble(quoteStatement, 9)
            ))
        }
        return StoredQuoteSnapshot(fetchedAt: fetchedAt, quotes: quotes)
    }

    func quoteSnapshotCount() throws -> Int {
        try scalarInt("SELECT COUNT(*) FROM quote_snapshots")
    }

    func saveQuoteSnapshot(_ snapshot: StoredQuoteSnapshot) throws {
        try saveQuoteSnapshots([snapshot])
    }

    func saveQuoteSnapshots(_ snapshots: [StoredQuoteSnapshot]) throws {
        guard !snapshots.isEmpty else { return }
        try transaction {
            var snapshotStatement = try prepare("INSERT INTO quote_snapshots(fetched_at) VALUES (?)")
            defer { sqlite3_finalize(snapshotStatement) }
            var quoteStatement = try prepare("""
                INSERT INTO quotes(
                    snapshot_id, code, name, price, change_pct, open, high, low,
                    prev_close, quote_time, volume
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """)
            defer { sqlite3_finalize(quoteStatement) }

            for snapshot in snapshots {
                bind(Self.dateString(snapshot.fetchedAt), to: snapshotStatement, at: 1)
                try stepDone(snapshotStatement)
                let snapshotID = sqlite3_last_insert_rowid(database)
                for quote in snapshot.quotes {
                    sqlite3_bind_int64(quoteStatement, 1, snapshotID)
                    bind(quote.code, to: quoteStatement, at: 2)
                    bind(quote.name, to: quoteStatement, at: 3)
                    sqlite3_bind_double(quoteStatement, 4, quote.price)
                    sqlite3_bind_double(quoteStatement, 5, quote.changePct)
                    bind(quote.open, to: quoteStatement, at: 6)
                    bind(quote.high, to: quoteStatement, at: 7)
                    bind(quote.low, to: quoteStatement, at: 8)
                    sqlite3_bind_double(quoteStatement, 9, quote.prevClose)
                    bind(quote.time, to: quoteStatement, at: 10)
                    bind(quote.volume, to: quoteStatement, at: 11)
                    try stepDone(quoteStatement)
                }
            }
            try execute("""
                DELETE FROM quote_snapshots
                WHERE id NOT IN (
                    SELECT id FROM quote_snapshots ORDER BY fetched_at DESC, id DESC LIMIT 10000
                )
            """)
        }
    }

    func loadGMBars() throws -> [StoredGMBar] {
        var statement = try prepare("SELECT date, open, close, high, low FROM gm_bars ORDER BY date")
        defer { sqlite3_finalize(statement) }
        var bars: [StoredGMBar] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw databaseError() }
            guard let date = columnText(statement, 0) else { throw SQLiteStoreError.invalidRow }
            bars.append(StoredGMBar(
                date: date,
                open: sqlite3_column_double(statement, 1),
                close: sqlite3_column_double(statement, 2),
                high: sqlite3_column_double(statement, 3),
                low: sqlite3_column_double(statement, 4)
            ))
        }
        return bars
    }

    func gmBarCount() throws -> Int {
        try scalarInt("SELECT COUNT(*) FROM gm_bars")
    }

    func upsertGMBars(_ bars: [StoredGMBar], updatedAt: Date) throws {
        guard !bars.isEmpty else { return }
        try transaction {
            var statement = try prepare("""
                INSERT INTO gm_bars(date, open, close, high, low, updated_at)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(date) DO UPDATE SET
                    open = excluded.open,
                    close = excluded.close,
                    high = excluded.high,
                    low = excluded.low,
                    updated_at = excluded.updated_at
            """)
            defer { sqlite3_finalize(statement) }
            let timestamp = Self.dateString(updatedAt)
            for bar in bars {
                bind(bar.date, to: statement, at: 1)
                sqlite3_bind_double(statement, 2, bar.open)
                sqlite3_bind_double(statement, 3, bar.close)
                sqlite3_bind_double(statement, 4, bar.high)
                sqlite3_bind_double(statement, 5, bar.low)
                bind(timestamp, to: statement, at: 6)
                try stepDone(statement)
            }
            try execute("""
                DELETE FROM gm_bars
                WHERE date NOT IN (SELECT date FROM gm_bars ORDER BY date DESC LIMIT 1000)
            """)
        }
    }

    private func transaction(_ work: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try work()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func scalarInt(_ sql: String) throws -> Int {
        var statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw databaseError() }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw databaseError()
        }
        return statement
    }

    private func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? databaseMessage()
            sqlite3_free(errorMessage)
            throw SQLiteStoreError.database(message)
        }
        sqlite3_free(errorMessage)
    }

    private func stepDone(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else { throw databaseError() }
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
    }

    private func bind(_ value: String, to statement: OpaquePointer, at index: Int32) {
        sqlite3_bind_text(statement, index, value, -1, Self.transient)
    }

    private func bind(_ value: Double?, to statement: OpaquePointer, at index: Int32) {
        if let value {
            sqlite3_bind_double(statement, index, value)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func columnText(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard let value = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: value)
    }

    private func optionalDouble(_ statement: OpaquePointer, _ index: Int32) -> Double? {
        sqlite3_column_type(statement, index) == SQLITE_NULL
            ? nil
            : sqlite3_column_double(statement, index)
    }

    private func databaseError() -> SQLiteStoreError {
        SQLiteStoreError.database(databaseMessage())
    }

    private func databaseMessage() -> String {
        guard let database else { return "SQLite 数据库不可用" }
        return String(cString: sqlite3_errmsg(database))
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static func dateString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func parseDate(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }
}

private enum SQLiteStoreError: LocalizedError {
    case applicationSupportUnavailable
    case database(String)
    case invalidRow

    var errorDescription: String? {
        switch self {
        case .applicationSupportUnavailable:
            return "无法定位 macOS Application Support 目录。"
        case .database(let message):
            return "SQLite 错误：\(message)"
        case .invalidRow:
            return "SQLite 缓存数据格式无效。"
        }
    }
}
