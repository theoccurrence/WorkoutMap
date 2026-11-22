import Foundation
import Combine
import SQLite3

/// The app's own edits to how a workout's route is *drawn* — the stretches the route-editing
/// mode erased — kept in a small SQLite database in Application Support.
///
/// A database rather than the route cache's own files, for two reasons: the edits are the user's
/// work, so they must not live in `Caches` (which iOS may purge under pressure) and must survive
/// the route itself being fetched from Health again; and a row per edited workout is the smallest
/// thing that can be written and read. Nothing here is ever written back to Health — Health's
/// data is untouched; only the app's drawing of it changes.
///
/// The whole table is read once, at launch, into memory: every screen that draws a route then
/// pays one dictionary lookup per workout and never a disk read, and the database only moves when
/// the user actually saves an edit. One row holds the erased legs as text — `12-40,58` — which for
/// a route erased in a few stretches is a few dozen bytes.
///
/// Reads and writes are behind `lock` rather than an actor: like `RouteStore`, this is reached
/// from the render path, which is not one place, and a lock is the whole of what it needs.
final class EraseStore: ObservableObject {
    static let shared = EraseStore()

    /// Bumped every time an edit is written, so a screen that observes the store draws the route
    /// again the moment it changed. Published from `set`, which the edit screen calls on the main
    /// thread.
    @Published private(set) var revision = 0

    private let lock = NSLock()
    private var memory: [UUID: EraseEdits] = [:]
    /// When each edit was last written, so the settings list has an order to show. Not kept in
    /// the database beyond the row's own `updated` column; this is only the in-memory copy.
    private var updated: [UUID: Date] = [:]
    private var database: OpaquePointer?

    private init() {
        open()
        load()
    }

    /// The legs erased from a workout's route, or `.empty` when it has never been edited.
    func edits(for id: UUID) -> EraseEdits {
        lock.lock()
        defer { lock.unlock() }
        return memory[id] ?? .empty
    }

    /// How many workouts carry an edit — the row count, read without walking the table.
    var editedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return memory.count
    }

    /// One edited workout: its id, the edits, and when they were last written.
    struct Entry: Identifiable {
        let id: UUID
        let edits: EraseEdits
        let updated: Date
    }

    /// Every edit the store holds, most recently written first — what the settings list shows.
    func entries() -> [Entry] {
        lock.lock()
        defer { lock.unlock() }
        return memory
            .map { Entry(id: $0.key, edits: $0.value, updated: updated[$0.key] ?? .distantPast) }
            .sorted { $0.updated > $1.updated }
    }

    /// Forgets a workout's edits. What the settings list's bin does: an edit can go without the
    /// workout ever being opened.
    func remove(for id: UUID) { set(.empty, for: id) }

    /// Writes (or, for `.empty`, removes) a workout's edits. The memory copy is what every
    /// drawing reads, and it is updated whether or not the row made it to disk — a database that
    /// cannot be written must not make the app lie about what it is showing.
    func set(_ edits: EraseEdits, for id: UUID) {
        let stamp = Date()
        lock.lock()
        if edits.isEmpty {
            memory[id] = nil
            updated[id] = nil
        } else {
            memory[id] = edits
            updated[id] = stamp
        }
        lock.unlock()

        revision &+= 1
        if edits.isEmpty {
            execute("DELETE FROM erase_edits WHERE workout_id = ?;", [id.uuidString])
        } else {
            execute("""
                INSERT INTO erase_edits (workout_id, legs, updated) VALUES (?, ?, ?)
                ON CONFLICT(workout_id) DO UPDATE SET legs = excluded.legs, updated = excluded.updated;
                """, [id.uuidString, edits.stored, stamp.timeIntervalSince1970])
        }
    }

    // MARK: - moving the edits between devices

    /// The file the edits travel in: one row per edited workout, the same text the database keeps
    /// under the workout's **id**. The id is the key on both devices — the same Health workout
    /// carries the same UUID in iCloud — so edits land on the same route, and an id whose workout
    /// this device does not have is simply never drawn: an import of edits for workouts this device
    /// has never seen is harmless, not an error.
    struct Document: Codable {
        var app: String?
        var version: Int?
        var edits: [Row]

        struct Row: Codable {
            var workout: String
            var legs: String
        }
    }

    /// Everything the store holds, as the file to export.
    func exportData() throws -> Data {
        let document = Document(app: "WorkoutMap",
                                version: 1,
                                edits: entries().map { Document.Row(workout: $0.id.uuidString,
                                                                    legs: $0.edits.stored) })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    /// Merges a file into the store. The erased legs are **unioned** with what is already here, so
    /// importing twice changes nothing and an edit made on this device is never lost to an import.
    /// Returns how many edits the file carried and this device understood; a row whose workout id
    /// or leg list is unreadable is skipped rather than failing the whole file.
    @discardableResult
    func importData(_ data: Data) throws -> Int {
        let document = try JSONDecoder().decode(Document.self, from: data)
        var applied = 0
        for row in document.edits {
            guard let id = UUID(uuidString: row.workout),
                  let incoming = EraseEdits(stored: row.legs),
                  !incoming.isEmpty else { continue }
            set(edits(for: id).merging(incoming), for: id)
            applied += 1
        }
        return applied
    }

    // MARK: - the database

    /// `sqlite3` wants to know who owns the bound bytes; `TRANSIENT` makes it copy them, which is
    /// what a Swift `String` handed over for a single statement needs.
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private func open() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = base.appendingPathComponent("WorkoutMap", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("edits.sqlite")

        guard sqlite3_open_v2(url.path, &database,
                              SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
                              nil) == SQLITE_OK else {
            database = nil
            return
        }
        execute("PRAGMA journal_mode = WAL;")
        execute("""
            CREATE TABLE IF NOT EXISTS erase_edits (
                workout_id TEXT PRIMARY KEY,
                legs       TEXT NOT NULL,
                updated    REAL NOT NULL
            );
            """)
    }

    /// Reads the whole table into memory. A row that cannot be read is skipped rather than
    /// reported: it costs the user an edit they can make again, not a launch that fails.
    private func load() {
        guard let database else { return }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT workout_id, legs, updated FROM erase_edits;", -1,
                                 &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idText = sqlite3_column_text(statement, 0),
                  let legsText = sqlite3_column_text(statement, 1),
                  let id = UUID(uuidString: String(cString: idText)),
                  let edits = EraseEdits(stored: String(cString: legsText)) else { continue }
            memory[id] = edits
            updated[id] = Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
        }
    }

    @discardableResult
    private func execute(_ sql: String, _ values: [Any] = []) -> Bool {
        guard let database else { return false }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(statement) }
        for (offset, value) in values.enumerated() {
            bind(statement, Int32(offset + 1), value)
        }
        return sqlite3_step(statement) == SQLITE_DONE
    }

    private func bind(_ statement: OpaquePointer?, _ index: Int32, _ value: Any) {
        switch value {
        case let text as String:
            sqlite3_bind_text(statement, index, text, -1, EraseStore.transient)
        case let number as Double:
            sqlite3_bind_double(statement, index, number)
        case let number as Int:
            sqlite3_bind_int64(statement, index, Int64(number))
        default:
            sqlite3_bind_null(statement, index)
        }
    }
}
