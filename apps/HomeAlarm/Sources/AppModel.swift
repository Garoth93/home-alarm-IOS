import SwiftUI
import UIKit
import AlarmCore
import WidgetKit
import MessageUI
import LocalAuthentication

/// A command waiting for the SMS composer.
struct ComposeRequest: Identifiable {
    let id = UUID()
    let command: ResolvedCommand
    let source: EventSource
}

/// A command waiting for the user's confirmation (setting "Chiedi conferma").
struct ConfirmRequest: Identifiable {
    let id = UUID()
    let command: ResolvedCommand
    let source: EventSource
}

struct Toast: Identifiable, Equatable {
    enum Style { case success, info, error }
    let id = UUID()
    let message: String
    let icon: String
    let style: Style
}

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    private(set) var data: AlarmData
    /// House shown in the Home tab.
    var selectedHouseID: UUID?
    var compose: ComposeRequest?
    var confirm: ConfirmRequest?
    var toast: Toast?
    var errorMessage: String?
    /// Bumped after every SMS sent (drives haptics).
    private(set) var sentCounter = 0
    /// Link received before the UI was ready.
    private var queuedLink: DeepLink?
    private(set) var isActive = false

    private let vault = PasswordVault()

    private init() {
        data = SharedStore.load()
        selectedHouseID = data.defaultHouse?.id
    }

    // MARK: Derived

    var houses: [House] { data.houses }
    var settings: AppSettings { data.settings }

    var selectedHouse: House? {
        if let id = selectedHouseID, let h = data.houses.first(where: { $0.id == id }) { return h }
        return data.defaultHouse
    }

    func state(for house: House) -> HouseState { data.state(for: house.id) }

    func house(_ id: UUID) -> House? { data.houses.first { $0.id == id } }

    // MARK: Persistence

    private func persist() {
        do {
            try SharedStore.store.save(data)
        } catch {
            errorMessage = "Salvataggio non riuscito: \(error.localizedDescription)"
        }
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadAllControls()
        AlarmShortcuts.updateAppShortcutParameters()
    }

    func reloadFromDisk() {
        data = SharedStore.load()
    }

    // MARK: Houses

    func password(for houseID: UUID) -> String {
        vault.password(for: houseID) ?? ""
    }

    func save(house: House, password: String) {
        data.upsert(house)
        if !vault.setPassword(password, for: house.id) {
            errorMessage = "Non riesco a salvare la password nel portachiavi."
        }
        if selectedHouseID == nil || data.houses.count == 1 { selectedHouseID = house.id }
        persist()
    }

    func deleteHouse(_ id: UUID) {
        data.removeHouse(id)
        vault.setPassword("", for: id)
        if selectedHouseID == id { selectedHouseID = data.defaultHouse?.id }
        persist()
    }

    func moveHouses(from source: IndexSet, to destination: Int) {
        data.houses.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    // MARK: Settings

    func updateSettings(_ change: (inout AppSettings) -> Void) {
        change(&data.settings)
        persist()
    }

    // MARK: History

    func deleteEvents(_ ids: Set<UUID>) {
        data.events.removeAll { ids.contains($0.id) }
        persist()
    }

    func clearHistory() {
        data.events.removeAll()
        persist()
    }

    /// Corrects the assumed state without sending an SMS.
    func markState(houseID: UUID, armedZone: Zone?) {
        let event = AlarmEvent(
            houseID: houseID, zoneID: armedZone?.id, zoneName: armedZone?.name,
            kind: armedZone == nil ? .disarm : .arm, result: .sent, source: .manual,
            message: "Correzione manuale")
        data.record(event)
        persist()
        show("Stato aggiornato", icon: "checkmark", style: .info)
    }

    // MARK: Backup

    func makeBackup(includePasswords: Bool) -> BackupFile {
        var pw: [UUID: String] = [:]
        if includePasswords {
            for h in data.houses { if let p = vault.password(for: h.id), !p.isEmpty { pw[h.id] = p } }
        }
        return BackupFile(data: data, passwords: pw)
    }

    func restore(_ backup: BackupFile) {
        for h in data.houses where !backup.data.houses.contains(where: { $0.id == h.id }) {
            vault.setPassword("", for: h.id)
        }
        data = backup.data
        for (id, p) in backup.passwordsByHouse { vault.setPassword(p, for: id) }
        selectedHouseID = data.defaultHouse?.id
        persist()
        show("Backup ripristinato", icon: "arrow.down.doc.fill", style: .success)
    }

    // MARK: Commands

    func setActive(_ active: Bool) {
        isActive = active
        guard active else { return }
        reloadFromDisk()
        if let pending = SharedStore.takePending() { queuedLink = pending }
        if let link = queuedLink {
            queuedLink = nil
            // Give the scene a moment before presenting the composer.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                self.handle(link)
            }
        }
    }

    func handle(url: URL) {
        guard let link = DeepLink(url: url) else { return }
        handle(link)
    }

    func handle(_ link: DeepLink) {
        guard isActive else {
            queuedLink = link
            return
        }
        switch link {
        case .open(let house):
            if let house { selectedHouseID = house }
        case .run(let ref, let source):
            if let h = ref.houseID ?? data.defaultHouse?.id { selectedHouseID = h }
            request(ref, source: source)
        }
    }

    /// Entry point of every command (buttons, widgets, controls, Siri).
    func request(_ ref: AlarmActionRef, source: EventSource) {
        let houseID = data.house(ref.houseID)?.id
        let pass = houseID.map { password(for: $0) }
        switch data.resolve(ref, password: pass) {
        case .failure(let error):
            errorMessage = error.message
        case .success(let command):
            Task { @MainActor in
                if command.kind == .disarm, data.settings.requireAuthForDisarm {
                    guard await authenticate(reason: "Conferma per disinserire l'antifurto di \(command.house.name).") else { return }
                }
                if data.settings.confirmBeforeSending && source == .app {
                    confirm = ConfirmRequest(command: command, source: source)
                } else {
                    present(command, source: source)
                }
            }
        }
    }

    func confirmAndSend(_ request: ConfirmRequest) {
        confirm = nil
        present(request.command, source: request.source)
    }

    private func present(_ command: ResolvedCommand, source: EventSource) {
        if MFMessageComposeViewController.canSendText() {
            compose = ComposeRequest(command: command, source: source)
        } else if let url = MessageBuilder.smsURL(number: command.recipient, body: command.body) {
            // No in-app composer (e.g. iMessage off): hand over to Messages.
            UIApplication.shared.open(url)
            finish(command, source: source, result: .sent)
        } else {
            errorMessage = "Questo dispositivo non può inviare SMS."
        }
    }

    func composeFinished(_ request: ComposeRequest, result: MessageComposeResult) {
        compose = nil
        let r: EventResult
        switch result {
        case .sent: r = .sent
        case .cancelled: r = .cancelled
        case .failed: r = .failed
        @unknown default: r = .failed
        }
        finish(request.command, source: request.source, result: r)
    }

    private func finish(_ command: ResolvedCommand, source: EventSource, result: EventResult) {
        data.record(command.event(result: result, source: source))
        persist()
        switch result {
        case .sent:
            sentCounter += 1
            let text: String
            switch command.kind {
            case .arm: text = "\(command.zone?.name ?? "Zona") inserita"
            case .disarm: text = "Antifurto disinserito"
            case .status: text = "Richiesta stato inviata"
            }
            show(text, icon: command.kind == .disarm ? "shield.slash.fill" : "checkmark.shield.fill", style: .success)
        case .cancelled:
            show("Invio annullato", icon: "xmark", style: .info)
        case .failed:
            show("Invio non riuscito", icon: "exclamationmark.triangle.fill", style: .error)
        }
    }

    func show(_ message: String, icon: String, style: Toast.Style) {
        let t = Toast(message: message, icon: icon, style: style)
        toast = t
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.6))
            if self.toast == t { self.toast = nil }
        }
    }

    // MARK: Authentication

    private func authenticate(reason: String) async -> Bool {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { return true }
        do {
            return try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }
}
