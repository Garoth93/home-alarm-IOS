import Foundation

// MARK: - Zone

/// One arming combination of a house, e.g. "Notte" → `attiva 1-2`.
public struct Zone: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// Command text sent before the password, e.g. "attiva 1-2-3".
    public var command: String
    /// SF Symbol name.
    public var icon: String
    public var colorHex: String

    public init(id: UUID = UUID(), name: String, command: String, icon: String = "shield.fill", colorHex: String = Palette.defaultAccent) {
        self.id = id
        self.name = name
        self.command = command
        self.icon = icon
        self.colorHex = colorHex
    }

    private enum CodingKeys: String, CodingKey { case id, name, command, icon, colorHex }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        command = try c.decodeIfPresent(String.self, forKey: .command) ?? ""
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? "shield.fill"
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? Palette.defaultAccent
    }
}

// MARK: - House

/// A house with its alarm control unit, reached by SMS at `phoneNumber`.
/// The password is NOT stored here: the app keeps it in the Keychain.
public struct House: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var phoneNumber: String
    public var icon: String
    public var colorHex: String
    /// The single disarm command, e.g. "disattiva".
    public var disarmCommand: String
    /// Optional status request command (empty = not supported).
    public var statusCommand: String
    /// SMS template; `{comando}` and `{password}` are replaced.
    public var messageTemplate: String
    public var zones: [Zone]

    public init(
        id: UUID = UUID(),
        name: String,
        phoneNumber: String = "",
        icon: String = "house.fill",
        colorHex: String = Palette.defaultAccent,
        disarmCommand: String = "disattiva",
        statusCommand: String = "",
        messageTemplate: String = MessageBuilder.defaultTemplate,
        zones: [Zone] = []
    ) {
        self.id = id
        self.name = name
        self.phoneNumber = phoneNumber
        self.icon = icon
        self.colorHex = colorHex
        self.disarmCommand = disarmCommand
        self.statusCommand = statusCommand
        self.messageTemplate = messageTemplate
        self.zones = zones
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, phoneNumber, icon, colorHex, disarmCommand, statusCommand, messageTemplate, zones
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        phoneNumber = try c.decodeIfPresent(String.self, forKey: .phoneNumber) ?? ""
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? "house.fill"
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? Palette.defaultAccent
        disarmCommand = try c.decodeIfPresent(String.self, forKey: .disarmCommand) ?? "disattiva"
        statusCommand = try c.decodeIfPresent(String.self, forKey: .statusCommand) ?? ""
        messageTemplate = try c.decodeIfPresent(String.self, forKey: .messageTemplate) ?? MessageBuilder.defaultTemplate
        zones = try c.decodeIfPresent([Zone].self, forKey: .zones) ?? []
    }

    public func zone(_ id: UUID?) -> Zone? {
        guard let id else { return nil }
        return zones.first { $0.id == id }
    }

    /// Phone number with spaces, dots, dashes and parentheses removed.
    public var normalizedPhoneNumber: String {
        MessageBuilder.normalize(phone: phoneNumber)
    }

    public var supportsStatus: Bool {
        !statusCommand.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Example house used by the onboarding (zones from the user's alarm).
    public static func example(name: String = "Casa") -> House {
        House(
            name: name,
            icon: "house.fill",
            colorHex: "#3949ab",
            disarmCommand: "disattiva",
            zones: [
                Zone(name: "Totale", command: "attiva 1-2-3", icon: "lock.shield.fill", colorHex: "#3949ab"),
                Zone(name: "Notte", command: "attiva 1-2", icon: "moon.stars.fill", colorHex: "#5e35b1"),
                Zone(name: "Perimetrale", command: "attiva 1", icon: "door.left.hand.closed", colorHex: "#00897b")
            ]
        )
    }
}

// MARK: - Events

public enum CommandKind: String, Codable, CaseIterable, Sendable {
    case arm, disarm, status

    public var label: String {
        switch self {
        case .arm: return "Inserimento"
        case .disarm: return "Disinserimento"
        case .status: return "Richiesta stato"
        }
    }
}

public enum EventResult: String, Codable, CaseIterable, Sendable {
    case sent, cancelled, failed

    public var label: String {
        switch self {
        case .sent: return "Inviato"
        case .cancelled: return "Annullato"
        case .failed: return "Non riuscito"
        }
    }
}

public enum EventSource: String, Codable, CaseIterable, Sendable {
    case app, widget, control, shortcut, manual

    public var label: String {
        switch self {
        case .app: return "App"
        case .widget: return "Widget"
        case .control: return "Centro di Controllo"
        case .shortcut: return "Siri e Comandi"
        case .manual: return "Correzione manuale"
        }
    }
}

/// One command sent (or attempted) to a house.
public struct AlarmEvent: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var houseID: UUID
    public var zoneID: UUID?
    /// Snapshot of the zone name, kept even if the zone is deleted later.
    public var zoneName: String?
    public var kind: CommandKind
    public var result: EventResult
    public var source: EventSource
    public var date: Date
    /// SMS text with the password masked.
    public var message: String

    public init(
        id: UUID = UUID(),
        houseID: UUID,
        zoneID: UUID? = nil,
        zoneName: String? = nil,
        kind: CommandKind,
        result: EventResult = .sent,
        source: EventSource = .app,
        date: Date = Date(),
        message: String = ""
    ) {
        self.id = id
        self.houseID = houseID
        self.zoneID = zoneID
        self.zoneName = zoneName
        self.kind = kind
        self.result = result
        self.source = source
        self.date = date
        self.message = message
    }

    /// True when the event changes the (assumed) state of the alarm.
    public var changesState: Bool {
        result == .sent && kind != .status
    }

    /// True for SMS actually handed to Messages (manual corrections excluded).
    public var isSentSMS: Bool {
        result == .sent && source != .manual
    }
}

// MARK: - Settings

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

public struct AppSettings: Codable, Equatable, Sendable {
    /// Ask for a confirmation before opening the SMS composer (in app).
    public var confirmBeforeSending: Bool
    /// Ask Face ID / passcode before disarming.
    public var requireAuthForDisarm: Bool
    public var appearance: Appearance
    /// House used by widgets and controls that don't pick one.
    public var defaultHouseID: UUID?

    public init(confirmBeforeSending: Bool = false, requireAuthForDisarm: Bool = false, appearance: Appearance = .system, defaultHouseID: UUID? = nil) {
        self.confirmBeforeSending = confirmBeforeSending
        self.requireAuthForDisarm = requireAuthForDisarm
        self.appearance = appearance
        self.defaultHouseID = defaultHouseID
    }

    private enum CodingKeys: String, CodingKey { case confirmBeforeSending, requireAuthForDisarm, appearance, defaultHouseID }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        confirmBeforeSending = try c.decodeIfPresent(Bool.self, forKey: .confirmBeforeSending) ?? false
        requireAuthForDisarm = try c.decodeIfPresent(Bool.self, forKey: .requireAuthForDisarm) ?? false
        appearance = (try? c.decodeIfPresent(Appearance.self, forKey: .appearance)) ?? .system
        defaultHouseID = try c.decodeIfPresent(UUID.self, forKey: .defaultHouseID)
    }
}

// MARK: - Root

/// Everything the app saves (except passwords). Shared with the widgets.
public struct AlarmData: Codable, Equatable, Sendable {
    public var version: Int
    public var houses: [House]
    public var events: [AlarmEvent]
    public var settings: AppSettings

    public init(houses: [House] = [], events: [AlarmEvent] = [], settings: AppSettings = AppSettings()) {
        self.version = 1
        self.houses = houses
        self.events = events
        self.settings = settings
    }

    private enum CodingKeys: String, CodingKey { case version, houses, events, settings }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        houses = try c.decodeIfPresent([House].self, forKey: .houses) ?? []
        events = try c.decodeIfPresent([AlarmEvent].self, forKey: .events) ?? []
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
    }
}

/// Backup file: the data plus (optionally) the passwords, keyed by house id.
public struct BackupFile: Codable, Equatable, Sendable {
    public var format: String
    public var exportedAt: Date
    public var data: AlarmData
    public var passwords: [String: String]

    public init(data: AlarmData, passwords: [UUID: String], exportedAt: Date = Date()) {
        self.format = "home-alarm-backup"
        self.exportedAt = exportedAt
        self.data = data
        self.passwords = Dictionary(uniqueKeysWithValues: passwords.map { ($0.key.uuidString, $0.value) })
    }

    public var passwordsByHouse: [UUID: String] {
        var out: [UUID: String] = [:]
        for (k, v) in passwords { if let id = UUID(uuidString: k) { out[id] = v } }
        return out
    }
}
