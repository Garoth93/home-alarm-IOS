import SwiftUI
import InstaCore

/// Account card: relationship, dates, mark, note and history across snapshots.
struct AccountDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    @Environment(\.dismiss) private var dismiss
    let username: String
    let kind: ListKind
    @State private var note = ""
    @FocusState private var noteFocused: Bool

    var body: some View {
        let row = model.analysis.row(username) ?? AccountRow(username: username)
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header(row)
                    markPicker(row)
                    infoCard(row)
                    noteCard
                    historyCard
                }
                .padding(16)
            }
            .background(m3.surface)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { commitNote(); dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(32)
        .onAppear { note = row.note }
        .onDisappear { commitNote() }
    }

    private func commitNote() {
        model.setNote(username, note.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func header(_ row: AccountRow) -> some View {
        VStack(spacing: 10) {
            Avatar(row: row, size: 88)
            VStack(spacing: 2) {
                Text("@\(row.username)")
                    .font(.m3TitleLarge)
                    .foregroundStyle(m3.onSurface)
                if !row.fullName.isEmpty {
                    Text(row.fullName)
                        .font(.m3BodyMedium)
                        .foregroundStyle(m3.onSurfaceVariant)
                }
            }
            if !row.status.isEmpty {
                Text(row.status)
                    .font(.m3LabelLarge)
                    .foregroundStyle(m3.onSecondaryContainer)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(m3.secondaryContainer, in: Capsule())
            }
            HStack(spacing: 10) {
                PillButton(title: "Apri su Instagram", icon: "arrow.up.right.square.fill", tones: m3.primaryTones, height: 48) {
                    model.open(row.username)
                }
                Button {
                    model.copy([row.username])
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(m3.onSurface)
                        .frame(width: 48, height: 48)
                        .background(m3.surfaceContainerHigh, in: Circle())
                }
                .accessibilityLabel("Copia username")
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }

    private func markPicker(_ row: AccountRow) -> some View {
        HStack(spacing: 10) {
            markButton("Tieni", "checkmark", .keep, row, tones: m3.keep, enabled: true)
            markButton("Da smettere", "xmark", .unfollow, row, tones: m3.reject, enabled: row.isFollowing)
        }
    }

    private func markButton(_ title: String, _ icon: String, _ state: MarkState, _ row: AccountRow, tones: Tones, enabled: Bool) -> some View {
        let on = row.mark == state
        return Button {
            model.toggleMark(row.username, state)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: on ? "\(icon).circle.fill" : icon)
                Text(on ? (state == .keep ? "Tenuto" : "Da smettere ✓") : title)
            }
            .font(.m3LabelLarge)
            .foregroundStyle(on ? tones.onAccent : tones.onContainer)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(on ? tones.accent : tones.container, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    private func infoCard(_ row: AccountRow) -> some View {
        let F = Rel.follower.rawValue, G = Rel.following.rawValue
        let followerSince = InstaFormat.date(row.since[F] != 0 ? row.since[F] : row.prevSince[F])
        let followingSince = InstaFormat.date(row.since[G] != 0 ? row.since[G] : row.prevSince[G])
        let pendingSince = InstaFormat.date(row.since[Rel.pendingSent.rawValue])
        return M3Card(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                info("Ti segue", row.isFollower ? (followerSince.isEmpty ? "sì" : "dal \(followerSince)") : (row.had(.follower) ? "non più (dal \(followerSince))" : "no"),
                     icon: "person.fill.checkmark", positive: row.isFollower)
                info("Lo segui", row.isFollowing ? (followingSince.isEmpty ? "sì" : "dal \(followingSince)") : (row.had(.following) ? "non più" : "no"),
                     icon: "person.crop.circle.badge.checkmark", positive: row.isFollowing)
                if row.has(.pendingSent) {
                    info("Richiesta inviata", pendingSince.isEmpty ? "in attesa" : "il \(pendingSince)", icon: "hourglass", positive: nil)
                }
                if row.has(.closeFriend) {
                    info("Amici stretti", "sì", icon: "star.fill", positive: true)
                }
            }
        }
    }

    private func info(_ title: String, _ value: String, icon: String, positive: Bool?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(positive == true ? m3.success : positive == false ? m3.outline : m3.tertiary)
                .frame(width: 26)
            Text(title)
                .font(.m3BodyMedium)
                .foregroundStyle(m3.onSurfaceVariant)
            Spacer()
            Text(value)
                .font(.m3LabelLarge)
                .foregroundStyle(m3.onSurface)
                .multilineTextAlignment(.trailing)
        }
    }

    private var noteCard: some View {
        M3Card(padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Nota", systemImage: "note.text")
                    .font(.m3LabelLarge)
                    .foregroundStyle(m3.onSurfaceVariant)
                TextField("Es. collega, brand, amico di Luca…", text: $note, axis: .vertical)
                    .font(.m3BodyMedium)
                    .lineLimit(1...4)
                    .focused($noteFocused)
                    .onSubmit(commitNote)
                    .onChange(of: noteFocused) { _, focused in if !focused { commitNote() } }
            }
        }
    }

    private var historyCard: some View {
        let points = model.data.history(owner: model.owner, username: username, currentID: model.currentID)
        return M3Card(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Storico")
                    .font(.m3TitleSmall)
                    .foregroundStyle(m3.onSurface)
                if points.isEmpty {
                    Text("Nessuna istantanea.").font(.m3BodySmall).foregroundStyle(m3.onSurfaceVariant)
                }
                ForEach(points.reversed()) { p in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(p.isCurrent ? m3.primary : m3.outlineVariant)
                            .frame(width: 8, height: 8)
                        Text(InstaFormat.date(p.takenAt))
                            .font(.m3LabelLarge)
                            .foregroundStyle(p.isCurrent ? m3.onSurface : m3.onSurfaceVariant)
                        Spacer()
                        pill("ti segue", on: p.follower)
                        pill("lo segui", on: p.following)
                    }
                }
            }
        }
    }

    private func pill(_ text: String, on: Bool) -> some View {
        Text(text)
            .font(.m3LabelSmall)
            .strikethrough(!on)
            .foregroundStyle(on ? m3.onSuccessContainer : m3.outline)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(on ? m3.successContainer : m3.surfaceContainerHigh, in: Capsule())
    }
}
