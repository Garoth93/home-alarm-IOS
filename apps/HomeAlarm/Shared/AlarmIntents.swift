import AppIntents
import AlarmCore
import Foundation

// Shared by the app and the widget extension (compiled in both targets).

// MARK: - House entity (widget configuration)

struct HouseEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Casa" }
    static var defaultQuery = HouseEntityQuery()

    var id: UUID
    var name: String
    var icon: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: icon))
    }

    init(_ house: House) {
        id = house.id
        name = house.name
        icon = house.icon
    }
}

struct HouseEntityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [HouseEntity] {
        let data = SharedStore.load()
        return identifiers.compactMap { id in data.houses.first { $0.id == id }.map(HouseEntity.init) }
    }

    func suggestedEntities() async throws -> [HouseEntity] {
        SharedStore.load().houses.map(HouseEntity.init)
    }

    func defaultResult() async -> HouseEntity? {
        SharedStore.load().defaultHouse.map(HouseEntity.init)
    }
}

// MARK: - Action entity (quick action widget, controls, Siri)

struct AlarmActionEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Comando antifurto" }
    static var defaultQuery = AlarmActionQuery()

    /// `AlarmActionRef.id`
    var id: String
    var title: String
    var subtitle: String
    var symbol: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(subtitle)", image: .init(systemName: symbol))
    }

    var ref: AlarmActionRef? { AlarmActionRef(id: id) }

    init(id: String, title: String, subtitle: String, symbol: String) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
    }

    init?(_ ref: AlarmActionRef, in data: AlarmData) {
        guard let d = data.describe(ref) else { return nil }
        self.init(id: ref.id, title: d.title, subtitle: d.subtitle, symbol: d.symbol)
    }

    /// Disarm of the default house: works even before any configuration.
    static let defaultDisarm = AlarmActionEntity(
        id: AlarmActionRef.disarm(nil).id, title: "Disinserisci", subtitle: "Casa predefinita", symbol: "shield.slash.fill")
}

struct AlarmActionQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [AlarmActionEntity] {
        let data = SharedStore.load()
        return identifiers.compactMap { (id: String) -> AlarmActionEntity? in
            guard let ref = AlarmActionRef(id: id) else { return nil }
            if ref.houseID == nil, ref.kind == .disarm { return AlarmActionEntity.defaultDisarm }
            return AlarmActionEntity(ref, in: data)
        }
    }

    func suggestedEntities() async throws -> [AlarmActionEntity] {
        let data = SharedStore.load()
        let all = data.houses.flatMap { h in data.actions(for: h).compactMap { AlarmActionEntity($0, in: data) } }
        return all.isEmpty ? [.defaultDisarm] : all
    }

    func defaultResult() async -> AlarmActionEntity? {
        let data = SharedStore.load()
        if let h = data.defaultHouse { return AlarmActionEntity(.disarm(h.id), in: data) }
        return .defaultDisarm
    }
}

// MARK: - Run action

/// Opens the app with the SMS of the chosen command ready to send.
/// iOS never lets an app send an SMS silently: the user taps "Invia".
@MainActor
private func runAlarmAction(_ action: AlarmActionEntity, source: EventSource) {
    guard let ref = action.ref else { return }
    let link = DeepLink.run(ref, source: source)
    #if WIDGET_EXTENSION
    SharedStore.setPending(link)
    #else
    AppModel.shared.handle(link)
    #endif
}

/// Siri / Shortcuts / Action button.
struct RunAlarmActionIntent: AppIntent {
    static var title: LocalizedStringResource = "Comando antifurto"
    static var description = IntentDescription("Apre Antifurto con l'SMS del comando pronto da inviare.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Comando")
    var action: AlarmActionEntity

    init() {}

    init(action: AlarmActionEntity) {
        self.action = action
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Invia \(\.$action)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        runAlarmAction(action, source: .shortcut)
        return .result()
    }
}

/// Same as `RunAlarmActionIntent`, used by the Control Center control.
struct ControlAlarmActionIntent: AppIntent {
    static var title: LocalizedStringResource = "Comando antifurto (controllo)"
    static var openAppWhenRun: Bool = true
    static var isDiscoverable: Bool = false

    @Parameter(title: "Comando")
    var action: AlarmActionEntity

    init() {}

    init(action: AlarmActionEntity) {
        self.action = action
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        runAlarmAction(action, source: .control)
        return .result()
    }
}

// MARK: - Widget / control configuration

struct SelectHouseIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Casa"
    static var description = IntentDescription("Scegli la casa da mostrare nel widget.")

    @Parameter(title: "Casa")
    var house: HouseEntity?
}

struct SelectActionIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Comando rapido"
    static var description = IntentDescription("Scegli il comando da inviare con un tocco.")

    @Parameter(title: "Comando")
    var action: AlarmActionEntity?
}

struct SelectControlActionIntent: ControlConfigurationIntent {
    static var title: LocalizedStringResource = "Comando antifurto"
    static var description = IntentDescription("Scegli il comando del controllo.")

    @Parameter(title: "Comando")
    var action: AlarmActionEntity?
}
