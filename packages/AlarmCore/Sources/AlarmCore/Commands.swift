import Foundation

// MARK: - Action reference

/// A command the user can trigger from the app, a widget, a control or Siri.
/// `houseID == nil` means "the default house".
public struct AlarmActionRef: Hashable, Codable, Sendable {
    public enum Kind: Hashable, Codable, Sendable {
        case arm(zoneID: UUID)
        case disarm
        case status
    }

    public var houseID: UUID?
    public var kind: Kind

    public init(houseID: UUID?, kind: Kind) {
        self.houseID = houseID
        self.kind = kind
    }

    public static func disarm(_ houseID: UUID?) -> AlarmActionRef { AlarmActionRef(houseID: houseID, kind: .disarm) }
    public static func status(_ houseID: UUID?) -> AlarmActionRef { AlarmActionRef(houseID: houseID, kind: .status) }
    public static func arm(_ houseID: UUID?, zone: UUID) -> AlarmActionRef { AlarmActionRef(houseID: houseID, kind: .arm(zoneID: zone)) }

    /// Stable string id: "<house|default>|disarm", "…|status", "…|zone:<uuid>".
    public var id: String {
        let h = houseID?.uuidString ?? "default"
        switch kind {
        case .disarm: return "\(h)|disarm"
        case .status: return "\(h)|status"
        case .arm(let z): return "\(h)|zone:\(z.uuidString)"
        }
    }

    public init?(id: String) {
        let parts = id.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        let house: UUID?
        if parts[0] == "default" {
            house = nil
        } else if let h = UUID(uuidString: parts[0]) {
            house = h
        } else {
            return nil
        }
        switch parts[1] {
        case "disarm": self.init(houseID: house, kind: .disarm)
        case "status": self.init(houseID: house, kind: .status)
        default:
            guard parts[1].hasPrefix("zone:"), let z = UUID(uuidString: String(parts[1].dropFirst(5))) else { return nil }
            self.init(houseID: house, kind: .arm(zoneID: z))
        }
    }

    public var commandKind: CommandKind {
        switch kind {
        case .arm: return .arm
        case .disarm: return .disarm
        case .status: return .status
        }
    }

    public var zoneID: UUID? {
        if case .arm(let z) = kind { return z }
        return nil
    }
}

// MARK: - Resolved command

public enum CommandError: Error, Equatable, Sendable {
    case noHouses
    case houseNotFound
    case zoneNotFound
    case missingPhoneNumber(house: String)
    case missingPassword(house: String)
    case missingCommand

    public var message: String {
        switch self {
        case .noHouses: return "Configura prima una casa nelle Impostazioni."
        case .houseNotFound: return "La casa di questo comando non esiste più."
        case .zoneNotFound: return "La zona di questo comando non esiste più. Riconfigura il widget."
        case .missingPhoneNumber(let h): return "Imposta il numero di telefono della centralina di \(h)."
        case .missingPassword(let h): return "Imposta la password della centralina di \(h)."
        case .missingCommand: return "Il comando è vuoto: controlla la configurazione."
        }
    }
}

/// A command ready to be sent as SMS.
public struct ResolvedCommand: Equatable, Identifiable, Sendable {
    public let id = UUID()
    public let house: House
    public let zone: Zone?
    public let kind: CommandKind
    public let recipient: String
    public let body: String
    public let maskedBody: String

    public var title: String {
        switch kind {
        case .arm: return "Inserisci \(zone?.name ?? "zona")"
        case .disarm: return "Disinserisci"
        case .status: return "Richiedi stato"
        }
    }

    public func event(result: EventResult, source: EventSource, date: Date = Date()) -> AlarmEvent {
        AlarmEvent(houseID: house.id, zoneID: zone?.id, zoneName: zone?.name, kind: kind,
                   result: result, source: source, date: date, message: maskedBody)
    }

    public static func == (a: ResolvedCommand, b: ResolvedCommand) -> Bool { a.id == b.id }
}

// MARK: - Message builder

public enum MessageBuilder {
    public static let defaultTemplate = "{comando} {password}"
    public static let commandToken = "{comando}"
    public static let passwordToken = "{password}"
    public static let mask = "••••"

    /// Builds the SMS text. A template without `{comando}` falls back to the default.
    public static func message(command: String, password: String, template: String = defaultTemplate) -> String {
        var t = template.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.contains(commandToken) { t = defaultTemplate }
        let text = t
            .replacingOccurrences(of: commandToken, with: command.trimmingCharacters(in: .whitespacesAndNewlines))
            .replacingOccurrences(of: passwordToken, with: password.trimmingCharacters(in: .whitespacesAndNewlines))
        return collapseSpaces(text)
    }

    public static func masked(command: String, password: String, template: String = defaultTemplate) -> String {
        message(command: command, password: password.isEmpty ? "" : mask, template: template)
    }

    static func collapseSpaces(_ s: String) -> String {
        s.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func normalize(phone: String) -> String {
        let allowed = Set("+0123456789")
        return String(phone.filter { allowed.contains($0) })
    }

    /// `sms:` URL fallback (used when the in-app composer is unavailable).
    public static func smsURL(number: String, body: String) -> URL? {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encoded = body.addingPercentEncoding(withAllowedCharacters: allowed) ?? body
        return URL(string: "sms:\(normalize(phone: number))&body=\(encoded)")
    }

    /// Raw command (without password) for an action in a house.
    public static func command(for kind: AlarmActionRef.Kind, in house: House) -> String? {
        switch kind {
        case .disarm: return house.disarmCommand
        case .status: return house.supportsStatus ? house.statusCommand : nil
        case .arm(let z): return house.zone(z)?.command
        }
    }
}

// MARK: - Resolution

extension AlarmData {
    /// The house used when nothing else is specified.
    public var defaultHouse: House? {
        if let id = settings.defaultHouseID, let h = houses.first(where: { $0.id == id }) { return h }
        return houses.first
    }

    public func house(_ id: UUID?) -> House? {
        guard let id else { return defaultHouse }
        return houses.first { $0.id == id }
    }

    /// Turns an action into an SMS ready to send, validating the configuration.
    public func resolve(_ ref: AlarmActionRef, password: String?) -> Result<ResolvedCommand, CommandError> {
        guard !houses.isEmpty else { return .failure(.noHouses) }
        guard let house = house(ref.houseID) else { return .failure(.houseNotFound) }
        var zone: Zone?
        if case .arm(let z) = ref.kind {
            guard let found = house.zone(z) else { return .failure(.zoneNotFound) }
            zone = found
        }
        guard let command = MessageBuilder.command(for: ref.kind, in: house),
              !command.trimmingCharacters(in: .whitespaces).isEmpty else { return .failure(.missingCommand) }
        let number = house.normalizedPhoneNumber
        guard !number.isEmpty else { return .failure(.missingPhoneNumber(house: house.name)) }
        let pass = (password ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let template = house.messageTemplate
        if template.contains(MessageBuilder.passwordToken) || !template.contains(MessageBuilder.commandToken) {
            guard !pass.isEmpty else { return .failure(.missingPassword(house: house.name)) }
        }
        return .success(ResolvedCommand(
            house: house,
            zone: zone,
            kind: ref.commandKind,
            recipient: number,
            body: MessageBuilder.message(command: command, password: pass, template: template),
            maskedBody: MessageBuilder.masked(command: command, password: pass, template: template)
        ))
    }

    /// All actions available for a house (disarm first, then zones, then status).
    public func actions(for house: House) -> [AlarmActionRef] {
        var out: [AlarmActionRef] = [.disarm(house.id)]
        out += house.zones.map { .arm(house.id, zone: $0.id) }
        if house.supportsStatus { out.append(.status(house.id)) }
        return out
    }

    /// Short label and symbol for an action, for widgets and Siri.
    public func describe(_ ref: AlarmActionRef) -> (title: String, subtitle: String, symbol: String, colorHex: String)? {
        guard let house = house(ref.houseID) else { return nil }
        switch ref.kind {
        case .disarm:
            return ("Disinserisci", house.name, "shield.slash.fill", house.colorHex)
        case .status:
            return ("Stato", house.name, "questionmark.bubble.fill", house.colorHex)
        case .arm(let z):
            guard let zone = house.zone(z) else { return nil }
            return (zone.name, house.name, zone.icon, zone.colorHex)
        }
    }
}

// MARK: - Deep links

/// URLs used by widgets (`homealarm://…`) to open the app on an action.
public enum DeepLink: Equatable, Sendable {
    case run(AlarmActionRef, source: EventSource)
    case open(houseID: UUID?)

    public static let scheme = "homealarm"

    public var url: URL {
        var c = URLComponents()
        c.scheme = Self.scheme
        switch self {
        case .run(let ref, let source):
            c.host = "run"
            c.queryItems = [URLQueryItem(name: "action", value: ref.id), URLQueryItem(name: "source", value: source.rawValue)]
        case .open(let house):
            c.host = "open"
            if let house { c.queryItems = [URLQueryItem(name: "house", value: house.uuidString)] }
        }
        return c.url ?? URL(string: "\(Self.scheme)://open")!
    }

    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let items = c.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        switch c.host?.lowercased() {
        case "run":
            guard let id = value("action"), let ref = AlarmActionRef(id: id) else { return nil }
            let source = value("source").flatMap(EventSource.init(rawValue:)) ?? .widget
            self = .run(ref, source: source)
        case "open":
            self = .open(houseID: value("house").flatMap(UUID.init(uuidString:)))
        default:
            return nil
        }
    }
}
