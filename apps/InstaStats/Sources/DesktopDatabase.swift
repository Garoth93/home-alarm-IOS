import Foundation
import SQLite3
import InstaCore

/// Reads the SQLite database of the desktop app (instaStats 2, `instastats.db`):
///
///     snapshot (id, owner, label, taken_at, imported_at, source, signature)
///     profile  (id, username, full_name)
///     relation (snapshot_id, kind, profile_id, since)
///     mark     (owner, profile_id, state, note, updated_at)
enum DesktopDatabase {
    struct Content {
        var snapshots: [Snapshot]
        var marks: [String: [String: MarkInfo]]
    }

    struct DBError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func read(url: URL) throws -> Content {
        // Work on a copy: the picked file may be read-only or in iCloud.
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("desktop-\(UUID().uuidString).db")
        try FileManager.default.copyItem(at: url, to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        var db: OpaquePointer?
        guard sqlite3_open_v2(tmp.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            throw DBError(message: "Il file non è un database SQLite.")
        }
        defer { sqlite3_close(db) }

        func query(_ sql: String, _ row: (OpaquePointer) -> Void) throws {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
                throw DBError(message: "Non è il database di instaStats 2 (tabelle mancanti).")
            }
            defer { sqlite3_finalize(stmt) }
            while sqlite3_step(stmt) == SQLITE_ROW { row(stmt) }
        }

        func text(_ s: OpaquePointer, _ i: Int32) -> String {
            guard let c = sqlite3_column_text(s, i) else { return "" }
            return String(cString: c)
        }

        var profiles: [Int64: (String, String)] = [:]
        try query("SELECT id, username, full_name FROM profile") { s in
            profiles[sqlite3_column_int64(s, 0)] = (text(s, 1), text(s, 2))
        }

        struct Snap { var owner: String; var label: String; var taken: Int64; var imported: Int64; var source: String; var lists: [Int: [Entry]] }
        var snaps: [Int64: Snap] = [:]
        try query("SELECT id, owner, label, taken_at, imported_at, source FROM snapshot") { s in
            snaps[sqlite3_column_int64(s, 0)] = Snap(owner: text(s, 1), label: text(s, 2), taken: sqlite3_column_int64(s, 3),
                                                     imported: sqlite3_column_int64(s, 4), source: text(s, 5), lists: [:])
        }
        try query("SELECT snapshot_id, kind, profile_id, since FROM relation") { s in
            let sid = sqlite3_column_int64(s, 0)
            let kind = Int(sqlite3_column_int(s, 1))
            guard snaps[sid] != nil, (1...7).contains(kind), let p = profiles[sqlite3_column_int64(s, 2)] else { return }
            snaps[sid]!.lists[kind, default: []].append(Entry(username: p.0, fullName: p.1, since: sqlite3_column_int64(s, 3)))
        }

        var marks: [String: [String: MarkInfo]] = [:]
        try? query("SELECT owner, profile_id, state, note, updated_at FROM mark") { s in
            guard let p = profiles[sqlite3_column_int64(s, 1)] else { return }
            let state = MarkState(rawValue: Int(sqlite3_column_int(s, 2))) ?? .none
            let m = MarkInfo(state: state, note: text(s, 3), updatedAt: Date(timeIntervalSince1970: Double(sqlite3_column_int64(s, 4))))
            guard !m.isEmpty else { return }
            marks[text(s, 0), default: [:]][p.0] = m
        }

        let out = snaps.values.sorted { $0.taken < $1.taken }.map { s in
            Snapshot(owner: s.owner, label: s.label.isEmpty ? "Export desktop" : s.label,
                     takenAt: Date(timeIntervalSince1970: Double(s.taken)),
                     importedAt: Date(timeIntervalSince1970: Double(s.imported)),
                     source: s.source, lists: s.lists)
        }
        guard !out.isEmpty else { throw DBError(message: "Il database non contiene istantanee.") }
        return Content(snapshots: out, marks: marks)
    }
}
