import Foundation
import Combine
import SQLite3

/// The app's own edits to how a workout's route is *drawn* — the stretches the route editor's
/// eraser took out, and the legs the user flagged as ground they really covered — kept in a small
/// SQLite database in Application Support.
///
/// A database rather than the route cache's own files, for two reasons: the edits are the user's
/// work, so they must not live in `Caches` (which iOS may purge under pressure) and must survive the
/// route itself being fetched from Health again; and a row per edited workout is the smallest thing
/// that can be written and read. Nothing here is ever written back to Health — Health's data is
/// untouched; only the app's drawing of it changes.
///
/// The whole table is read once, at launch, into memory: every screen that draws a route then pays
/// one dictionary lookup per workout and never a disk read, and the database only moves when the
/// user actually saves an edit. One row holds each set of legs as text — `12-40,58` — which for a
/// route edited in a few stretches is a few dozen bytes.
///
/// Reads and writes are behind `lock` rather than an actor: like `RouteStore`, this is reached from
/// the render path, which is not one place, and a lock is the whole of what it needs.
final class RouteEditStore: ObservableObject {
    static let shared = RouteEditStore()

    /// Bumped every time an edit is written, so a screen that observes the store draws the route
    /// again the moment it changed. Published from `set`, which the edit screen calls on the main
    /// thread.
    @Published private(set) var revision = 0

    private let lock = NSLock()
    private var memory: [UUID: RouteEdits] = [:]
    /// When each edit was last written, so the settings list has an order to show. Not kept in the
    /// database beyond the row's own `updated` column; this is only the in-memory copy.
    private var updated: [UUID: Date] = [:]
    private var database: OpaquePointer?

    private init() {
        open()
        load()
    }

    /// What the user has changed about a workout's route, or `.empty` when it has never been edited.
    func edits(for id: UUID) -> RouteEdits {
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
        let edits: RouteEdits
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

    /// Writes (or, for `.empty`, removes) a workout's edits. The memory copy is what every drawing
    /// reads, and it is updated whether or not the row made it to disk — a database that cannot be
    /// written must not make the app lie about what it is showing.
    func set(_ edits: RouteEdits, for id: UUID) {
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
            execute("DELETE FROM route_edits WHERE workout_id = ?;", [id.uuidString])
        } else {
            execute("""
                INSERT INTO route_edits (workout_id, erased, validated, updated) VALUES (?, ?, ?, ?)
                ON CONFLICT(workout_id) DO UPDATE SET erased = excluded.erased,
                                                      validated = excluded.validated,
                                                      updated = excluded.updated;
                """, [id.uuidString, edits.storedErased, edits.storedValidated,
                      stamp.timeIntervalSince1970])
        }
    }

    // MARK: - moving the edits between devices

    /// The file the edits travel in: one row per edited workout, the same text the database keeps
    /// under the workout's **id**. The id is the key on both devices — the same Health workout
    /// carries the same UUID in iCloud — so edits land on the same route, and an id whose workout
    /// this device does not have is simply never drawn: an import of edits for workouts this device
    /// has never seen is harmless, not an error.
    ///
    /// `legs` is the key the erased set travelled under before the *valid* tool existed; it is still
    /// read, so a file exported by that build imports whole.
    struct Document: Codable {
        var app: String?
        var version: Int?
        var edits: [Row]

        struct Row: Codable {
            var workout: String
            var erased: String?
            var validated: String?
            var legs: String?

            /// The erased legs, whichever key carries them.
            var erasedLegs: String { erased ?? legs ?? "" }
        }
    }

    /// Everything the store holds, as the file to export.
    func exportData() throws -> Data {
        let document = Document(app: "WorkoutMap",
                                version: 1,
                                edits: entries().map { entry in
                                    Document.Row(workout: entry.id.uuidString,
                                                 erased: entry.edits.storedErased,
                                                 validated: entry.edits.storedValidated)
                                })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    /// Merges a file into the store. The legs are **unioned** with what is already here, so importing
    /// twice changes nothing and an edit made on this device is never lost to an import. Returns how
    /// many edits the file carried and this device understood; a row whose workout id or leg lists
    /// are unreadable is skipped rather than failing the whole file.
    @discardableResult
    func importData(_ data: Data) throws -> Int {
        let document = try JSONDecoder().decode(Document.self, from: data)
        var applied = 0
        for row in document.edits {
            guard let id = UUID(uuidString: row.workout),
                  let incoming = RouteEdits(storedErased: row.erasedLegs,
                                            storedValidated: row.validated ?? ""),
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
            CREATE TABLE IF NOT EXISTS route_edits (
                workout_id TEXT PRIMARY KEY,
                erased     TEXT NOT NULL,
                validated  TEXT NOT NULL,
                updated    REAL NOT NULL
            );
            """)
        migrateErasedOnlyTable()
    }

    /// Carries a database written before the *valid* tool existed into the shape above: it held one
    /// table, `erase_edits`, with the erased legs in a `legs` column. The rows are moved over and the
    /// old table dropped, so nobody loses the edits they had already made.
    private func migrateErasedOnlyTable() {
        guard tableExists("erase_edits") else { return }
        execute("""
            INSERT INTO route_edits (workout_id, erased, validated, updated)
            SELECT workout_id, legs, '', updated FROM erase_edits
            WHERE workout_id NOT IN (SELECT workout_id FROM route_edits);
            """)
        execute("DROP TABLE erase_edits;")
    }

    private func tableExists(_ name: String) -> Bool {
        guard let database else { return false }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database,
                                 "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?;",
                                 -1, &statement, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, name, -1, Self.transient)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    /// Reads the whole table into memory. A row that cannot be read is skipped rather than reported:
    /// it costs the user an edit they can make again, not a launch that fails.
    private func load() {
        guard let database else { return }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database,
                                 "SELECT workout_id, erased, validated, updated FROM route_edits;",
                                 -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idText = sqlite3_column_text(statement, 0),
                  let erasedText = sqlite3_column_text(statement, 1),
                  let validatedText = sqlite3_column_text(statement, 2),
                  let id = UUID(uuidString: String(cString: idText)),
                  let edits = RouteEdits(storedErased: String(cString: erasedText),
                                         storedValidated: String(cString: validatedText))
            else { continue }
            memory[id] = edits
            updated[id] = Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
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
            sqlite3_bind_text(statement, index, text, -1, RouteEditStore.transient)
        case let number as Double:
            sqlite3_bind_double(statement, index, number)
        case let number as Int:
            sqlite3_bind_int64(statement, index, Int64(number))
        default:
            sqlite3_bind_null(statement, index)
        }
    }
}
