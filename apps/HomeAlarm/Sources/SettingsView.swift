import SwiftUI
import UniformTypeIdentifiers
import WidgetKit
import AlarmCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    @State private var editing: HouseEditorTarget?
    @State private var includePasswords = true
    @State private var exportDoc: TextFileDocument?
    @State private var exportName = "antifurto-backup.json"
    @State private var exportType: UTType = .json
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var confirmClear = false
    @State private var pendingRestore: BackupFile?

    var body: some View {
        List {
            housesSection
            sendingSection
            widgetSection
            appearanceSection
            backupSection
            infoSection
        }
        .scrollContentBackground(.hidden)
        .background(m3.surface)
        .navigationTitle("Impostazioni")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        .sheet(item: $editing) { target in
            HouseEditorView(target: target)
        }
        .fileExporter(isPresented: $showExporter, document: exportDoc, contentType: exportType, defaultFilename: exportName) { result in
            if case .success = result { model.show("File salvato", icon: "checkmark", style: .success) }
            exportDoc = nil
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            importBackup(result)
        }
        .confirmationDialog("Cancellare tutto lo storico?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Cancella storico", role: .destructive) { model.clearHistory() }
        } message: {
            Text("Le case e le zone restano. Le statistiche ripartono da zero.")
        }
        .confirmationDialog("Ripristinare il backup?", isPresented: Binding(
            get: { pendingRestore != nil },
            set: { if !$0 { pendingRestore = nil } }
        ), titleVisibility: .visible) {
            Button("Sostituisci tutti i dati", role: .destructive) {
                if let b = pendingRestore { model.restore(b) }
                pendingRestore = nil
            }
        } message: {
            if let b = pendingRestore {
                Text("\(b.data.houses.count) case e \(b.data.events.count) comandi. I dati attuali verranno sostituiti.")
            }
        }
    }

    // MARK: Sections

    private var housesSection: some View {
        Section {
            ForEach(model.houses) { house in
                Button {
                    editing = .edit(house)
                } label: {
                    HStack(spacing: 12) {
                        IconBadge(icon: house.icon, tones: m3.tones(house.colorHex), size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(house.name)
                                .font(.m3TitleSmall)
                                .foregroundStyle(m3.onSurface)
                            Text(houseSubtitle(house))
                                .font(.m3BodySmall)
                                .foregroundStyle(m3.onSurfaceVariant)
                        }
                        Spacer()
                        if house.id == model.data.defaultHouse?.id && model.houses.count > 1 {
                            Text("Predefinita")
                                .font(.m3LabelSmall)
                                .foregroundStyle(m3.onSecondaryContainer)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(m3.secondaryContainer, in: Capsule())
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(m3.outline)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(m3.surfaceContainerLow)
            }
            .onMove { model.moveHouses(from: $0, to: $1) }
            Button {
                editing = .new(model.houses.isEmpty ? House.example() : House(name: "", colorHex: Catalog.colors[model.houses.count % Catalog.colors.count]))
            } label: {
                Label("Aggiungi casa", systemImage: "plus.circle.fill")
                    .font(.m3LabelLarge)
            }
            .listRowBackground(m3.surfaceContainerLow)
        } header: {
            Text("Case")
        } footer: {
            Text("Per ogni casa: numero della centralina, password, comando di disinserimento e zone.")
        }
    }

    private func houseSubtitle(_ h: House) -> String {
        let phone = h.phoneNumber.isEmpty ? "numero mancante" : h.phoneNumber
        let pw = model.password(for: h.id).isEmpty ? " · password mancante" : ""
        return "\(phone) · \(h.zones.count) zone\(pw)"
    }

    private var sendingSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { model.settings.confirmBeforeSending },
                set: { v in model.updateSettings { $0.confirmBeforeSending = v } }
            )) {
                Label("Chiedi conferma prima dell'SMS", systemImage: "hand.raised.fill")
            }
            Toggle(isOn: Binding(
                get: { model.settings.requireAuthForDisarm },
                set: { v in model.updateSettings { $0.requireAuthForDisarm = v } }
            )) {
                Label("Face ID per disinserire", systemImage: "faceid")
            }
        } header: {
            Text("Invio")
        } footer: {
            Text("iOS non permette alle app di inviare SMS da sole: l'app prepara il messaggio e tu premi Invia. Con Face ID, nessuno può disinserire dal tuo telefono sbloccato.")
        }
        .listRowBackground(m3.surfaceContainerLow)
    }

    private var widgetSection: some View {
        Section {
            if model.houses.count > 1 {
                Picker(selection: Binding(
                    get: { model.data.defaultHouse?.id },
                    set: { v in model.updateSettings { $0.defaultHouseID = v } }
                )) {
                    ForEach(model.houses) { h in
                        Text(h.name).tag(UUID?.some(h.id))
                    }
                } label: {
                    Label("Casa predefinita", systemImage: "star.fill")
                }
            }
            HStack {
                Label("Dati condivisi con i widget", systemImage: SharedStore.isShared ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                Spacer()
                Text(SharedStore.isShared ? "Attivi" : "Non disponibili")
                    .foregroundStyle(SharedStore.isShared ? m3.success : m3.warning)
            }
            Button {
                WidgetCenter.shared.reloadAllTimelines()
                ControlCenter.shared.reloadAllControls()
                model.show("Widget aggiornati", icon: "arrow.clockwise", style: .info)
            } label: {
                Label("Aggiorna widget", systemImage: "arrow.clockwise")
            }
        } header: {
            Text("Widget e controlli")
        } footer: {
            Text(SharedStore.isShared
                 ? "Aggiungi i widget dalla schermata Home (tieni premuto → Modifica → Aggiungi widget → Antifurto) e il pulsante nel Centro di Controllo. Un tocco apre l'SMS pronto."
                 : "La firma usata non include l'App Group: i widget mostrano solo \"Disinserisci\" della casa predefinita. Vedi il README per firmare con gli App Group.")
        }
        .listRowBackground(m3.surfaceContainerLow)
    }

    private var appearanceSection: some View {
        Section("Aspetto") {
            Picker(selection: Binding(
                get: { model.settings.appearance },
                set: { v in model.updateSettings { $0.appearance = v } }
            )) {
                ForEach(Appearance.allCases, id: \.self) { a in
                    Text(a.label).tag(a)
                }
            } label: {
                Label("Tema", systemImage: "circle.lefthalf.filled")
            }
        }
        .listRowBackground(m3.surfaceContainerLow)
    }

    private var backupSection: some View {
        Section {
            Toggle(isOn: $includePasswords) {
                Label("Includi le password nel backup", systemImage: "key.fill")
            }
            Button {
                exportBackup()
            } label: {
                Label("Esporta backup (JSON)", systemImage: "square.and.arrow.up")
            }
            Button {
                showImporter = true
            } label: {
                Label("Importa backup", systemImage: "square.and.arrow.down")
            }
            Button {
                exportDoc = TextFileDocument(text: AlarmFormat.csv(model.data))
                exportName = "antifurto-storico.csv"
                exportType = .commaSeparatedText
                showExporter = true
            } label: {
                Label("Esporta storico (CSV)", systemImage: "tablecells")
            }
            .disabled(model.data.events.isEmpty)
            Button(role: .destructive) {
                confirmClear = true
            } label: {
                Label("Cancella storico", systemImage: "trash")
            }
            .disabled(model.data.events.isEmpty)
        } header: {
            Text("Backup")
        } footer: {
            Text("I dati restano solo su questo iPhone. Fai un backup prima di reinstallare l'app; se includi le password, conserva il file in un posto sicuro.")
        }
        .listRowBackground(m3.surfaceContainerLow)
    }

    private var infoSection: some View {
        Section("Informazioni") {
            LabeledContent("Versione", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
            LabeledContent("Comandi registrati", value: "\(model.data.events.count)")
        }
        .listRowBackground(m3.surfaceContainerLow)
    }

    // MARK: Backup

    private func exportBackup() {
        let backup = model.makeBackup(includePasswords: includePasswords)
        guard let data = try? JSONFileStore<BackupFile>.encoder.encode(backup),
              let text = String(data: data, encoding: .utf8) else {
            model.errorMessage = "Non riesco a creare il backup."
            return
        }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        exportDoc = TextFileDocument(text: text)
        exportName = "antifurto-backup-\(df.string(from: Date())).json"
        exportType = .json
        showExporter = true
    }

    private func importBackup(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let raw = try Data(contentsOf: url)
            if let backup = try? JSONFileStore<BackupFile>.decoder.decode(BackupFile.self, from: raw), backup.format == "home-alarm-backup" {
                pendingRestore = backup
            } else {
                let data = try JSONFileStore<AlarmData>.decoder.decode(AlarmData.self, from: raw)
                pendingRestore = BackupFile(data: data, passwords: [:])
            }
        } catch {
            model.errorMessage = "File non valido: \(error.localizedDescription)"
        }
    }
}

/// Plain text document for `.fileExporter` (JSON and CSV).
struct TextFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText, .plainText] }
    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, let s = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = s
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
