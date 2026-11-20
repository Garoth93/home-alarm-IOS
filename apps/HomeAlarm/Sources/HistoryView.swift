import SwiftUI
import AlarmCore

struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    @State private var houseFilter: UUID?
    @State private var kindFilter: CommandKind?
    @State private var showCancelled = true

    private var filtered: [AlarmEvent] {
        model.data.eventsNewestFirst.filter { e in
            (houseFilter == nil || e.houseID == houseFilter) &&
            (kindFilter == nil || e.kind == kindFilter) &&
            (showCancelled || e.result == .sent)
        }
    }

    private var groups: [(day: Date, events: [AlarmEvent])] {
        let cal = Calendar.current
        let dict = Dictionary(grouping: filtered) { cal.startOfDay(for: $0.date) }
        return dict.keys.sorted(by: >).map { (day: $0, events: dict[$0] ?? []) }
    }

    var body: some View {
        List {
            Section {
                filters
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            if filtered.isEmpty {
                EmptyStateView(icon: "clock.arrow.circlepath", title: "Nessun comando",
                               message: "Qui trovi tutti gli SMS inviati alla centralina, con data, zona ed esito.")
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            ForEach(groups, id: \.day) { group in
                Section {
                    ForEach(group.events) { event in
                        EventRow(event: event, house: model.house(event.houseID), showHouse: model.houses.count > 1)
                            .listRowBackground(m3.surfaceContainerLow)
                            .listRowSeparatorTint(m3.outlineVariant)
                    }
                    .onDelete { offsets in
                        let ids = Set(offsets.map { group.events[$0].id })
                        model.deleteEvents(ids)
                    }
                } header: {
                    Text(group.day.dayHeader)
                        .font(.m3LabelLarge)
                        .foregroundStyle(m3.onSurfaceVariant)
                        .textCase(nil)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(m3.surface)
        .navigationTitle("Storico")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle(isOn: $showCancelled) {
                        Label("Mostra annullati", systemImage: "xmark.circle")
                    }
                    if model.houses.count > 1 {
                        Picker("Casa", selection: $houseFilter) {
                            Text("Tutte le case").tag(UUID?.none)
                            ForEach(model.houses) { h in
                                Text(h.name).tag(UUID?.some(h.id))
                            }
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                }
                .accessibilityLabel("Filtri")
            }
        }
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Chip(title: "Tutti", selected: kindFilter == nil) { kindFilter = nil }
                Chip(title: "Inserimenti", icon: "lock.shield", selected: kindFilter == .arm) { kindFilter = .arm }
                Chip(title: "Disinserimenti", icon: "shield.slash", selected: kindFilter == .disarm) { kindFilter = .disarm }
                Chip(title: "Stato", icon: "questionmark.bubble", selected: kindFilter == .status) { kindFilter = .status }
            }
            .padding(.horizontal, 4)
        }
    }
}

/// One command in a list.
struct EventRow: View {
    @Environment(\.m3) private var m3
    let event: AlarmEvent
    let house: House?
    var showHouse: Bool

    private var title: String {
        switch event.kind {
        case .arm: return house?.zone(event.zoneID)?.name ?? event.zoneName ?? "Inserimento"
        case .disarm: return "Disinserito"
        case .status: return "Richiesta stato"
        }
    }

    private var icon: String {
        switch event.kind {
        case .arm: return house?.zone(event.zoneID)?.icon ?? "lock.shield.fill"
        case .disarm: return "shield.slash.fill"
        case .status: return "questionmark.bubble.fill"
        }
    }

    var body: some View {
        let tones: Tones = {
            if event.result != .sent { return m3.neutral }
            if event.kind == .arm, let hex = house?.zone(event.zoneID)?.colorHex { return m3.tones(hex) }
            return m3.tones(for: event.kind)
        }()
        HStack(spacing: 12) {
            IconBadge(icon: icon, tones: tones, size: 42)
                .opacity(event.result == .sent ? 1 : 0.6)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.m3TitleSmall)
                        .foregroundStyle(m3.onSurface)
                        .strikethrough(event.result == .cancelled, color: m3.onSurfaceVariant)
                    if event.result != .sent {
                        Text(event.result.label)
                            .font(.m3LabelSmall)
                            .foregroundStyle(event.result == .failed ? m3.onErrorContainer : m3.onSurfaceVariant)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(event.result == .failed ? m3.errorContainer : m3.surfaceContainerHighest, in: Capsule())
                    }
                }
                HStack(spacing: 4) {
                    if showHouse, let house {
                        Text(house.name)
                        Text("·")
                    }
                    Image(systemName: sourceIcon)
                    Text(event.source.label)
                }
                .font(.m3BodySmall)
                .foregroundStyle(m3.onSurfaceVariant)
                .lineLimit(1)
                if !event.message.isEmpty && event.source != .manual {
                    Text(event.message)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(m3.outline)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text(event.date.timeLabel)
                .font(.m3LabelLarge)
                .foregroundStyle(m3.onSurfaceVariant)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }

    private var sourceIcon: String {
        switch event.source {
        case .app: return "iphone"
        case .widget: return "square.grid.2x2"
        case .control: return "switch.2"
        case .shortcut: return "mic.fill"
        case .manual: return "hand.tap"
        }
    }
}
