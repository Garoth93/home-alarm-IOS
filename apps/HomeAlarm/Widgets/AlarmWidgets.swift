import WidgetKit
import SwiftUI
import AppIntents
import AlarmCore

@main
struct AlarmWidgetsBundle: WidgetBundle {
    var body: some Widget {
        AlarmStatusWidget()
        QuickActionWidget()
        AlarmControl()
    }
}

// MARK: - Snapshot model

/// What a widget needs to draw one house, read from the shared JSON.
struct HouseSnapshot {
    struct ZoneItem: Identifiable {
        let id: UUID
        let name: String
        let icon: String
        let colorHex: String
    }

    let id: UUID?
    let name: String
    let icon: String
    let colorHex: String
    let zones: [ZoneItem]
    let state: HouseState
    let supportsStatus: Bool

    init(house: House, data: AlarmData) {
        id = house.id
        name = house.name
        icon = house.icon
        colorHex = house.colorHex
        zones = house.zones.map { ZoneItem(id: $0.id, name: $0.name, icon: $0.icon, colorHex: $0.colorHex) }
        state = data.state(for: house.id)
        supportsStatus = house.supportsStatus
    }

    init(id: UUID?, name: String, icon: String, colorHex: String, zones: [ZoneItem], state: HouseState, supportsStatus: Bool) {
        self.id = id
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.zones = zones
        self.state = state
        self.supportsStatus = supportsStatus
    }

    /// Used when the widget cannot read the app data (no App Group).
    static let generic = HouseSnapshot(id: nil, name: "Antifurto", icon: "house.fill", colorHex: Palette.defaultAccent,
                                       zones: [], state: .unknown, supportsStatus: false)

    static let preview = HouseSnapshot(
        id: nil, name: "Casa", icon: "house.fill", colorHex: "#3949ab",
        zones: [
            ZoneItem(id: UUID(), name: "Totale", icon: "lock.shield.fill", colorHex: "#3949ab"),
            ZoneItem(id: UUID(), name: "Notte", icon: "moon.stars.fill", colorHex: "#5e35b1"),
            ZoneItem(id: UUID(), name: "Perimetrale", icon: "door.left.hand.closed", colorHex: "#00897b")
        ],
        state: HouseState(isArmed: true, zoneID: nil, zoneName: "Notte", since: Date().addingTimeInterval(-7200), lastEvent: nil),
        supportsStatus: false)

    func link(_ kind: AlarmActionRef.Kind) -> URL {
        DeepLink.run(AlarmActionRef(houseID: id, kind: kind), source: .widget).url
    }

    var openLink: URL { DeepLink.open(houseID: id).url }
}

// MARK: - Status widget

struct StatusEntry: TimelineEntry {
    let date: Date
    let house: HouseSnapshot
    let configured: Bool
}

struct StatusProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> StatusEntry {
        StatusEntry(date: Date(), house: .preview, configured: true)
    }

    func snapshot(for configuration: SelectHouseIntent, in context: Context) async -> StatusEntry {
        let e = entry(for: configuration)
        return context.isPreview && !e.configured ? placeholder(in: context) : e
    }

    func timeline(for configuration: SelectHouseIntent, in context: Context) async -> Timeline<StatusEntry> {
        Timeline(entries: [entry(for: configuration)], policy: .after(Date().addingTimeInterval(3600)))
    }

    private func entry(for configuration: SelectHouseIntent) -> StatusEntry {
        let data = SharedStore.load()
        let house = configuration.house.flatMap { e in data.houses.first { $0.id == e.id } } ?? data.defaultHouse
        guard let house else { return StatusEntry(date: Date(), house: .generic, configured: false) }
        return StatusEntry(date: Date(), house: HouseSnapshot(house: house, data: data), configured: true)
    }
}

struct AlarmStatusWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "AlarmStatusWidget", intent: SelectHouseIntent.self, provider: StatusProvider()) { entry in
            StatusWidgetView(entry: entry)
        }
        .configurationDisplayName("Antifurto")
        .description("Stato della casa, disinserimento e zone a portata di tocco.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

// MARK: - Quick action widget

struct QuickActionEntry: TimelineEntry {
    let date: Date
    let title: String
    let subtitle: String
    let symbol: String
    let colorHex: String
    let kind: CommandKind
    let url: URL
    let armed: Bool
}

struct QuickActionProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> QuickActionEntry {
        QuickActionEntry(date: Date(), title: "Disinserisci", subtitle: "Casa", symbol: "shield.slash.fill",
                         colorHex: "#e53935", kind: .disarm, url: DeepLink.run(.disarm(nil), source: .widget).url, armed: false)
    }

    func snapshot(for configuration: SelectActionIntent, in context: Context) async -> QuickActionEntry {
        entry(for: configuration)
    }

    func timeline(for configuration: SelectActionIntent, in context: Context) async -> Timeline<QuickActionEntry> {
        Timeline(entries: [entry(for: configuration)], policy: .after(Date().addingTimeInterval(3600)))
    }

    private func entry(for configuration: SelectActionIntent) -> QuickActionEntry {
        let data = SharedStore.load()
        let ref = configuration.action?.ref ?? AlarmActionRef.disarm(data.defaultHouse?.id)
        let url = DeepLink.run(ref, source: .widget).url
        guard let d = data.describe(ref), let house = data.house(ref.houseID) else {
            return QuickActionEntry(date: Date(), title: configuration.action?.title ?? "Disinserisci",
                                    subtitle: configuration.action?.subtitle ?? "Antifurto",
                                    symbol: configuration.action?.symbol ?? "shield.slash.fill",
                                    colorHex: "#e53935", kind: ref.commandKind, url: url, armed: false)
        }
        let state = data.state(for: house.id)
        let armed: Bool = {
            if case .arm(let z) = ref.kind { return state.isArmed && state.zoneID == z }
            if case .disarm = ref.kind { return !state.isArmed && state.since != nil }
            return false
        }()
        return QuickActionEntry(date: Date(), title: d.title, subtitle: d.subtitle, symbol: d.symbol,
                                colorHex: ref.commandKind == .disarm ? "#e53935" : d.colorHex,
                                kind: ref.commandKind, url: url, armed: armed)
    }
}

struct QuickActionWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "QuickActionWidget", intent: SelectActionIntent.self, provider: QuickActionProvider()) { entry in
            QuickActionView(entry: entry)
        }
        .configurationDisplayName("Comando rapido")
        .description("Un pulsante per un comando: disinserisci o inserisci una zona.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
        .contentMarginsDisabled()
    }
}

// MARK: - Control Center

struct AlarmControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "com.garoth93.homealarm.control", intent: SelectControlActionIntent.self) { configuration in
            let action = configuration.action ?? AlarmActionEntity.defaultDisarm
            ControlWidgetButton(action: ControlAlarmActionIntent(action: action)) {
                Label(action.title, systemImage: action.symbol)
            }
        }
        .displayName("Antifurto")
        .description("Disinserisci o inserisci una zona dal Centro di Controllo o dal tasto Azione.")
    }
}
