import SwiftUI
import AlarmCore

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    @State private var editing: HouseEditorTarget?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let house = model.selectedHouse {
                    if model.houses.count > 1 { houseSwitcher }
                    StatusCard(house: house, state: model.state(for: house))
                    PillButton(title: "Disinserisci", icon: "shield.slash.fill", tones: m3.danger) {
                        model.request(.disarm(house.id), source: .app)
                    }
                    zonesSection(house)
                    if house.supportsStatus {
                        PillButton(title: "Chiedi stato alla centralina", icon: "questionmark.bubble.fill", tones: m3.tertiaryTones, filled: false, height: 52) {
                            model.request(.status(house.id), source: .app)
                        }
                    }
                    recentSection(house)
                } else {
                    WelcomeView { editing = .new(House.example()) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(m3.surface)
        .navigationTitle(model.selectedHouse?.name ?? "Antifurto")
        .toolbar {
            if let house = model.selectedHouse {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editing = .edit(house)
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("Modifica casa")
                }
            }
        }
        .sheet(item: $editing) { target in
            HouseEditorView(target: target)
        }
    }

    // MARK: Sections

    private var houseSwitcher: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.houses) { h in
                    Chip(title: h.name, icon: h.icon, selected: h.id == model.selectedHouse?.id) {
                        withAnimation(.snappy) { model.selectedHouseID = h.id }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func zonesSection(_ house: House) -> some View {
        SectionTitle("Inserisci", trailing: house.zones.isEmpty ? nil : "\(house.zones.count) zone")
        if house.zones.isEmpty {
            M3Card {
                HStack(spacing: 14) {
                    IconBadge(icon: "plus", tones: m3.primaryTones)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nessuna zona").font(.m3TitleSmall).foregroundStyle(m3.onSurface)
                        Text("Aggiungi le combinazioni, ad esempio \"attiva 1-2-3\".")
                            .font(.m3BodySmall).foregroundStyle(m3.onSurfaceVariant)
                    }
                    Spacer()
                }
            }
            .onTapGesture { editing = .edit(house) }
        } else {
            let state = model.state(for: house)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(house.zones) { zone in
                    ZoneTile(zone: zone, active: state.isArmed && state.zoneID == zone.id) {
                        model.request(.arm(house.id, zone: zone.id), source: .app)
                    }
                    .contextMenu {
                        Button {
                            model.markState(houseID: house.id, armedZone: zone)
                        } label: {
                            Label("Segna come inserita (senza SMS)", systemImage: "checkmark.shield")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func recentSection(_ house: House) -> some View {
        let recent = model.data.eventsNewestFirst.filter { $0.houseID == house.id }.prefix(4)
        if !recent.isEmpty {
            SectionTitle("Ultimi comandi")
            M3Card(padding: 4) {
                VStack(spacing: 0) {
                    ForEach(Array(recent.enumerated()), id: \.element.id) { index, event in
                        EventRow(event: event, house: house, showHouse: false)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                        if index < recent.count - 1 {
                            Divider().overlay(m3.outlineVariant).padding(.leading, 66)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Status card

struct StatusCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    let house: House
    let state: HouseState

    var body: some View {
        let tones = state.isArmed ? m3.tones(house.zone(state.zoneID)?.colorHex ?? house.colorHex) : m3.neutral
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                IconBadge(icon: state.isArmed ? "lock.shield.fill" : "shield.slash",
                          tones: tones, size: 72, cookie: true, filled: state.isArmed)
                    .symbolEffect(.bounce, value: state.since)
                Spacer()
                Menu {
                    Button {
                        model.markState(houseID: house.id, armedZone: nil)
                    } label: {
                        Label("Segna come disinserito (senza SMS)", systemImage: "shield.slash")
                    }
                    ForEach(house.zones) { z in
                        Button {
                            model.markState(houseID: house.id, armedZone: z)
                        } label: {
                            Label("Segna \(z.name) inserita", systemImage: z.icon)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(tones.onContainer)
                        .frame(width: 40, height: 40)
                        .background(tones.onContainer.opacity(0.08), in: Circle())
                }
                .accessibilityLabel("Correggi stato")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(state.title)
                    .font(.m3DisplaySmall)
                    .foregroundStyle(tones.onContainer)
                    .contentTransition(.numericText())
                if let zone = state.subtitle {
                    Text(zone)
                        .font(.m3TitleLarge)
                        .foregroundStyle(tones.onContainer.opacity(0.85))
                }
                if let since = state.since {
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                        Text("da \(Text(since, style: .relative))")
                        Text("· \(since.shortLabel)")
                    }
                    .font(.m3BodyMedium)
                    .foregroundStyle(tones.onContainer.opacity(0.75))
                } else {
                    Text("Tocca una zona per inserire l'antifurto.")
                        .font(.m3BodyMedium)
                        .foregroundStyle(tones.onContainer.opacity(0.75))
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                Text("Stato dedotto dall'ultimo SMS inviato")
            }
            .font(.m3LabelSmall)
            .foregroundStyle(tones.onContainer.opacity(0.6))
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tones.container, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: state)
    }
}

// MARK: - Zone tile

struct ZoneTile: View {
    @Environment(\.m3) private var m3
    let zone: Zone
    let active: Bool
    let action: () -> Void

    var body: some View {
        let tones = m3.tones(zone.colorHex)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    IconBadge(icon: zone.icon, tones: tones, size: 46, filled: active)
                    Spacer()
                    if active {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(tones.accent)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(zone.name)
                        .font(.m3TitleMedium)
                        .foregroundStyle(m3.onSurface)
                        .lineLimit(1)
                    Text(zone.command)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(m3.onSurfaceVariant)
                        .lineLimit(1)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(active ? tones.container : m3.surfaceContainerLow, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(active ? tones.accent : Color.clear, lineWidth: 2)
            )
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Inserisci \(zone.name)")
    }
}

// MARK: - Welcome

private struct WelcomeView: View {
    @Environment(\.m3) private var m3
    let onCreate: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            EmptyStateView(icon: "shield.lefthalf.filled", title: "Benvenuto",
                           message: "Gestisci l'antifurto di casa con un tocco: l'app prepara l'SMS per la centralina e tu premi Invia.")
            M3Card {
                VStack(alignment: .leading, spacing: 14) {
                    step(1, "Crea la casa", "Numero di telefono della centralina e password: si inseriscono una volta sola.")
                    step(2, "Aggiungi le zone", "Ogni zona ha la sua combinazione, ad esempio \"attiva 1-2-3\".")
                    step(3, "Invia con un tocco", "L'app compone \"attiva 1-2-3 1966\". Per disinserire basta un pulsante.")
                }
            }
            PillButton(title: "Crea la tua casa", icon: "plus", tones: m3.primaryTones, action: onCreate)
        }
        .padding(.top, 12)
    }

    private func step(_ n: Int, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(n)")
                .font(.m3TitleMedium)
                .foregroundStyle(m3.onPrimaryContainer)
                .frame(width: 34, height: 34)
                .background(m3.primaryContainer, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.m3TitleSmall).foregroundStyle(m3.onSurface)
                Text(text).font(.m3BodySmall).foregroundStyle(m3.onSurfaceVariant)
            }
        }
    }
}
