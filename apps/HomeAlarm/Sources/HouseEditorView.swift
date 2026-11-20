import SwiftUI
import AlarmCore

enum HouseEditorTarget: Identifiable {
    case new(House)
    case edit(House)

    var id: UUID {
        switch self {
        case .new(let h), .edit(let h): return h.id
        }
    }

    var house: House {
        switch self {
        case .new(let h), .edit(let h): return h
        }
    }

    var isNew: Bool {
        if case .new = self { return true }
        return false
    }
}

/// Create / edit a house: phone, password, commands and zones.
struct HouseEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    @Environment(\.dismiss) private var dismiss

    let target: HouseEditorTarget
    @State private var draft: House
    @State private var password: String
    @State private var showPassword = false
    @State private var editingZone: ZoneEditorTarget?
    @State private var confirmDelete = false

    init(target: HouseEditorTarget) {
        self.target = target
        _draft = State(initialValue: target.house)
        _password = State(initialValue: target.isNew ? "" : AppModel.shared.password(for: target.house.id))
    }

    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nome (es. Casa, Mare)", text: $draft.name)
                        .font(.m3TitleMedium)
                    IconPicker(icons: Catalog.houseIcons, selection: $draft.icon, colorHex: draft.colorHex)
                    ColorPickerRow(selection: $draft.colorHex)
                } header: {
                    Text("Casa")
                }

                Section {
                    LabeledContent {
                        TextField("+39 333 1234567", text: $draft.phoneNumber)
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                            .multilineTextAlignment(.trailing)
                    } label: {
                        Label("Numero", systemImage: "phone.fill")
                    }
                    LabeledContent {
                        HStack {
                            Group {
                                if showPassword {
                                    TextField("Password", text: $password)
                                } else {
                                    SecureField("Password", text: $password)
                                }
                            }
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                            Button {
                                showPassword.toggle()
                            } label: {
                                Image(systemName: showPassword ? "eye.slash" : "eye")
                                    .foregroundStyle(m3.onSurfaceVariant)
                            }
                            .buttonStyle(.plain)
                        }
                    } label: {
                        Label("Password", systemImage: "key.fill")
                    }
                } header: {
                    Text("Centralina")
                } footer: {
                    Text("Numero e password vengono aggiunti automaticamente a ogni comando. La password resta nel portachiavi dell'iPhone.")
                }

                Section {
                    LabeledContent {
                        TextField("disattiva", text: $draft.disarmCommand)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                    } label: {
                        Label("Disinserisci", systemImage: "shield.slash.fill")
                    }
                    LabeledContent {
                        TextField("facoltativo, es. stato", text: $draft.statusCommand)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                    } label: {
                        Label("Stato", systemImage: "questionmark.bubble.fill")
                    }
                    LabeledContent {
                        TextField(MessageBuilder.defaultTemplate, text: $draft.messageTemplate)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                            .font(.system(.body, design: .monospaced))
                    } label: {
                        Label("Formato SMS", systemImage: "text.bubble.fill")
                    }
                } header: {
                    Text("Comandi")
                } footer: {
                    Text("Nel formato, {comando} è la combinazione e {password} la password. Il predefinito \"{comando} {password}\" produce ad esempio \"attiva 1-2-3 1966\".")
                }

                Section {
                    ForEach(draft.zones) { zone in
                        Button {
                            editingZone = .edit(zone)
                        } label: {
                            ZoneRow(zone: zone)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { draft.zones.remove(atOffsets: $0) }
                    .onMove { draft.zones.move(fromOffsets: $0, toOffset: $1) }
                    Button {
                        editingZone = .new(Zone(name: "", command: "attiva ", icon: "lock.shield.fill", colorHex: draft.colorHex))
                    } label: {
                        Label("Aggiungi zona", systemImage: "plus.circle.fill")
                            .font(.m3LabelLarge)
                    }
                } header: {
                    Text("Zone")
                } footer: {
                    Text("Ogni zona è una combinazione da inserire. Scorri a sinistra su una zona per eliminarla.")
                }

                Section {
                    preview
                } header: {
                    Text("Anteprima SMS")
                }

                if !target.isNew {
                    Section {
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Label("Elimina casa", systemImage: "trash")
                        }
                    } footer: {
                        Text("Elimina anche lo storico dei comandi di questa casa.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(m3.surface)
            .navigationTitle(target.isNew ? "Nuova casa" : "Modifica casa")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        draft.name = draft.name.trimmingCharacters(in: .whitespaces)
                        model.save(house: draft, password: password)
                        dismiss()
                    }
                    .disabled(!canSave)
                    .fontWeight(.semibold)
                }
            }
            .sheet(item: $editingZone) { target in
                ZoneEditorView(target: target, password: password, template: draft.messageTemplate) { zone in
                    if let i = draft.zones.firstIndex(where: { $0.id == zone.id }) {
                        draft.zones[i] = zone
                    } else {
                        draft.zones.append(zone)
                    }
                } onDelete: { id in
                    draft.zones.removeAll { $0.id == id }
                }
            }
            .confirmationDialog("Eliminare \(draft.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Elimina casa e storico", role: .destructive) {
                    model.deleteHouse(draft.id)
                    dismiss()
                }
            }
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            previewLine("Disinserisci", MessageBuilder.masked(command: draft.disarmCommand, password: password, template: draft.messageTemplate))
            ForEach(draft.zones) { z in
                previewLine(z.name, MessageBuilder.masked(command: z.command, password: password, template: draft.messageTemplate))
            }
            if draft.supportsStatus {
                previewLine("Stato", MessageBuilder.masked(command: draft.statusCommand, password: password, template: draft.messageTemplate))
            }
            Text("A: \(draft.phoneNumber.isEmpty ? "numero mancante" : draft.phoneNumber)")
                .font(.m3LabelMedium)
                .foregroundStyle(draft.phoneNumber.isEmpty ? m3.error : m3.onSurfaceVariant)
        }
        .padding(.vertical, 4)
    }

    private func previewLine(_ label: String, _ text: String) -> some View {
        HStack {
            Text(label)
                .font(.m3LabelLarge)
                .foregroundStyle(m3.onSurfaceVariant)
            Spacer()
            Text(text)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(m3.onSurface)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(m3.surfaceContainerHigh, in: Capsule())
        }
    }
}

struct ZoneRow: View {
    @Environment(\.m3) private var m3
    let zone: Zone

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(icon: zone.icon, tones: m3.tones(zone.colorHex), size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(zone.name.isEmpty ? "Senza nome" : zone.name)
                    .font(.m3TitleSmall)
                    .foregroundStyle(m3.onSurface)
                Text(zone.command)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(m3.onSurfaceVariant)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(m3.outline)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Zone editor

enum ZoneEditorTarget: Identifiable {
    case new(Zone)
    case edit(Zone)

    var id: UUID {
        switch self {
        case .new(let z), .edit(let z): return z.id
        }
    }

    var zone: Zone {
        switch self {
        case .new(let z), .edit(let z): return z
        }
    }

    var isNew: Bool {
        if case .new = self { return true }
        return false
    }
}

struct ZoneEditorView: View {
    @Environment(\.m3) private var m3
    @Environment(\.dismiss) private var dismiss

    let target: ZoneEditorTarget
    let password: String
    let template: String
    let onSave: (Zone) -> Void
    let onDelete: (UUID) -> Void
    @State private var draft: Zone

    init(target: ZoneEditorTarget, password: String, template: String, onSave: @escaping (Zone) -> Void, onDelete: @escaping (UUID) -> Void) {
        self.target = target
        self.password = password
        self.template = template
        self.onSave = onSave
        self.onDelete = onDelete
        _draft = State(initialValue: target.zone)
    }

    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !draft.command.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nome (es. Notte, Fuori casa)", text: $draft.name)
                        .font(.m3TitleMedium)
                    LabeledContent {
                        TextField("attiva 1-2-3", text: $draft.command)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                            .font(.system(.body, design: .monospaced))
                    } label: {
                        Label("Combinazione", systemImage: "number")
                    }
                } header: {
                    Text("Zona")
                } footer: {
                    Text("SMS inviato: \(MessageBuilder.masked(command: draft.command, password: password, template: template))")
                        .font(.system(.footnote, design: .monospaced))
                }
                Section("Icona") {
                    IconPicker(icons: Catalog.zoneIcons, selection: $draft.icon, colorHex: draft.colorHex)
                }
                Section("Colore") {
                    ColorPickerRow(selection: $draft.colorHex)
                }
                if !target.isNew {
                    Section {
                        Button(role: .destructive) {
                            onDelete(draft.id)
                            dismiss()
                        } label: {
                            Label("Elimina zona", systemImage: "trash")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(m3.surface)
            .navigationTitle(target.isNew ? "Nuova zona" : "Modifica zona")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fatto") {
                        draft.name = draft.name.trimmingCharacters(in: .whitespaces)
                        draft.command = draft.command.trimmingCharacters(in: .whitespaces)
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(!canSave)
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
    }
}
