import SwiftUI
import Charts
import UniformTypeIdentifiers
import InstaCore

struct OverviewView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    @Binding var tab: AppTab
    @State private var showImporter = false

    var body: some View {
        let an = model.analysis
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !model.hasData {
                    WelcomeView { showImporter = true }
                } else {
                    snapshotHeader
                    heroCard(an.stats)
                    reviewCard(an.stats)
                    if an.stats.hasCompare { changesCard(an) }
                    if model.snapshots.count >= 2 { trendCard }
                    quickLists(an)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(m3.surface)
        .navigationTitle(model.owner.isEmpty ? "instaStats" : "@\(model.owner)")
        .toolbar {
            if model.owners.count > 1 {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        ForEach(model.owners, id: \.self) { o in
                            Button {
                                model.loadOwner(o)
                            } label: {
                                if o == model.owner { Label("@\(o)", systemImage: "checkmark") } else { Text("@\(o)") }
                            }
                        }
                    } label: {
                        Image(systemName: "person.crop.circle")
                    }
                    .accessibilityLabel("Cambia account")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showImporter = true
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .accessibilityLabel("Importa export")
            }
        }
        .exportImporter(isPresented: $showImporter)
    }

    // MARK: Header

    private var snapshotHeader: some View {
        HStack(spacing: 8) {
            Menu {
                Picker("Istantanea", selection: Binding(
                    get: { model.currentID ?? UUID() },
                    set: { model.selectCurrent($0) }
                )) {
                    ForEach(model.snapshots.reversed()) { s in
                        Text("\(s.label) · \(InstaFormat.date(s.takenAt))").tag(s.id)
                    }
                }
            } label: {
                headerChip(icon: "calendar", text: model.current.map { InstaFormat.date($0.takenAt) } ?? "–", strong: true)
            }
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(m3.onSurfaceVariant)
            Menu {
                Picker("Confronta con", selection: Binding(
                    get: { model.compareID },
                    set: { model.selectCompare($0) }
                )) {
                    Text("Nessun confronto").tag(UUID?.none)
                    ForEach(model.snapshots.reversed().filter { $0.id != model.currentID }) { s in
                        Text("\(s.label) · \(InstaFormat.date(s.takenAt))").tag(UUID?.some(s.id))
                    }
                }
            } label: {
                headerChip(icon: "clock.arrow.circlepath", text: model.compare.map { InstaFormat.date($0.takenAt) } ?? "nessun confronto", strong: false)
            }
            Spacer(minLength: 0)
        }
    }

    private func headerChip(icon: String, text: String, strong: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold))
            Text(text).font(.m3LabelLarge).lineLimit(1)
            Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(strong ? m3.onSecondaryContainer : m3.onSurfaceVariant)
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(strong ? m3.secondaryContainer : Color.clear, in: Capsule())
        .overlay(Capsule().strokeBorder(strong ? Color.clear : m3.outlineVariant, lineWidth: 1))
    }

    // MARK: Cards

    private func heroCard(_ s: OverviewStats) -> some View {
        M3Card(color: m3.primaryContainer, padding: 20, corner: 32) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    bigNumber("Follower", s.followers, delta: s.hasCompare ? s.followersDelta : nil)
                    Spacer()
                    bigNumber("Seguiti", s.following, delta: s.hasCompare ? s.followingDelta : nil)
                }
                HStack(spacing: 10) {
                    smallStat("Reciproci", "\(s.mutualPercent)%", "dei seguiti ricambia")
                    smallStat("Rapporto", String(format: "%.2f", s.ratio).replacingOccurrences(of: ".", with: ","), "follower per seguito")
                }
                if s.hasCompare && s.days > 0 {
                    Text("Rispetto a \(s.days) giorni prima")
                        .font(.m3LabelMedium)
                        .foregroundStyle(m3.onPrimaryContainer.opacity(0.7))
                }
            }
        }
    }

    private func bigNumber(_ title: String, _ value: Int, delta: Int?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.m3LabelLarge)
                .foregroundStyle(m3.onPrimaryContainer.opacity(0.8))
            Text(InstaFormat.number(value))
                .font(.m3DisplaySmall)
                .foregroundStyle(m3.onPrimaryContainer)
                .monospacedDigit()
                .contentTransition(.numericText())
            if let delta {
                let tones = delta > 0 ? m3.keep : delta < 0 ? m3.reject : m3.neutral
                Text(InstaFormat.signed(delta))
                    .font(.m3LabelMedium)
                    .monospacedDigit()
                    .foregroundStyle(tones.onContainer)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(tones.container, in: Capsule())
            }
        }
    }

    private func smallStat(_ title: String, _ value: String, _ hint: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.m3TitleLarge)
                .foregroundStyle(m3.onPrimaryContainer)
                .monospacedDigit()
            Text(title)
                .font(.m3LabelMedium)
                .foregroundStyle(m3.onPrimaryContainer.opacity(0.8))
            Text(hint)
                .font(.m3LabelSmall)
                .foregroundStyle(m3.onPrimaryContainer.opacity(0.6))
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(m3.onPrimaryContainer.opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func reviewCard(_ s: OverviewStats) -> some View {
        Button {
            tab = .review
        } label: {
            M3Card {
                HStack(spacing: 14) {
                    IconBadge(icon: "person.fill.xmark", tones: m3.reject, size: 52, cookie: true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(InstaFormat.number(s.notBack)) non ricambiano")
                            .font(.m3TitleMedium)
                            .foregroundStyle(m3.onSurface)
                        Text(s.toUnfollow > 0
                             ? "\(s.toUnfollow) da smettere di seguire · \(s.kept) tenuti"
                             : "Rivedili uno alla volta: tieni o smetti di seguire")
                            .font(.m3BodySmall)
                            .foregroundStyle(m3.onSurfaceVariant)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(m3.outline)
                }
            }
        }
        .buttonStyle(PressableStyle())
    }

    private func changesCard(_ an: Analysis) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Cambiamenti", trailing: an.stats.days > 0 ? "in \(an.stats.days) giorni" : nil)
            HStack(spacing: 12) {
                changeTile(.lostFollowers, rows: an.preview(.lostFollowers), count: an.stats.lostFollowers, tones: m3.reject)
                changeTile(.newFollowers, rows: an.preview(.newFollowers), count: an.stats.newFollowers, tones: m3.keep)
            }
            HStack(spacing: 12) {
                changeTile(.newFollowing, rows: an.preview(.newFollowing), count: an.stats.newFollowing, tones: m3.primaryTones)
                changeTile(.dropped, rows: an.preview(.dropped), count: an.stats.dropped, tones: m3.neutral)
            }
        }
    }

    private func changeTile(_ kind: ListKind, rows: [AccountRow], count: Int, tones: Tones) -> some View {
        NavigationLink(value: Route.list(kind)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(InstaFormat.number(count))
                        .font(.m3HeadlineSmall)
                        .foregroundStyle(tones.onContainer)
                        .monospacedDigit()
                    Spacer()
                    Image(systemName: kind.icon)
                        .foregroundStyle(tones.onContainer.opacity(0.8))
                }
                Text(kind.title)
                    .font(.m3LabelLarge)
                    .foregroundStyle(tones.onContainer.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if rows.isEmpty {
                    Text("nessuno").font(.m3LabelSmall).foregroundStyle(tones.onContainer.opacity(0.6)).frame(height: 28)
                } else {
                    AvatarStack(rows: rows, size: 28, max: 5)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tones.container, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }

    private var trendCard: some View {
        let snaps = model.snapshots
        return M3Card(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Andamento")
                    .font(.m3TitleMedium)
                    .foregroundStyle(m3.onSurface)
                Chart {
                    ForEach(snaps) { s in
                        LineMark(x: .value("Data", s.takenAt), y: .value("Numero", s.followers))
                            .foregroundStyle(by: .value("Serie", "Follower"))
                            .interpolationMethod(.monotone)
                        PointMark(x: .value("Data", s.takenAt), y: .value("Numero", s.followers))
                            .foregroundStyle(by: .value("Serie", "Follower"))
                            .symbolSize(s.id == model.currentID ? 90 : 30)
                        LineMark(x: .value("Data", s.takenAt), y: .value("Numero", s.following))
                            .foregroundStyle(by: .value("Serie", "Seguiti"))
                            .interpolationMethod(.monotone)
                        PointMark(x: .value("Data", s.takenAt), y: .value("Numero", s.following))
                            .foregroundStyle(by: .value("Serie", "Seguiti"))
                            .symbolSize(s.id == model.currentID ? 90 : 30)
                    }
                }
                .chartForegroundStyleScale(["Follower": m3.primary, "Seguiti": m3.tertiary])
                .chartLegend(position: .bottom, alignment: .leading)
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine().foregroundStyle(m3.outlineVariant)
                        AxisValueLabel().foregroundStyle(m3.onSurfaceVariant)
                    }
                }
                .frame(height: 190)
            }
        }
    }

    private func quickLists(_ an: Analysis) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Liste")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach([ListKind.fans, .mutual, .toUnfollow, .kept, .pending, .closeFriends], id: \.self) { k in
                    NavigationLink(value: Route.list(k)) {
                        HStack(spacing: 12) {
                            IconBadge(icon: k.icon, tones: tones(for: k), size: 40)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(InstaFormat.number(an.count(k)))
                                    .font(.m3TitleMedium)
                                    .foregroundStyle(m3.onSurface)
                                    .monospacedDigit()
                                Text(k.title)
                                    .font(.m3LabelMedium)
                                    .foregroundStyle(m3.onSurfaceVariant)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .background(m3.surfaceContainerLow, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
    }

    private func tones(for k: ListKind) -> Tones {
        switch k {
        case .toUnfollow, .notBack, .lostFollowers: return m3.reject
        case .kept, .newFollowers, .mutual: return m3.keep
        case .fans, .closeFriends: return m3.tertiaryTones
        default: return m3.primaryTones
        }
    }
}

// MARK: - Welcome

struct WelcomeView: View {
    @Environment(\.m3) private var m3
    @Environment(\.openURL) private var openURL
    let onImport: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            EmptyStateView(icon: "person.2.fill", title: "Chi ti segue davvero?",
                           message: "Importa l'export ufficiale di Instagram: vedi chi non ricambia, chi ti ha smesso di seguire e chi è arrivato. Nessuna password, niente esce dal telefono.")
            M3Card {
                VStack(alignment: .leading, spacing: 14) {
                    step(1, "Richiedi l'export", "Instagram › Impostazioni › Centro gestione account › Le tue informazioni e autorizzazioni › Scarica le tue informazioni.")
                    step(2, "Scegli solo \"Follower e persone seguite\"", "Formato **JSON**, intervallo \"Sempre\". Instagram ti avvisa quando è pronto.")
                    step(3, "Importa lo ZIP", "Scaricalo nell'app File e importalo qui, oppure condividilo con instaStats.")
                    Button {
                        if let url = URL(string: "https://accountscenter.instagram.com/info_and_permissions/dyi/") { openURL(url) }
                    } label: {
                        Label("Apri Centro gestione account", systemImage: "arrow.up.right.square")
                            .font(.m3LabelLarge)
                    }
                    .padding(.leading, 48)
                }
            }
            PillButton(title: "Importa export", icon: "square.and.arrow.down.fill", tones: m3.primaryTones, action: onImport)
        }
        .padding(.top, 8)
    }

    private func step(_ n: Int, _ title: String, _ text: LocalizedStringKey) -> some View {
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

// MARK: - Importer

extension View {
    /// File picker for Instagram exports (ZIP, folder or JSON), multiple at once.
    func exportImporter(isPresented: Binding<Bool>) -> some View {
        modifier(ExportImporter(isPresented: isPresented))
    }
}

private struct ExportImporter: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.fileImporter(isPresented: $isPresented, allowedContentTypes: [.zip, .folder, .json], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { model.importFiles(urls) }
        }
    }
}
