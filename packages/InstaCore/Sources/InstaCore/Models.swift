import Foundation

/// Relationship types read from the Instagram export (same values as the desktop app).
public enum Rel: Int, Codable, CaseIterable, Sendable {
    case follower = 1      // followers_N.json
    case following = 2     // following.json
    case pendingSent = 3   // pending_follow_requests.json
    case closeFriend = 4   // close_friends.json
    case blocked = 5       // blocked_profiles.json
    case unfollowed = 6    // recently_unfollowed_profiles.json
    case requestRecv = 7   // follow_requests_you've_received.json

    public var bit: Int { 1 << rawValue }
}

/// User mark on an account (persists across snapshots).
public enum MarkState: Int, Codable, Sendable {
    case none = 0
    case keep = 1        // "va bene così": followed even if not following back
    case unfollow = -1   // to unfollow

    public var label: String {
        switch self {
        case .none: return "Nessun segno"
        case .keep: return "Tenuto"
        case .unfollow: return "Da smettere"
        }
    }
}

/// One account in a list of the export.
public struct Entry: Codable, Equatable, Hashable, Sendable {
    public var username: String
    public var fullName: String
    /// Seconds since epoch (0 = unknown).
    public var since: Int64

    public init(username: String, fullName: String = "", since: Int64 = 0) {
        self.username = username
        self.fullName = fullName
        self.since = since
    }

    private enum CodingKeys: String, CodingKey { case u, n, s }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        username = try c.decode(String.self, forKey: .u)
        fullName = try c.decodeIfPresent(String.self, forKey: .n) ?? ""
        since = try c.decodeIfPresent(Int64.self, forKey: .s) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(username, forKey: .u)
        if !fullName.isEmpty { try c.encode(fullName, forKey: .n) }
        if since != 0 { try c.encode(since, forKey: .s) }
    }
}

/// The useful content of one export, before it becomes a snapshot.
public struct ParsedExport: Equatable, Sendable {
    public var owner: String
    public var takenAt: Date
    public var source: String
    public var lists: [Rel: [Entry]]
    public var filesRead: [String]

    public init(owner: String = "", takenAt: Date = Date(), source: String = "", lists: [Rel: [Entry]] = [:], filesRead: [String] = []) {
        self.owner = owner
        self.takenAt = takenAt
        self.source = source
        self.lists = lists
        self.filesRead = filesRead
    }

    public func count(_ r: Rel) -> Int { lists[r]?.count ?? 0 }
    public var isEmpty: Bool { count(.follower) == 0 && count(.following) == 0 }

    /// Identifies the same export imported twice (follower, following, pending).
    public var signature: String {
        var h = FNV1a()
        for r in [Rel.follower, .following, .pendingSent] {
            h.add("\(r.rawValue):")
            h.add((lists[r] ?? []).map(\.username).sorted().joined(separator: ","))
            h.add(";")
        }
        return h.hex
    }
}

/// One imported export.
public struct Snapshot: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var owner: String
    public var label: String
    public var takenAt: Date
    public var importedAt: Date
    public var source: String
    public var signature: String
    /// Keyed by `Rel.rawValue`.
    public var lists: [Int: [Entry]]

    public init(id: UUID = UUID(), owner: String, label: String, takenAt: Date, importedAt: Date = Date(),
                source: String = "", signature: String = "", lists: [Int: [Entry]] = [:]) {
        self.id = id
        self.owner = owner
        self.label = label
        self.takenAt = takenAt
        self.importedAt = importedAt
        self.source = source
        self.signature = signature
        self.lists = lists
    }

    public func list(_ r: Rel) -> [Entry] { lists[r.rawValue] ?? [] }
    public var followers: Int { list(.follower).count }
    public var following: Int { list(.following).count }
}

public struct MarkInfo: Codable, Equatable, Sendable {
    public var state: MarkState
    public var note: String
    public var updatedAt: Date

    public init(state: MarkState = .none, note: String = "", updatedAt: Date = Date()) {
        self.state = state
        self.note = note
        self.updatedAt = updatedAt
    }

    public var isEmpty: Bool { state == .none && note.isEmpty }
}

public enum SortMode: Int, Codable, CaseIterable, Sendable {
    case alphabetical = 0, newest = 1, oldest = 2

    public var label: String {
        switch self {
        case .alphabetical: return "A–Z"
        case .newest: return "Più recenti"
        case .oldest: return "Meno recenti"
        }
    }
}

public enum Appearance: String, Codable, CaseIterable, Sendable {
    case system, light, dark

    public var label: String {
        switch self {
        case .system: return "Automatico"
        case .light: return "Chiaro"
        case .dark: return "Scuro"
        }
    }
}

public struct InstaSettings: Codable, Equatable, Sendable {
    public var showKept: Bool
    public var sortMode: SortMode
    public var lastOwner: String?
    public var appearance: Appearance

    public init(showKept: Bool = false, sortMode: SortMode = .alphabetical, lastOwner: String? = nil, appearance: Appearance = .system) {
        self.showKept = showKept
        self.sortMode = sortMode
        self.lastOwner = lastOwner
        self.appearance = appearance
    }

    private enum CodingKeys: String, CodingKey { case showKept, sortMode, lastOwner, appearance }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showKept = try c.decodeIfPresent(Bool.self, forKey: .showKept) ?? false
        sortMode = (try? c.decodeIfPresent(SortMode.self, forKey: .sortMode)) ?? .alphabetical
        lastOwner = try c.decodeIfPresent(String.self, forKey: .lastOwner)
        appearance = (try? c.decodeIfPresent(Appearance.self, forKey: .appearance)) ?? .system
    }
}

/// Everything the app saves.
public struct InstaData: Codable, Equatable, Sendable {
    public var version: Int
    public var snapshots: [Snapshot]
    /// owner → username → mark
    public var marks: [String: [String: MarkInfo]]
    public var settings: InstaSettings

    public init(snapshots: [Snapshot] = [], marks: [String: [String: MarkInfo]] = [:], settings: InstaSettings = InstaSettings()) {
        self.version = 1
        self.snapshots = snapshots
        self.marks = marks
        self.settings = settings
    }

    private enum CodingKeys: String, CodingKey { case version, snapshots, marks, settings }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        snapshots = try c.decodeIfPresent([Snapshot].self, forKey: .snapshots) ?? []
        marks = try c.decodeIfPresent([String: [String: MarkInfo]].self, forKey: .marks) ?? [:]
        settings = try c.decodeIfPresent(InstaSettings.self, forKey: .settings) ?? InstaSettings()
    }
}

// MARK: - Hash

/// FNV-1a 64-bit: stable across launches and platforms (unlike `Hasher`).
public struct FNV1a {
    public private(set) var value: UInt64 = 0xcbf29ce484222325

    public init() {}

    public mutating func add(_ s: String) {
        for b in s.utf8 {
            value ^= UInt64(b)
            value = value &* 0x100000001b3
        }
    }

    public var hex: String { String(format: "%016llx", value) }

    public static func hash(_ s: String) -> UInt64 {
        var h = FNV1a()
        h.add(s)
        return h.value
    }
}
