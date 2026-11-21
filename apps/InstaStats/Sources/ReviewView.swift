import SwiftUI
import InstaCore

/// The desktop "P / X" keyboard review, as swipeable cards:
/// swipe left = keep, swipe right = to unfollow.
/// Second mode: walk through "Da smettere di seguire" opening each profile.
struct ReviewView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3

    enum Mode: String, CaseIterable { case review = "Rivedi", unfollow = "Smetti di seguire" }
    @State private var mode: Mode = .review

    var body: some View {
        VStack(spacing: 0) {
            Picker("Modalità", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { m in Text(m.rawValue).tag(m) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 8)

            if !model.hasData {
                Spacer()
                EmptyStateView(icon: "rectangle.stack.fill", title: "Nessun export", message: "Importa un export di Instagram dalla Panoramica.")
                Spacer()
            } else if mode == .review {
                ReviewDeck()
            } else {
                UnfollowSession()
            }
        }
        .background(m3.surface)
        .navigationTitle(mode == .review ? "Non ricambiano" : "Da smettere")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.canUndo {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.undo()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .accessibilityLabel("Annulla")
                }
            }
        }
    }
}

// MARK: - Review deck

private struct ReviewDeck: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    @State private var drag: CGSize = .zero
    @State private var lastDecision: MarkState = .none

    /// Accounts not following back and still without a mark.
    private var queue: [AccountRow] {
        _ = model.revision
        return model.analysis.rows(for: .notBack, sort: model.settings.sortMode).filter { $0.mark == .none }
    }

    var body: some View {
        let queue = queue
        let total = model.analysis.stats.notBackAll
        VStack(spacing: 16) {
            progress(done: total - queue.count, total: total)
            ZStack {
                if queue.isEmpty {
                    doneView
                } else {
                    if queue.count > 1 {
                        ReviewCard(row: queue[1])
                            .scaleEffect(0.94)
                            .offset(y: 14)
                            .opacity(0.7)
                            .allowsHitTesting(false)
                    }
                    ReviewCard(row: queue[0], stamp: stamp)
                        .offset(x: drag.width, y: drag.height * 0.2)
                        .rotationEffect(.degrees(Double(drag.width / 22)))
                        .gesture(
                            DragGesture()
                                .onChanged { drag = $0.translation }
                                .onEnded { v in
                                    let t = v.translation.width + v.predictedEndTranslation.width * 0.2
                                    if t < -110 { decide(queue[0], .keep) }
                                    else if t > 110 { decide(queue[0], .unfollow) }
                                    else { withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { drag = .zero } }
                                }
                        )
                        .id(queue[0].username)
                        .transition(.asymmetric(insertion: .scale(scale: 0.94).combined(with: .opacity),
                                                removal: .move(edge: lastDecision == .keep ? .leading : .trailing).combined(with: .opacity)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 16)

            if let first = queue.first {
                HStack(spacing: 14) {
                    roundButton("checkmark", tones: m3.keep, size: 64, label: "Tieni") { decide(first, .keep) }
                    roundButton("arrow.up.right", tones: m3.primaryTones, size: 52, label: "Apri") { model.open(first.username) }
                    roundButton("xmark", tones: m3.reject, size: 64, label: "Da smettere") { decide(first, .unfollow) }
                }
                Text("Scorri a sinistra per tenere, a destra per smettere di seguire")
                    .font(.m3LabelSmall)
                    .foregroundStyle(m3.outline)
            }
        }
        .padding(.vertical, 12)
        .sensoryFeedback(.selection, trigger: abs(drag.width) > 110)
    }

    private var stamp: MarkState? {
        if drag.width < -60 { return .keep }
        if drag.width > 60 { return .unfollow }
        return nil
    }

    private func decide(_ row: AccountRow, _ state: MarkState) {
        lastDecision = state
        withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
            model.setMark([row.username], state)
            drag = .zero
        }
    }

    private func progress(done: Int, total: Int) -> some View {
        VStack(spacing: 6) {
            ProgressView(value: Double(max(0, done)), total: Double(max(1, total)))
                .tint(m3.primary)
            HStack {
                Text("\(InstaFormat.number(max(0, done))) rivisti su \(InstaFormat.number(total))")
                Spacer()
                Text("\(model.analysis.stats.kept) tenuti · \(model.analysis.stats.toUnfollow) da smettere")
            }
            .font(.m3LabelMedium)
            .foregroundStyle(m3.onSurfaceVariant)
        }
        .padding(.horizontal, 16)
    }

    private var doneView: some View {
        VStack(spacing: 16) {
            EmptyStateView(icon: "checkmark.seal.fill", title: "Tutto rivisto",
                           message: model.analysis.stats.toUnfollow > 0
                           ? "Ora passa a \"Smetti di seguire\": apri ogni profilo e smetti di seguirlo su Instagram. Al prossimo import spariscono da soli."
                           : "Nessun account da rivedere. Importa un nuovo export più avanti per vedere cosa cambia.")
        }
    }

    private func roundButton(_ icon: String, tones: Tones, size: CGFloat, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.36, weight: .bold))
                .foregroundStyle(tones.onContainer)
                .frame(width: size, height: size)
                .background(tones.container, in: Circle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }
}

/// Big card of one account.
private struct ReviewCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    let row: AccountRow
    var stamp: MarkState?

    var body: some View {
        let history = model.data.history(owner: model.owner, username: row.username, currentID: model.currentID)
        let wasFollower = history.contains { $0.follower }
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            Avatar(row: row, size: 120)
            VStack(spacing: 4) {
                Text("@\(row.username)")
                    .font(.m3HeadlineSmall)
                    .foregroundStyle(m3.onSurface)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if !row.fullName.isEmpty {
                    Text(row.fullName)
                        .font(.m3BodyLarge)
                        .foregroundStyle(m3.onSurfaceVariant)
                }
            }
            VStack(spacing: 6) {
                let sub = row.subtitle(for: .notBack)
                if !sub.isEmpty { chip(sub, icon: "calendar") }
                if wasFollower { chip("In passato ti seguiva", icon: "clock.arrow.circlepath") }
                if row.has(.closeFriend) { chip("Nei tuoi amici stretti", icon: "star.fill") }
                if !row.note.isEmpty { chip(row.note, icon: "note.text") }
            }
            Spacer(minLength: 0)
            Button {
                model.open(row.username)
            } label: {
                Label(model.isOpened(row.username) ? "Profilo aperto" : "Apri profilo su Instagram", systemImage: "arrow.up.right.square")
                    .font(.m3LabelLarge)
            }
            .padding(.bottom, 6)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(m3.surfaceContainerLow, in: RoundedRectangle(cornerRadius: 36, style: .continuous))
        .overlay(alignment: .top) {
            if let stamp {
                let tones = stamp == .keep ? m3.keep : m3.reject
                Text(stamp == .keep ? "TIENI" : "DA SMETTERE")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(tones.onAccent)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(tones.accent, in: Capsule())
                    .rotationEffect(.degrees(stamp == .keep ? -8 : 8))
                    .padding(.top, 28)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
        .animation(.snappy(duration: 0.2), value: stamp)
    }

    private func chip(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.m3LabelLarge)
            .foregroundStyle(m3.onSecondaryContainer)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(m3.secondaryContainer, in: Capsule())
    }
}

// MARK: - Unfollow session

/// Walks the "to unfollow" list: open the profile, unfollow on Instagram, next.
private struct UnfollowSession: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3

    private var rows: [AccountRow] {
        _ = model.revision
        return model.analysis.rows(for: .toUnfollow, sort: .alphabetical)
    }

    var body: some View {
        let rows = rows
        let next = rows.first { !model.isOpened($0.username) }
        let openedCount = rows.filter { model.isOpened($0.username) }.count
        ScrollView {
            VStack(spacing: 16) {
                if rows.isEmpty {
                    EmptyStateView(icon: "xmark.circle.fill", title: "Nessuno da smettere",
                                   message: "Nella modalità Rivedi scorri a destra gli account che vuoi smettere di seguire.")
                } else {
                    M3Card(color: m3.primaryContainer, padding: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(openedCount) di \(rows.count) aperti")
                                .font(.m3TitleLarge)
                                .foregroundStyle(m3.onPrimaryContainer)
                            ProgressView(value: Double(openedCount), total: Double(max(1, rows.count)))
                                .tint(m3.primary)
                            Text("Apri il profilo, tocca \"Segui già\" › \"Smetti di seguire\" su Instagram e torna qui. Al prossimo import chi non segui più sparisce da questa lista.")
                                .font(.m3BodySmall)
                                .foregroundStyle(m3.onPrimaryContainer.opacity(0.8))
                        }
                    }
                    if let next {
                        M3Card(padding: 20) {
                            VStack(spacing: 14) {
                                Avatar(row: next, size: 84)
                                Text("@\(next.username)")
                                    .font(.m3TitleLarge)
                                    .foregroundStyle(m3.onSurface)
                                PillButton(title: "Apri su Instagram", icon: "arrow.up.right.square.fill", tones: m3.reject) {
                                    model.open(next.username)
                                }
                                Button("Tienilo invece") { model.setMark([next.username], .keep) }
                                    .font(.m3LabelLarge)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    } else {
                        EmptyStateView(icon: "checkmark.circle.fill", title: "Tutti aperti",
                                       message: "Quando hai finito su Instagram, scarica un nuovo export e importalo: i segni si tolgono da soli.")
                    }
                    SectionTitle("Elenco")
                    VStack(spacing: 0) {
                        ForEach(rows) { r in
                            Button {
                                model.open(r.username)
                            } label: {
                                HStack {
                                    AccountRowView(row: r, kind: .toUnfollow, opened: model.isOpened(r.username))
                                    Image(systemName: model.isOpened(r.username) ? "checkmark.circle.fill" : "arrow.up.right")
                                        .foregroundStyle(model.isOpened(r.username) ? m3.success : m3.outline)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(m3.surfaceContainerLow, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
            }
            .padding(16)
        }
    }
}
