import Foundation

/// The lists of the app (same order and meaning as the desktop app).
public enum ListKind: Int, CaseIterable, Identifiable, Sendable {
    case notBack = 1, fans, mutual, followers, following, pending
    case newFollowers, lostFollowers, newFollowing, dropped
    case toUnfollow, kept, closeFriends, recentlyUnfollowed

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .notBack: return "Non ricambiano"
        case .fans: return "Fan"
        case .mutual: return "Reciproci"
        case .followers: return "Follower"
        case .following: return "Seguiti"
        case .pending: return "Richieste in sospeso"
        case .newFollowers: return "Nuovi follower"
        case .lostFollowers: return "Follower persi"
        case .newFollowing: return "Nuovi seguiti"
        case .dropped: return "Non segui più"
        case .toUnfollow: return "Da smettere di seguire"
        case .kept: return "Tenuti"
        case .closeFriends: return "Amici stretti"
        case .recentlyUnfollowed: return "Smessi di recente"
        }
    }

    public var hint: String {
        switch self {
        case .notBack: return "Li segui, ma non ti seguono"
        case .fans: return "Ti seguono, ma tu non li segui"
        case .mutual: return "Vi seguite a vicenda"
        case .followers: return "Tutti quelli che ti seguono"
        case .following: return "Tutti quelli che segui"
        case .pending: return "Richieste inviate a profili privati non ancora accettate"
        case .newFollowers: return "Hanno iniziato a seguirti"
        case .lostFollowers: return "Ti seguivano e ora non più (o hanno cambiato nome o chiuso il profilo)"
        case .newFollowing: return "Hai iniziato a seguirli"
        case .dropped: return "Li seguivi e ora non più"
        case .toUnfollow: return "Aprili e smetti di seguirli su Instagram. Al prossimo import spariscono da soli"
        case .kept: return "Li segui anche se non ricambiano: non compaiono fra i Non ricambiano"
        case .closeFriends: return "La tua lista di amici stretti"
        case .recentlyUnfollowed: return "Profili che hai smesso di seguire, secondo Instagram"
        }
    }

    public var icon: String {
        switch self {
        case .notBack: return "person.fill.xmark"
        case .fans: return "heart.fill"
        case .mutual: return "arrow.left.arrow.right"
        case .followers: return "person.2.fill"
        case .following: return "person.crop.circle.badge.checkmark"
        case .pending: return "hourglass"
        case .newFollowers: return "person.fill.badge.plus"
        case .lostFollowers: return "person.fill.badge.minus"
        case .newFollowing: return "plus.circle.fill"
        case .dropped: return "minus.circle.fill"
        case .toUnfollow: return "xmark.circle.fill"
        case .kept: return "checkmark.seal.fill"
        case .closeFriends: return "star.circle.fill"
        case .recentlyUnfollowed: return "clock.arrow.circlepath"
        }
    }

    public var needsCompare: Bool {
        switch self {
        case .newFollowers, .lostFollowers, .newFollowing, .dropped: return true
        default: return false
        }
    }

    public enum Section: String, CaseIterable, Sendable {
        case relations = "Relazioni"
        case changes = "Cambiamenti"
        case mine = "Le tue liste"
    }

    public var section: Section {
        switch self {
        case .notBack, .fans, .mutual, .followers, .following, .pending: return .relations
        case .newFollowers, .lostFollowers, .newFollowing, .dropped: return .changes
        case .toUnfollow, .kept, .closeFriends, .recentlyUnfollowed: return .mine
        }
    }

    public static func kinds(in section: Section) -> [ListKind] { allCases.filter { $0.section == section } }
}

/// One account seen in the current snapshot and/or the comparison one.
public struct AccountRow: Identifiable, Equatable, Sendable {
    public var username: String
    public var fullName: String
    public var bits: Int = 0
    public var prevBits: Int = 0
    public var since: [Int64] = Array(repeating: 0, count: 8)
    public var prevSince: [Int64] = Array(repeating: 0, count: 8)
    public var mark: MarkState = .none
    public var note: String = ""

    public var id: String { username }

    public init(username: String, fullName: String = "") {
        self.username = username
        self.fullName = fullName
    }

    public func has(_ r: Rel) -> Bool { bits & r.bit != 0 }
    public func had(_ r: Rel) -> Bool { prevBits & r.bit != 0 }

    public var isFollower: Bool { has(.follower) }
    public var isFollowing: Bool { has(.following) }

    public var profileURL: URL { URL(string: "https://www.instagram.com/\(username)/")! }

    public var status: String {
        let f = has(.follower), g = has(.following)
        if f && g { return "Vi seguite a vicenda" }
        if g { return "Lo segui, ma non ti segue" }
        if f { return "Ti segue, tu non lo segui" }
        if had(.follower) { return "Ti ha smesso di seguire" }
        if had(.following) { return "Non lo segui più" }
        if has(.pendingSent) { return "Richiesta di follow in attesa" }
        return ""
    }

    public func relevantDate(for kind: ListKind) -> Int64 {
        let F = Rel.follower.rawValue, G = Rel.following.rawValue
        switch kind {
        case .fans, .followers, .newFollowers: return since[F]
        case .lostFollowers: return prevSince[F]
        case .dropped: return prevSince[G]
        case .mutual: return max(since[F], since[G])
        case .pending: return since[Rel.pendingSent.rawValue]
        case .closeFriends: return since[Rel.closeFriend.rawValue]
        case .recentlyUnfollowed: return since[Rel.unfollowed.rawValue]
        default: return since[G] != 0 ? since[G] : since[F]
        }
    }

    public func subtitle(for kind: ListKind) -> String {
        let d = InstaFormat.date(relevantDate(for: kind))
        guard !d.isEmpty else { return "" }
        switch kind {
        case .fans, .followers, .newFollowers: return "Ti segue dal \(d)"
        case .lostFollowers: return "Ti seguiva dal \(d)"
        case .dropped: return "Lo seguivi dal \(d)"
        case .mutual: return "Reciproci dal \(d)"
        case .pending: return "Richiesta del \(d)"
        case .closeFriends: return "Amico stretto dal \(d)"
        case .recentlyUnfollowed: return "Smesso il \(d)"
        default: return since[Rel.following.rawValue] != 0 ? "Lo segui dal \(d)" : "Ti segue dal \(d)"
        }
    }

    /// "ale_film" → AF, "marco.rossi" → MR, full name "Mario Rossi" → MR.
    public var initials: String {
        let words = fullName.split(separator: " ")
        if words.count >= 2, let a = words[0].first, let b = words[1].first, a.isLetter, b.isLetter {
            return (String(a) + String(b)).uppercased()
        }
        let cleaned = username.map { $0.isNumber ? " " : $0 }
        let parts = String(cleaned).split(whereSeparator: { $0 == "." || $0 == "_" || $0 == " " })
        if parts.count >= 2, let a = parts[0].first, let b = parts[1].first { return (String(a) + String(b)).uppercased() }
        if let p = parts.first { return String(p.prefix(2)).uppercased() }
        return String(username.prefix(2)).uppercased()
    }

    /// Stable muted color for the avatar.
    public var colorHex: String { InstaFormat.avatarColor(username) }
}

public struct HistoryPoint: Equatable, Identifiable, Sendable {
    public var snapshotID: UUID
    public var label: String
    public var takenAt: Date
    public var follower: Bool
    public var following: Bool
    public var isCurrent: Bool
    public var id: UUID { snapshotID }
}

public struct OverviewStats: Equatable, Sendable {
    public var followers = 0, following = 0, mutual = 0, notBack = 0, notBackAll = 0, fans = 0
    public var pending = 0, kept = 0, toUnfollow = 0
    public var newFollowers = 0, lostFollowers = 0, newFollowing = 0, dropped = 0
    public var followersDelta = 0, followingDelta = 0
    public var hasCompare = false
    public var days = 0

    /// followers / following
    public var ratio: Double { following == 0 ? 0 : Double(followers) / Double(following) }
    /// % of followed accounts that follow back.
    public var mutualPercent: Int { following == 0 ? 0 : Int((100 * Double(mutual) / Double(following)).rounded()) }
}

/// The comparison of the current snapshot with the chosen one, plus marks.
public struct Analysis: Sendable {
    public let owner: String
    public let current: Snapshot?
    public let compare: Snapshot?
    public let rows: [AccountRow]
    public let counts: [ListKind: Int]
    public let stats: OverviewStats
    public let showKept: Bool

    public static let empty = Analysis(data: InstaData(), owner: "", currentID: nil, compareID: nil)

    public init(data: InstaData, owner: String, currentID: UUID?, compareID: UUID?) {
        self.owner = owner
        showKept = data.settings.showKept
        let cur = data.snapshots.first { $0.id == currentID && $0.owner == owner }
        let cmp = data.snapshots.first { $0.id == compareID && $0.owner == owner && $0.id != currentID }
        current = cur
        compare = cmp

        var index: [String: Int] = [:]
        var rows: [AccountRow] = []
        func slot(_ e: Entry) -> Int {
            if let i = index[e.username] {
                if rows[i].fullName.isEmpty && !e.fullName.isEmpty { rows[i].fullName = e.fullName }
                return i
            }
            index[e.username] = rows.count
            rows.append(AccountRow(username: e.username, fullName: e.fullName))
            return rows.count - 1
        }
        if let cur {
            for (k, list) in cur.lists where k > 0 && k < 8 {
                for e in list {
                    let i = slot(e)
                    rows[i].bits |= 1 << k
                    rows[i].since[k] = e.since
                }
            }
        }
        if let cmp {
            for (k, list) in cmp.lists where k > 0 && k < 8 {
                for e in list {
                    let i = slot(e)
                    rows[i].prevBits |= 1 << k
                    rows[i].prevSince[k] = e.since
                }
            }
        }
        for (user, m) in data.marks[owner] ?? [:] {
            if let i = index[user] {
                rows[i].mark = m.state
                rows[i].note = m.note
            }
        }
        self.rows = rows

        var counts: [ListKind: Int] = [:]
        for k in ListKind.allCases { counts[k] = 0 }
        var prevF = 0, prevG = 0, notBackAll = 0
        let hasCmp = cmp != nil
        for r in rows {
            for k in ListKind.allCases where Analysis.matches(r, k, hasCompare: hasCmp, showKept: data.settings.showKept) {
                counts[k, default: 0] += 1
            }
            if r.had(.follower) { prevF += 1 }
            if r.had(.following) { prevG += 1 }
            if r.has(.following) && !r.has(.follower) { notBackAll += 1 }
        }
        self.counts = counts

        var s = OverviewStats()
        s.followers = counts[.followers] ?? 0
        s.following = counts[.following] ?? 0
        s.mutual = counts[.mutual] ?? 0
        s.notBack = counts[.notBack] ?? 0
        s.notBackAll = notBackAll
        s.fans = counts[.fans] ?? 0
        s.pending = counts[.pending] ?? 0
        s.kept = counts[.kept] ?? 0
        s.toUnfollow = counts[.toUnfollow] ?? 0
        s.newFollowers = counts[.newFollowers] ?? 0
        s.lostFollowers = counts[.lostFollowers] ?? 0
        s.newFollowing = counts[.newFollowing] ?? 0
        s.dropped = counts[.dropped] ?? 0
        s.hasCompare = hasCmp
        s.followersDelta = hasCmp ? s.followers - prevF : 0
        s.followingDelta = hasCmp ? s.following - prevG : 0
        if let cur, let cmp {
            s.days = Int((cur.takenAt.timeIntervalSince(cmp.takenAt) / 86400).rounded())
        }
        stats = s
    }

    /// Predicate of each list (identical to the desktop app).
    public static func matches(_ r: AccountRow, _ k: ListKind, hasCompare: Bool, showKept: Bool) -> Bool {
        let f = r.has(.follower), g = r.has(.following)
        switch k {
        case .notBack: return g && !f && (showKept || r.mark != .keep)
        case .fans: return f && !g
        case .mutual: return f && g
        case .followers: return f
        case .following: return g
        case .pending: return r.has(.pendingSent)
        case .newFollowers: return hasCompare && f && !r.had(.follower)
        case .lostFollowers: return hasCompare && !f && r.had(.follower)
        case .newFollowing: return hasCompare && g && !r.had(.following)
        case .dropped: return hasCompare && !g && r.had(.following)
        case .toUnfollow: return g && r.mark == .unfollow
        case .kept: return (f || g) && r.mark == .keep
        case .closeFriends: return r.has(.closeFriend)
        case .recentlyUnfollowed: return r.has(.unfollowed)
        }
    }

    public func count(_ k: ListKind) -> Int { counts[k] ?? 0 }

    public func row(_ username: String) -> AccountRow? { rows.first { $0.username == username } }

    /// Rows of a list, filtered by search and sorted.
    public func rows(for k: ListKind, search: String = "", sort: SortMode = .alphabetical) -> [AccountRow] {
        var needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        if needle.hasPrefix("@") { needle.removeFirst() }
        var out = rows.filter { r in
            guard Analysis.matches(r, k, hasCompare: compare != nil, showKept: showKept) else { return false }
            if needle.isEmpty { return true }
            return r.username.contains(needle) || r.fullName.lowercased().contains(needle)
        }
        switch sort {
        case .alphabetical:
            out.sort { $0.username < $1.username }
        case .newest, .oldest:
            let desc = sort == .newest
            out = out.enumerated().sorted { a, b in
                let da = a.element.relevantDate(for: k), db = b.element.relevantDate(for: k)
                if da == db { return a.offset < b.offset }
                return desc ? da > db : da < db
            }.map(\.element)
        }
        return out
    }

    /// Most recent accounts of a list (overview previews).
    public func preview(_ k: ListKind, limit: Int = 12) -> [AccountRow] {
        Array(rows(for: k, sort: .newest).prefix(limit))
    }
}

// MARK: - Library operations

public enum ImportOutcome: Equatable, Sendable {
    case added(id: UUID, owner: String, resolvedUnfollows: Int)
    case duplicate(id: UUID, owner: String)
}

extension InstaData {
    public static let defaultOwner = "il_mio_account"

    /// Owners sorted by name.
    public var owners: [String] {
        Array(Set(snapshots.map(\.owner))).sorted()
    }

    /// Snapshots of an owner, oldest first.
    public func snapshots(of owner: String) -> [Snapshot] {
        snapshots.filter { $0.owner == owner }.sorted { $0.takenAt < $1.takenAt }
    }

    public func mark(_ owner: String, _ username: String) -> MarkInfo {
        marks[owner]?[username] ?? MarkInfo()
    }

    public mutating func setMark(_ owner: String, _ username: String, state: MarkState, now: Date = Date()) {
        var m = mark(owner, username)
        m.state = state
        m.updatedAt = now
        store(owner, username, m)
    }

    public mutating func setNote(_ owner: String, _ username: String, note: String, now: Date = Date()) {
        var m = mark(owner, username)
        m.note = note
        m.updatedAt = now
        store(owner, username, m)
    }

    private mutating func store(_ owner: String, _ username: String, _ m: MarkInfo) {
        var byUser = marks[owner] ?? [:]
        byUser[username] = m.isEmpty ? nil : m
        marks[owner] = byUser.isEmpty ? nil : byUser
    }

    /// Adds an export as a new snapshot (or finds the same one already imported).
    public mutating func importExport(_ e: ParsedExport, preferredOwner: String?, now: Date = Date()) -> ImportOutcome {
        let owner = !e.owner.isEmpty ? e.owner : (preferredOwner?.isEmpty == false ? preferredOwner! : Self.defaultOwner)
        // data without account name + first export with a name: they become one account
        if owner != Self.defaultOwner, owners == [Self.defaultOwner] { renameOwner(Self.defaultOwner, to: owner) }
        let sig = e.signature
        if let dup = snapshots.first(where: { $0.owner == owner && $0.signature == sig }) {
            return .duplicate(id: dup.id, owner: owner)
        }
        var lists: [Int: [Entry]] = [:]
        for (r, l) in e.lists { lists[r.rawValue] = l }
        let snap = Snapshot(owner: owner, label: "Export del \(InstaFormat.date(e.takenAt))", takenAt: e.takenAt,
                            importedAt: now, source: e.source, signature: sig, lists: lists)
        snapshots.append(snap)

        // Marked "to unfollow" and no longer followed: done, the mark goes away.
        var done = 0
        if snapshots(of: owner).last?.id == snap.id {
            let following = Set(snap.list(.following).map(\.username))
            for (user, m) in marks[owner] ?? [:] where m.state == .unfollow && !following.contains(user) {
                setMark(owner, user, state: .none, now: now)
                done += 1
            }
        }
        return .added(id: snap.id, owner: owner, resolvedUnfollows: done)
    }

    public mutating func deleteSnapshot(_ id: UUID) {
        snapshots.removeAll { $0.id == id }
    }

    public mutating func renameSnapshot(_ id: UUID, label: String) {
        let l = label.trimmingCharacters(in: .whitespaces)
        guard !l.isEmpty, let i = snapshots.firstIndex(where: { $0.id == id }) else { return }
        snapshots[i].label = l
    }

    public mutating func setSnapshotDate(_ id: UUID, date: Date) {
        guard let i = snapshots.firstIndex(where: { $0.id == id }) else { return }
        snapshots[i].takenAt = date
    }

    /// Renames (or merges, if the target exists) an account with its marks.
    public mutating func renameOwner(_ from: String, to: String) {
        guard from != to else { return }
        for i in snapshots.indices where snapshots[i].owner == from { snapshots[i].owner = to }
        if let old = marks.removeValue(forKey: from) {
            var target = marks[to] ?? [:]
            for (u, m) in old where target[u] == nil { target[u] = m }
            marks[to] = target
        }
        if settings.lastOwner == from { settings.lastOwner = to }
    }

    /// Presence of an account in every snapshot of the owner.
    public func history(owner: String, username: String, currentID: UUID?) -> [HistoryPoint] {
        snapshots(of: owner).compactMap { s in
            let f = s.list(.follower).contains { $0.username == username }
            let g = s.list(.following).contains { $0.username == username }
            return HistoryPoint(snapshotID: s.id, label: s.label, takenAt: s.takenAt, follower: f, following: g, isCurrent: s.id == currentID)
        }
    }
}

// MARK: - Formatting

public enum InstaFormat {
    static let itLocale = Locale(identifier: "it_IT")

    /// "16 mag 2025"
    public static func date(_ secs: Int64) -> String {
        secs > 0 ? date(Date(timeIntervalSince1970: Double(secs))) : ""
    }

    public static func date(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = itLocale
        f.dateFormat = "d MMM yyyy"
        return f.string(from: d)
    }

    public static func number(_ n: Int) -> String {
        let f = NumberFormatter()
        f.locale = itLocale
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    public static func signed(_ n: Int) -> String {
        n > 0 ? "+\(number(n))" : number(n)
    }

    static let avatarPalette = ["#c0764f", "#b5894a", "#8f9a4e", "#5f9e78", "#4f9a9a",
                                "#5383b5", "#7172b8", "#9467b0", "#ad5f8c", "#b8605f"]

    public static func avatarColor(_ username: String) -> String {
        avatarPalette[Int(FNV1a.hash(username) % UInt64(avatarPalette.count))]
    }

    /// CSV (UTF-8 with BOM, `;`) of a list, as in the desktop app.
    public static func csv(_ rows: [AccountRow]) -> String {
        func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var out = "\u{FEFF}username;nome;profilo;ti segue;lo segui;ti segue dal;lo segui dal;segno;nota\n"
        for r in rows {
            let mark = r.mark == .keep ? "tenuto" : r.mark == .unfollow ? "da smettere" : ""
            out += [q(r.username), q(r.fullName), q("https://www.instagram.com/" + r.username),
                    r.has(.follower) ? "sì" : "no", r.has(.following) ? "sì" : "no",
                    q(date(r.since[Rel.follower.rawValue])), q(date(r.since[Rel.following.rawValue])),
                    q(mark), q(r.note)].joined(separator: ";") + "\n"
        }
        return out
    }
}

// MARK: - Merge (desktop database, backups)

extension InstaData {
    /// Adds a snapshot unless the same export (same lists) is already there.
    /// The signature is recomputed so imports from different sources match.
    @discardableResult
    public mutating func merge(snapshot: Snapshot) -> Bool {
        var parsed = ParsedExport()
        for (k, l) in snapshot.lists { if let r = Rel(rawValue: k) { parsed.lists[r] = l } }
        var s = snapshot
        s.signature = parsed.signature
        guard !snapshots.contains(where: { $0.owner == s.owner && $0.signature == s.signature }) else { return false }
        snapshots.append(s)
        return true
    }

    /// Adds marks that are not already set (existing marks win).
    public mutating func merge(marks other: [String: [String: MarkInfo]]) -> Int {
        var added = 0
        for (owner, byUser) in other {
            for (user, m) in byUser where self.marks[owner]?[user] == nil && !m.isEmpty {
                var target = self.marks[owner] ?? [:]
                target[user] = m
                self.marks[owner] = target
                added += 1
            }
        }
        return added
    }
}
