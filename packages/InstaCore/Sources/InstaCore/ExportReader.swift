import Foundation

public enum ExportError: Error, Equatable, Sendable {
    case unreadable
    case badZip
    case corruptedZip(String)
    case htmlFormat
    case noData

    public var message: String {
        switch self {
        case .unreadable: return "Non riesco a leggere il file."
        case .badZip: return "Lo ZIP non si apre: è completo e non danneggiato?"
        case .corruptedZip(let f): return "Lo ZIP è danneggiato (\(f)): scaricalo di nuovo."
        case .htmlFormat: return "Questo export è in formato HTML. Richiedilo di nuovo scegliendo il formato JSON."
        case .noData: return "Non ho trovato follower né seguiti. Serve l'export JSON di \"Follower e persone seguite\"."
        }
    }
}

/// Reads the official Instagram export (ZIP, folder or single JSON files).
/// Handles old and new formats (2024+, `label_values` 2025), Italian and English labels.
public enum ExportReader {
    /// File name (lowercased) → relation. nil = not interesting, `.none` marker for personal info.
    enum FileKind: Equatable { case rel(Rel), personal }

    static func kind(for baseName: String) -> FileKind? {
        let b = baseName.lowercased()
        if b == "followers.json" || (b.hasPrefix("followers_") && b.hasSuffix(".json")
            && b.dropFirst("followers_".count).dropLast(5).allSatisfy(\.isNumber)) { return .rel(.follower) }
        if b == "following.json" { return .rel(.following) }
        if b == "pending_follow_requests.json" { return .rel(.pendingSent) }
        if b == "close_friends.json" { return .rel(.closeFriend) }
        if b == "blocked_profiles.json" || b == "blocked_accounts.json" { return .rel(.blocked) }
        if b.hasPrefix("recently_unfollowed_") && b.hasSuffix(".json") { return .rel(.unfollowed) }
        if b.hasPrefix("follow_requests_you") && b.hasSuffix("received.json") { return .rel(.requestRecv) }
        if b == "personal_information.json" { return .personal }
        return nil
    }

    public static func isValidUsername(_ s: String) -> Bool {
        guard (1...30).contains(s.count) else { return false }
        return s.unicodeScalars.allSatisfy { c in
            (c >= "a" && c <= "z") || (c >= "0" && c <= "9") || c == "." || c == "_"
        }
    }

    public static func usernameFromHref(_ href: String) -> String {
        guard let url = URL(string: href.trimmingCharacters(in: .whitespaces)) else { return "" }
        let parts = url.path.split(separator: "/").map { String($0).lowercased() }
        for p in parts.reversed() {
            if p == "_u" { continue }
            return isValidUsername(p) ? p : ""
        }
        return ""
    }

    static func pickUsername(value: String, title: String, href: String) -> String {
        let v = value.trimmingCharacters(in: .whitespaces).lowercased()
        let t = title.trimmingCharacters(in: .whitespaces).lowercased()
        if isValidUsername(v) { return v }
        if isValidUsername(t) { return t }
        return usernameFromHref(href)
    }

    static func epoch(_ v: Any?) -> Int64 {
        var raw: Int64 = 0
        if let n = v as? NSNumber { raw = n.int64Value }
        else if let s = v as? String { raw = Int64(s) ?? 0 }
        return raw > 20_000_000_000 ? raw / 1000 : raw
    }

    /// Generic visit, works with all known variants:
    ///  - `[{ "string_list_data": [{href, value, timestamp}] }]` (old)
    ///  - `{ "relationships_following": [{ "title": "user", "string_list_data": [...] }] }` (2024+)
    ///  - `[{ "timestamp": …, "label_values": [{label: "Nome utente", value: "…"}] }]` (2025+)
    static func walk(_ v: Any, into out: inout [Entry], seen: inout Set<String>) {
        if let a = v as? [Any] {
            for x in a { walk(x, into: &out, seen: &seen) }
            return
        }
        guard let o = v as? [String: Any] else { return }

        if let items = o["string_list_data"] as? [Any] {
            let title = o["title"] as? String ?? ""
            for it in items {
                guard let s = it as? [String: Any] else { continue }
                let u = pickUsername(value: s["value"] as? String ?? "", title: title, href: s["href"] as? String ?? "")
                add(Entry(username: u, since: epoch(s["timestamp"])), to: &out, seen: &seen)
            }
            return
        }

        if let lvs = o["label_values"] as? [Any] {
            var user = "", name = "", href = ""
            for x in lvs {
                guard let lv = x as? [String: Any] else { continue }
                let label = (lv["label"] as? String ?? "").trimmingCharacters(in: .whitespaces).lowercased()
                let value = lv["value"] as? String ?? ""
                if href.isEmpty { href = lv["href"] as? String ?? "" }
                if label == "nome utente" || label == "username" { user = value }
                else if label == "nome" || label == "name" { name = value }
                else if label == "url" && href.isEmpty { href = value }
            }
            let u = pickUsername(value: user, title: "", href: href)
            add(Entry(username: u, fullName: name.trimmingCharacters(in: .whitespaces), since: epoch(o["timestamp"])), to: &out, seen: &seen)
            return
        }

        for key in o.keys.sorted() { if let x = o[key] { walk(x, into: &out, seen: &seen) } }
    }

    static func add(_ e: Entry, to list: inout [Entry], seen: inout Set<String>) {
        guard !e.username.isEmpty, !seen.contains(e.username) else { return }
        seen.insert(e.username)
        list.append(e)
    }

    /// personal_information.json: looks for `{"Username"|"Nome utente": {"value": "…"}}`.
    static func findOwner(_ v: Any) -> String? {
        if let a = v as? [Any] {
            for x in a { if let s = findOwner(x) { return s } }
        } else if let o = v as? [String: Any] {
            for key in ["Username", "Nome utente", "username"] {
                if let u = o[key] {
                    let raw = (u as? [String: Any])?["value"] as? String ?? (u as? String ?? "")
                    let s = raw.trimmingCharacters(in: .whitespaces).lowercased()
                    if isValidUsername(s) { return s }
                }
            }
            for key in o.keys.sorted() { if let x = o[key], let s = findOwner(x) { return s } }
        }
        return nil
    }

    public struct RawFile {
        public var name: String
        public var data: Data
        public var modified: Date?

        public init(name: String, data: Data, modified: Date?) {
            self.name = name
            self.data = data
            self.modified = modified
        }
    }

    // MARK: Collect

    static func collectZip(_ zip: MiniZip) throws -> (files: [RawFile], sawHtml: Bool) {
        var files: [RawFile] = []
        var sawHtml = false
        for e in zip.entries {
            let base = e.baseName
            if base.hasSuffix(".html") {
                if base.hasPrefix("followers") { sawHtml = true }
                continue
            }
            guard base.hasSuffix(".json"), kind(for: base) != nil else { continue }
            guard let data = zip.read(e) else { throw ExportError.corruptedZip(base) }
            files.append(RawFile(name: base, data: data, modified: e.modified))
        }
        return (files, sawHtml)
    }

    static func collectFolder(_ url: URL) -> (files: [RawFile], sawHtml: Bool) {
        var files: [RawFile] = []
        var sawHtml = false
        let fm = FileManager.default
        guard let en = fm.enumerator(at: url, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]) else { return ([], false) }
        for case let f as URL in en {
            let base = f.lastPathComponent.lowercased()
            if base.hasSuffix(".html") {
                if base.hasPrefix("followers") { sawHtml = true }
                continue
            }
            if base.hasSuffix(".zip"), files.isEmpty, let zip = try? MiniZip(url: f), let r = try? collectZip(zip) {
                files += r.files
                sawHtml = sawHtml || r.sawHtml
                continue
            }
            guard base.hasSuffix(".json"), kind(for: base) != nil, let data = try? Data(contentsOf: f) else { continue }
            let mod = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            files.append(RawFile(name: base, data: data, modified: mod))
        }
        return (files, sawHtml)
    }

    // MARK: Read

    /// Reads a ZIP, a folder or a single JSON file.
    public static func read(url: URL) throws -> ParsedExport {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { throw ExportError.unreadable }
        let collected: (files: [RawFile], sawHtml: Bool)
        if isDir.boolValue {
            collected = collectFolder(url)
        } else if url.pathExtension.lowercased() == "json" {
            guard let data = try? Data(contentsOf: url) else { throw ExportError.unreadable }
            collected = ([RawFile(name: url.lastPathComponent.lowercased(), data: data, modified: nil)], false)
        } else {
            let zip: MiniZip
            do { zip = try MiniZip(url: url) } catch { throw ExportError.badZip }
            collected = try collectZip(zip)
        }
        let name = isDir.boolValue ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
        let fileDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return try parse(files: collected.files, sawHtml: collected.sawHtml, sourceName: name, source: url.lastPathComponent, fallbackDate: fileDate)
    }

    /// Builds the export from raw files (also used by tests).
    public static func parse(files: [RawFile], sawHtml: Bool = false, sourceName: String, source: String = "", fallbackDate: Date? = nil) throws -> ParsedExport {
        var out = ParsedExport(source: source)
        var seen: [Rel: Set<String>] = [:]
        var newestFile: Date?
        for f in files {
            guard let k = kind(for: f.name),
                  let root = try? JSONSerialization.jsonObject(with: f.data, options: [.fragmentsAllowed]) else { continue }
            switch k {
            case .personal:
                if let o = findOwner(root) { out.owner = o }
            case .rel(let r):
                var list = out.lists[r] ?? []
                var s = seen[r] ?? []
                walk(root, into: &list, seen: &s)
                out.lists[r] = list
                seen[r] = s
                out.filesRead.append(f.name)
                if let m = f.modified, newestFile == nil || m > newestFile! { newestFile = m }
            }
        }
        if out.isEmpty { throw sawHtml ? ExportError.htmlFormat : ExportError.noData }

        // Owner and date from the export name: "instagram-mario.rossi-2025-05-16-AbCdEf"
        var taken: Date?
        if let m = parseExportName(sourceName) {
            if out.owner.isEmpty { out.owner = m.owner }
            taken = m.date
        }
        out.takenAt = taken ?? newestFile ?? fallbackDate ?? Date()

        // The export cannot be older than the newest follow it contains.
        let newest = out.lists.values.flatMap { $0 }.map(\.since).max() ?? 0
        if newest > 0, out.takenAt.timeIntervalSince1970 < Double(newest) {
            out.takenAt = Date(timeIntervalSince1970: Double(newest))
        }
        return out
    }

    /// "instagram-mario.rossi-2025-05-16-AbCdEf" → ("mario.rossi", 2025-05-16 12:00 UTC)
    public static func parseExportName(_ name: String) -> (owner: String, date: Date)? {
        let lower = name.lowercased()
        guard let r = lower.range(of: "instagram-") else { return nil }
        let rest = String(name[r.upperBound...])
        // find "-YYYY-MM-DD" after the username
        let chars = Array(rest)
        var i = 1
        while i + 11 <= chars.count {
            if chars[i] == "-",
               chars[(i + 1)...(i + 4)].allSatisfy(\.isNumber), chars[i + 5] == "-",
               chars[(i + 6)...(i + 7)].allSatisfy(\.isNumber), chars[i + 8] == "-",
               chars[(i + 9)...(i + 10)].allSatisfy(\.isNumber) {
                let owner = String(chars[0..<i]).lowercased()
                guard isValidUsername(owner) else { return nil }
                var c = DateComponents()
                c.year = Int(String(chars[(i + 1)...(i + 4)]))
                c.month = Int(String(chars[(i + 6)...(i + 7)]))
                c.day = Int(String(chars[(i + 9)...(i + 10)]))
                c.hour = 12
                var cal = Calendar(identifier: .gregorian)
                cal.timeZone = TimeZone(identifier: "UTC")!
                guard let d = cal.date(from: c) else { return nil }
                return (owner, d)
            }
            i += 1
        }
        return nil
    }
}
