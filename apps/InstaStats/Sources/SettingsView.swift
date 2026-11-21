import SwiftUI
import UniformTypeIdentifiers
import InstaCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    private enum Picking { case export, desktop, restore }
    @State private var picking: Picking?
    @State private var isPicking = false
    @State private var backupDoc: TextFileDocument?
    @State private var showBackup = false
    @State private var renaming = false
    @State private var newOwner = ""
    @State private var confirmErase = false

    var body: some View {
        List {
            Section {
                Button {
                    picking = .export
                    isPicking = true
                } label: {
                    Label("Importa export di Instagram", systemImage: "square.and.arrow.down.fill")
                }
                if model.hasData {
                    NavigationLink(value: Route.snapshots) {
                        LabeledContent {
                            Text("\(model.snapshots.count)")
                        } label: {
                            Label("Istantanee", systemImage: "clock.arrow.circlepath")
                        }
                    }
                }
            } header: {
                Text("Dati")
            } footer: {
                Text("Ogni export importato diventa un'istantanea. Con due o più istantanee vedi chi è arrivato e chi se n'è andato.")
            }
            .listRowBackground(m3.surfaceContainerLow)

            if model.hasData {
                Section {
                    if model.owners.count > 1 {
                        Picker(selection: Binding(get: { model.owner }, set: { model.loadOwner($0) })) {
                            ForEach(model.owners, id: \.self) { o in Text("@\(o)").tag(o) }
                        } label: {
                            Label("Account", systemImage: "person.crop.circle")
                        }
                    }
                    Button {
                        newOwner = model.owner
                        renaming = true
                    } label: {
                        LabeledContent {
                            Text("@\(model.owner)")
                        } label: {
                            Label("Rinomina account", systemImage: "pencil")
                        }
                    }
                } header: {
                    Text("Account")
                } footer: {
                    Text("Se hai importato lo stesso account con due nomi, rinominalo con l'altro nome: le istantanee si uniscono.")
                }
                .listRowBackground(m3.surfaceContainerLow)
            }

            Section {
                Toggle(isOn: Binding(get: { model.settings.showKept }, set: { v in model.updateSettings { $0.showKept = v } })) {
                    Label("Mostra i tenuti nei Non ricambiano", systemImage: "eye")
                }
                Picker(selection: Binding(get: { model.settings.sortMode }, set: { v in model.updateSettings { $0.sortMode = v } })) {
                    ForEach(SortMode.allCases, id: \.self) { m in Text(m.label).tag(m) }
                } label: {
                    Label("Ordine delle liste", systemImage: "arrow.up.arrow.down")
                }
                Picker(selection: Binding(get: { model.settings.appearance }, set: { v in model.updateSettings { $0.appearance = v } })) {
                    ForEach(Appearance.allCases, id: \.self) { a in Text(a.label).tag(a) }
                } label: {
                    Label("Tema", systemImage: "circle.lefthalf.filled")
                }
            } header: {
                Text("Preferenze")
            }
            .listRowBackground(m3.surfaceContainerLow)

            Section {
                Button {
                    picking = .desktop
                    isPicking = true
                } label: {
                    Label("Importa da instaStats desktop", systemImage: "desktopcomputer")
                }
                Button {
                    if let json = model.backupJSON() {
                        backupDoc = TextFileDocument(text: json)
                        showBackup = true
                    }
                } label: {
                    Label("Esporta backup (JSON)", systemImage: "square.and.arrow.up")
                }
                .disabled(!model.hasData)
                Button {
                    picking = .restore
                    isPicking = true
                } label: {
                    Label("Ripristina backup", systemImage: "arrow.down.doc")
                }
                Button(role: .destructive) {
                    confirmErase = true
                } label: {
                    Label("Cancella tutti i dati", systemImage: "trash")
                }
                .disabled(!model.hasData)
            } header: {
                Text("Backup")
            } footer: {
                Text("Dal PC copia instastats.db (percorso in Impostazioni dell'app desktop) in iCloud Drive e importalo qui: istantanee, segni e note arrivano sul telefono. I dati restano solo su questo iPhone.")
            }
            .listRowBackground(m3.surfaceContainerLow)

            Section("Informazioni") {
                LabeledContent("Versione", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
                LabeledContent("Istantanee salvate", value: "\(model.data.snapshots.count)")
            }
            .listRowBackground(m3.surfaceContainerLow)
        }
        .scrollContentBackground(.hidden)
        .background(m3.surface)
        .navigationTitle("Altro")
        .fileImporter(isPresented: $isPicking,
                      allowedContentTypes: picking == .export ? [.zip, .folder, .json] : (picking == .restore ? [.json] : [.data]),
                      allowsMultipleSelection: picking == .export) { result in
            let kind = picking
            guard case .success(let urls) = result, !urls.isEmpty else { return }
            switch kind {
            case .export: model.importFiles(urls)
            case .desktop: model.importDesktopDatabase(urls[0])
            case .restore: model.restore(from: urls[0])
            case nil: break
            }
        }
        .background {
            Color.clear.fileExporter(isPresented: $showBackup, document: backupDoc, contentType: .json,
                          defaultFilename: "instastats-backup-\(InstaFormat.date(Date()).replacingOccurrences(of: " ", with: "-")).json") { result in
                if case .success = result { model.show("Backup salvato", icon: "checkmark", style: .success) }
                backupDoc = nil
            }
        }
        .alert("Rinomina account", isPresented: $renaming) {
            TextField("username", text: $newOwner)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Annulla", role: .cancel) {}
            Button("Rinomina") {
                if !model.renameOwner(newOwner) { model.errorMessage = "Username non valido: solo lettere minuscole, numeri, punti e trattini bassi." }
            }
        } message: {
            Text("Nome utente Instagram senza @.")
        }
        .confirmationDialog("Cancellare tutti i dati?", isPresented: $confirmErase, titleVisibility: .visible) {
            Button("Cancella istantanee e segni", role: .destructive) { model.eraseAll() }
        } message: {
            Text("Fai prima un backup se vuoi conservarli.")
        }
    }
}

/// List of snapshots: rename, change date, delete.
struct SnapshotsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    @State private var editing: Snapshot?
    @State private var toDelete: Snapshot?

    var body: some View {
        List {
            Section {
                ForEach(model.snapshots.reversed()) { s in
                    Button {
                        model.selectCurrent(s.id)
                    } label: {
                        HStack(spacing: 12) {
                            IconBadge(icon: s.id == model.currentID ? "checkmark" : "calendar",
                                      tones: s.id == model.currentID ? m3.primaryTones : m3.neutral, size: 40, filled: s.id == model.currentID)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.label)
                                    .font(.m3TitleSmall)
                                    .foregroundStyle(m3.onSurface)
                                Text("\(InstaFormat.date(s.takenAt)) · \(InstaFormat.number(s.followers)) follower · \(InstaFormat.number(s.following)) seguiti")
                                    .font(.m3BodySmall)
                                    .foregroundStyle(m3.onSurfaceVariant)
                            }
                            Spacer()
                            if s.id == model.compareID {
                                Text("confronto")
                                    .font(.m3LabelSmall)
                                    .foregroundStyle(m3.onTertiaryContainer)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(m3.tertiaryContainer, in: Capsule())
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button(role: .destructive) { toDelete = s } label: { Label("Elimina", systemImage: "trash") }
                        Button { editing = s } label: { Label("Modifica", systemImage: "pencil") }
                    }
                    .contextMenu {
                        Button { model.selectCompare(s.id) } label: { Label("Usa come confronto", systemImage: "arrow.left.arrow.right") }
                        Button { editing = s } label: { Label("Modifica", systemImage: "pencil") }
                        Button(role: .destructive) { toDelete = s } label: { Label("Elimina", systemImage: "trash") }
                    }
                    .listRowBackground(m3.surfaceContainerLow)
                }
            } footer: {
                Text("Tocca per vederla, tieni premuto per usarla come confronto. La data viene dal nome dell'export: se è sbagliata correggila.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(m3.surface)
        .navigationTitle("Istantanee")
        .sheet(item: $editing) { s in
            SnapshotEditor(snapshot: s)
        }
        .confirmationDialog("Eliminare l'istantanea?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Elimina", role: .destructive) {
                if let s = toDelete { model.deleteSnapshot(s.id) }
                toDelete = nil
            }
        } message: {
            Text("I segni sugli account restano.")
        }
    }
}

private struct SnapshotEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let snapshot: Snapshot
    @State private var label = ""
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nome", text: $label)
                DatePicker("Data dell'export", selection: $date, displayedComponents: .date)
                    .environment(\.locale, Locale(identifier: "it_IT"))
            }
            .navigationTitle("Istantanea")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        model.renameSnapshot(snapshot.id, label)
                        if !Calendar.current.isDate(date, inSameDayAs: snapshot.takenAt) { model.setSnapshotDate(snapshot.id, date) }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear {
            label = snapshot.label
            date = snapshot.takenAt
        }
    }
}
