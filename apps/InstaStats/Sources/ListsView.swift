import SwiftUI
import InstaCore

/// All the lists, grouped as in the desktop sidebar.
struct ListsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3

    var body: some View {
        let an = model.analysis
        List {
            if !model.hasData {
                EmptyStateView(icon: "person.2.fill", title: "Nessun export", message: "Importa un export di Instagram dalla Panoramica.")
                    .listRowBackground(Color.clear)
            } else {
                ForEach(ListKind.Section.allCases, id: \.self) { section in
                    Section {
                        ForEach(ListKind.kinds(in: section)) { k in
                            NavigationLink(value: Route.list(k)) {
                                row(k, count: an.count(k), disabled: k.needsCompare && !an.stats.hasCompare)
                            }
                            .listRowBackground(m3.surfaceContainerLow)
                        }
                    } header: {
                        Text(section.rawValue)
                            .font(.m3LabelLarge)
                            .foregroundStyle(m3.onSurfaceVariant)
                            .textCase(nil)
                    } footer: {
                        if section == .changes && !an.stats.hasCompare {
                            Text("Servono almeno due export: importa di nuovo tra qualche settimana per vedere chi è arrivato e chi se n'è andato.")
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(m3.surface)
        .navigationTitle("Liste")
    }

    private func row(_ k: ListKind, count: Int, disabled: Bool) -> some View {
        HStack(spacing: 12) {
            IconBadge(icon: k.icon, tones: tones(for: k), size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(k.title)
                    .font(.m3TitleSmall)
                    .foregroundStyle(m3.onSurface)
                Text(k.hint)
                    .font(.m3BodySmall)
                    .foregroundStyle(m3.onSurfaceVariant)
                    .lineLimit(2)
            }
            Spacer()
            Text(disabled ? "–" : InstaFormat.number(count))
                .font(.m3TitleSmall)
                .foregroundStyle(m3.onSurfaceVariant)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
        .opacity(disabled ? 0.55 : 1)
    }

    private func tones(for k: ListKind) -> Tones {
        switch k {
        case .toUnfollow, .notBack, .lostFollowers, .dropped: return m3.reject
        case .kept, .newFollowers, .mutual: return m3.keep
        case .fans, .closeFriends, .recentlyUnfollowed: return m3.tertiaryTones
        default: return m3.primaryTones
        }
    }
}

/// One list: search, sort, swipe to mark, multiple selection, CSV.
struct AccountListView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    let kind: ListKind

    @State private var search = ""
    @State private var selection = Set<String>()
    @State private var editMode: EditMode = .inactive
    @State private var detail: String?
    @State private var csv: TextFileDocument?
    @State private var showExporter = false

    private var rows: [AccountRow] {
        _ = model.revision
        return model.analysis.rows(for: kind, search: search, sort: model.settings.sortMode)
    }

    var body: some View {
        let rows = rows
        List(selection: $selection) {
            Section {
                ForEach(rows) { r in
                    Group {
                        if editMode.isEditing {
                            AccountRowView(row: r, kind: kind, opened: model.isOpened(r.username))
                        } else {
                            Button {
                                detail = r.username
                            } label: {
                                AccountRowView(row: r, kind: kind, opened: model.isOpened(r.username))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                model.toggleMark(r.username, .keep)
                            } label: {
                                Label(r.mark == .keep ? "Togli" : "Tieni", systemImage: "checkmark")
                            }
                            .tint(m3.success)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if r.isFollowing {
                                Button {
                                    model.toggleMark(r.username, .unfollow)
                                } label: {
                                    Label(r.mark == .unfollow ? "Togli" : "Da smettere", systemImage: "xmark")
                                }
                                .tint(m3.error)
                            }
                            Button {
                                model.open(r.username)
                            } label: {
                                Label("Apri", systemImage: "arrow.up.right.square")
                            }
                            .tint(m3.primary)
                        }
                        .contextMenu {
                            Button { model.open(r.username) } label: { Label("Apri su Instagram", systemImage: "arrow.up.right.square") }
                            Button { model.copy([r.username]) } label: { Label("Copia username", systemImage: "doc.on.doc") }
                            Divider()
                            Button { model.toggleMark(r.username, .keep) } label: { Label(r.mark == .keep ? "Togli \"tenuto\"" : "Tieni", systemImage: "checkmark") }
                            if r.isFollowing {
                                Button(role: .destructive) { model.toggleMark(r.username, .unfollow) } label: {
                                    Label(r.mark == .unfollow ? "Togli \"da smettere\"" : "Da smettere di seguire", systemImage: "xmark")
                                }
                            }
                        }
                        .listRowBackground(m3.surfaceContainerLow)
                        .tag(r.username)
                }
            } header: {
                Text(headerText(rows.count))
                    .font(.m3LabelMedium)
                    .foregroundStyle(m3.onSurfaceVariant)
                    .textCase(nil)
            }
            if rows.isEmpty {
                EmptyStateView(icon: kind.icon, title: search.isEmpty ? "Nessun account" : "Nessun risultato",
                               message: search.isEmpty ? kind.hint : "Prova con un altro nome.")
                    .listRowBackground(Color.clear)
            }
        }
        .environment(\.editMode, $editMode)
        .scrollContentBackground(.hidden)
        .background(m3.surface)
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Cerca username o nome")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(editMode.isEditing ? "Fine" : "Seleziona") {
                    withAnimation {
                        editMode = editMode.isEditing ? .inactive : .active
                        if !editMode.isEditing { selection.removeAll() }
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Ordina", selection: Binding(
                        get: { model.settings.sortMode },
                        set: { v in model.updateSettings { $0.sortMode = v } }
                    )) {
                        ForEach(SortMode.allCases, id: \.self) { m in Text(m.label).tag(m) }
                    }
                    Divider()
                    Button { model.copy(rows.map(\.username)) } label: { Label("Copia tutti gli username", systemImage: "doc.on.doc") }
                    Button {
                        csv = TextFileDocument(text: InstaFormat.csv(rows))
                        showExporter = true
                    } label: { Label("Esporta CSV", systemImage: "tablecells") }
                    if model.canUndo {
                        Divider()
                        Button { model.undo() } label: { Label("Annulla ultimo segno", systemImage: "arrow.uturn.backward") }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            if editMode.isEditing {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        selection = Set(rows.map(\.username))
                    } label: { Text(selection.count == rows.count && !rows.isEmpty ? "Tutti" : "Seleziona tutti") }
                    Spacer()
                    Menu {
                        Button { mark(.keep) } label: { Label("Tieni", systemImage: "checkmark") }
                        Button(role: .destructive) { mark(.unfollow) } label: { Label("Da smettere di seguire", systemImage: "xmark") }
                        Button { mark(.none) } label: { Label("Togli il segno", systemImage: "circle.slash") }
                        Divider()
                        Button { model.copy(selectedInOrder(rows)) } label: { Label("Copia username", systemImage: "doc.on.doc") }
                    } label: {
                        Text(selection.isEmpty ? "Azioni" : "Azioni (\(selection.count))")
                            .fontWeight(.semibold)
                    }
                    .disabled(selection.isEmpty)
                }
            }
        }
        .sheet(item: Binding(get: { detail.map(IdentifiedUser.init) }, set: { detail = $0?.id })) { u in
            AccountDetailView(username: u.id, kind: kind)
        }
        .fileExporter(isPresented: $showExporter, document: csv, contentType: .commaSeparatedText,
                      defaultFilename: "\(model.owner)-\(kind.title.lowercased().replacingOccurrences(of: " ", with: "-")).csv") { _ in
            csv = nil
        }
        .onChange(of: kind) { _, _ in selection.removeAll() }
    }

    private func headerText(_ n: Int) -> String {
        let base = "\(InstaFormat.number(n)) account"
        return editMode.isEditing && !selection.isEmpty ? "\(base) · \(selection.count) selezionati" : base
    }

    private func selectedInOrder(_ rows: [AccountRow]) -> [String] {
        rows.map(\.username).filter { selection.contains($0) }
    }

    private func mark(_ state: MarkState) {
        let users = selectedInOrder(rows).filter { u in
            state != .unfollow || model.analysis.row(u)?.isFollowing == true
        }
        model.setMark(users, state)
        selection.removeAll()
    }
}

struct IdentifiedUser: Identifiable {
    let id: String
}

/// One account in a list.
struct AccountRowView: View {
    @Environment(\.m3) private var m3
    let row: AccountRow
    let kind: ListKind
    var opened = false

    var body: some View {
        HStack(spacing: 12) {
            Avatar(row: row, size: 44, ring: opened ? m3.primary : nil)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("@\(row.username)")
                        .font(.m3TitleSmall)
                        .foregroundStyle(m3.onSurface)
                        .lineLimit(1)
                    if row.has(.closeFriend) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(m3.success)
                    }
                }
                let sub = [row.fullName, row.subtitle(for: kind)].filter { !$0.isEmpty }.joined(separator: " · ")
                if !sub.isEmpty {
                    Text(sub)
                        .font(.m3BodySmall)
                        .foregroundStyle(m3.onSurfaceVariant)
                        .lineLimit(1)
                }
                if !row.note.isEmpty {
                    Label(row.note, systemImage: "note.text")
                        .font(.m3LabelSmall)
                        .foregroundStyle(m3.outline)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            MarkBadge(mark: row.mark)
        }
        .padding(.vertical, 2)
    }
}
