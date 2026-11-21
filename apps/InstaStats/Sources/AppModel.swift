import SwiftUI
import UIKit
import InstaCore

@MainActor
@Observable
final class AppModel {
    private(set) var data: InstaData
    private(set) var owner: String = ""
    private(set) var currentID: UUID?
    private(set) var compareID: UUID?
    private(set) var analysis: Analysis = .empty
    /// Bumped at every change of the analysis (lists observe it).
    private(set) var revision = 0

    var importing = false
    var toast: Toast?
    var errorMessage: String?
    /// Profiles opened on Instagram in this session.
    private(set) var opened: Set<String> = []

    private struct UndoGroup { var owner: String; var items: [(user: String, previous: MarkState)] }
    private var undoStack: [UndoGroup] = []
    var canUndo: Bool { !undoStack.isEmpty }

    private var saveTask: Task<Void, Never>?

    private static var storeURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("instastats.json")
    }

    private var store: JSONFileStore<InstaData> { JSONFileStore(url: Self.storeURL) }

    init() {
        data = (try? JSONFileStore<InstaData>(url: Self.storeURL).load()) ?? InstaData()
        let owners = data.owners
        let last = data.settings.lastOwner
        if let o = (last.flatMap { owners.contains($0) ? $0 : nil }) ?? owners.first {
            loadOwner(o)
        }
    }

    // MARK: Derived

    var hasData: Bool { !data.snapshots.isEmpty }
    var owners: [String] { data.owners }
    var snapshots: [Snapshot] { data.snapshots(of: owner) }
    var current: Snapshot? { analysis.current }
    var compare: Snapshot? { analysis.compare }
    var settings: InstaSettings { data.settings }

    // MARK: Loading

    func loadOwner(_ o: String, select: UUID? = nil) {
        owner = o
        data.settings.lastOwner = o
        let snaps = data.snapshots(of: o)
        currentID = nil
        compareID = nil
        if !snaps.isEmpty {
            let idx = snaps.firstIndex { $0.id == select } ?? snaps.count - 1
            currentID = snaps[idx].id
            compareID = idx > 0 ? snaps[idx - 1].id : nil
        }
        undoStack.removeAll()
        recompute()
    }

    func selectCurrent(_ id: UUID) {
        guard id != currentID else { return }
        currentID = id
        if compareID == id {
            let snaps = snapshots
            if let i = snaps.firstIndex(where: { $0.id == id }) { compareID = i > 0 ? snaps[i - 1].id : nil }
        }
        recompute()
    }

    func selectCompare(_ id: UUID?) {
        guard id != currentID else { return }
        compareID = id
        recompute()
    }

    private func recompute() {
        analysis = Analysis(data: data, owner: owner, currentID: currentID, compareID: compareID)
        revision += 1
    }

    private func changed(recompute again: Bool = true) {
        if again { recompute() }
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = data
        let store = store
        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            do {
                try store.save(snapshot)
            } catch {
                await MainActor.run { self.errorMessage = "Salvataggio non riuscito: \(error.localizedDescription)" }
            }
        }
    }

    func saveNow() {
        saveTask?.cancel()
        try? store.save(data)
    }

    // MARK: Marks

    func setMark(_ users: [String], _ state: MarkState, announce: Bool = true) {
        var group = UndoGroup(owner: owner, items: [])
        for u in users {
            let prev = data.mark(owner, u).state
            guard prev != state else { continue }
            group.items.append((u, prev))
            data.setMark(owner, u, state: state)
        }
        guard !group.items.isEmpty else { return }
        undoStack.append(group)
        if undoStack.count > 200 { undoStack.removeFirst() }
        changed()
        if announce {
            let what = state == .keep ? "tenuti" : state == .unfollow ? "da smettere" : "senza segno"
            let msg = group.items.count == 1
                ? "@\(group.items[0].user): \(state == .keep ? "tenuto" : state == .unfollow ? "da smettere" : "segno tolto")"
                : "\(group.items.count) account segnati come \(what)"
            show(msg, icon: state == .keep ? "checkmark" : state == .unfollow ? "xmark" : "arrow.uturn.backward",
                 style: .info, canUndo: true)
        }
    }

    /// Same mark again removes it.
    func toggleMark(_ user: String, _ state: MarkState) {
        let cur = data.mark(owner, user).state
        setMark([user], cur == state ? .none : state)
    }

    func setNote(_ user: String, _ note: String) {
        guard data.mark(owner, user).note != note else { return }
        data.setNote(owner, user, note: note)
        changed()
    }

    @discardableResult
    func undo() -> String? {
        guard let g = undoStack.popLast() else { return nil }
        for item in g.items { data.setMark(g.owner, item.user, state: item.previous) }
        changed()
        toast = nil
        show(g.items.count == 1 ? "Annullato: @\(g.items[0].user)" : "Annullati \(g.items.count) segni", icon: "arrow.uturn.backward", style: .info)
        return g.items.last?.user
    }

    // MARK: Opening profiles

    func open(_ user: String) {
        opened.insert(user)
        guard let url = URL(string: "https://www.instagram.com/\(user)/") else { return }
        UIApplication.shared.open(url)
    }

    func isOpened(_ user: String) -> Bool { opened.contains(user) }

    func copy(_ users: [String]) {
        UIPasteboard.general.string = users.joined(separator: "\n")
        show(users.count == 1 ? "Copiato @\(users[0])" : "Copiati \(users.count) username", icon: "doc.on.doc", style: .info)
    }

    // MARK: Import

    func importFiles(_ urls: [URL]) {
        guard !importing, !urls.isEmpty else { return }
        importing = true
        Task {
            var messages: [String] = []
            var lastOwner: String?
            var lastID: UUID?
            for url in urls {
                let result: Result<ParsedExport, Error> = await Task.detached(priority: .userInitiated) {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    return Result { try ExportReader.read(url: url) }
                }.value
                switch result {
                case .failure(let error):
                    let msg = (error as? ExportError)?.message ?? error.localizedDescription
                    messages.append(urls.count > 1 ? "\(url.lastPathComponent): \(msg)" : msg)
                case .success(let parsed):
                    switch data.importExport(parsed, preferredOwner: owner.isEmpty ? nil : owner) {
                    case .duplicate(let id, let o):
                        lastOwner = o
                        lastID = id
                        messages.append("Questo export era già stato importato")
                    case .added(let id, let o, let resolved):
                        lastOwner = o
                        lastID = id
                        var msg = "Importati \(InstaFormat.number(parsed.count(.follower))) follower e \(InstaFormat.number(parsed.count(.following))) seguiti di @\(o)"
                        if resolved > 0 { msg += " · \(resolved) da smettere risultano fatti" }
                        messages.append(msg)
                    }
                }
            }
            importing = false
            if let lastOwner { loadOwner(lastOwner, select: lastID) }
            changed()
            let failed = lastOwner == nil
            if failed {
                errorMessage = messages.joined(separator: "\n")
            } else {
                show(messages.last ?? "Importato", icon: "tray.and.arrow.down.fill", style: .success)
                if messages.count > 1 { errorMessage = messages.joined(separator: "\n") }
            }
        }
    }

    func importDesktopDatabase(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let legacy = try DesktopDatabase.read(url: url)
            var added = 0
            for s in legacy.snapshots where data.merge(snapshot: s) { added += 1 }
            let marks = data.merge(marks: legacy.marks)
            let target = owner.isEmpty ? (legacy.snapshots.last?.owner ?? data.owners.first ?? "") : owner
            if !target.isEmpty { loadOwner(target) }
            changed()
            show("Da instaStats desktop: \(added) istantanee, \(marks) segni", icon: "desktopcomputer", style: .success)
        } catch {
            errorMessage = "Database non valido: \(error.localizedDescription)"
        }
    }

    // MARK: Snapshots & accounts

    func deleteSnapshot(_ id: UUID) {
        data.deleteSnapshot(id)
        if data.owners.contains(owner) {
            loadOwner(owner, select: id == currentID ? nil : currentID)
        } else if let first = data.owners.first {
            loadOwner(first)
        } else {
            owner = ""
            currentID = nil
            compareID = nil
            recompute()
        }
        changed(recompute: false)
        show("Istantanea eliminata", icon: "trash", style: .info)
    }

    func renameSnapshot(_ id: UUID, _ label: String) {
        data.renameSnapshot(id, label: label)
        changed()
    }

    func setSnapshotDate(_ id: UUID, _ date: Date) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        c.hour = 12
        data.setSnapshotDate(id, date: cal.date(from: c) ?? date)
        loadOwner(owner, select: currentID)
        changed(recompute: false)
    }

    /// Returns false when the name is not a valid username.
    func renameOwner(_ name: String) -> Bool {
        var n = name.trimmingCharacters(in: .whitespaces).lowercased()
        if n.hasPrefix("@") { n.removeFirst() }
        guard ExportReader.isValidUsername(n), n != owner else { return false }
        let merge = data.owners.contains(n)
        data.renameOwner(owner, to: n)
        loadOwner(n)
        changed(recompute: false)
        show(merge ? "Istantanee unite in @\(n)" : "Account rinominato in @\(n)", icon: "person.fill", style: .success)
        return true
    }

    func updateSettings(_ change: (inout InstaSettings) -> Void) {
        change(&data.settings)
        changed()
    }

    // MARK: Backup

    func backupJSON() -> String? {
        guard let d = try? JSONFileStore<InstaData>.encoder.encode(data) else { return nil }
        return String(data: d, encoding: .utf8)
    }

    func restore(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let raw = try Data(contentsOf: url)
            let restored = try JSONFileStore<InstaData>.decoder.decode(InstaData.self, from: raw)
            data = restored
            if let o = data.settings.lastOwner ?? data.owners.first { loadOwner(o) } else { owner = ""; recompute() }
            changed(recompute: false)
            show("Backup ripristinato", icon: "arrow.down.doc.fill", style: .success)
        } catch {
            errorMessage = "Backup non valido: \(error.localizedDescription)"
        }
    }

    func eraseAll() {
        data = InstaData(settings: data.settings)
        owner = ""
        currentID = nil
        compareID = nil
        undoStack.removeAll()
        recompute()
        scheduleSave()
    }

    // MARK: Toast

    func show(_ message: String, icon: String, style: Toast.Style, canUndo: Bool = false) {
        let t = Toast(message: message, icon: icon, style: style, canUndo: canUndo)
        toast = t
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(canUndo ? 3.5 : 2.6))
            if self.toast == t { self.toast = nil }
        }
    }
}
