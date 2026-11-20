import Foundation
import AlarmCore

/// Where the app and the widgets keep `AlarmData`.
///
/// Both read the same JSON file inside the App Group container. The real
/// group id is read from the provisioning profile, because free-account
/// signers (Sideloadly / SideStore) may rename it. Without an App Group the
/// app falls back to its own Application Support folder and the widgets show
/// generic actions only.
enum SharedStore {
    static let configuredGroup = "group.com.garoth93.homealarm"
    static let fileName = "alarm-data.json"

    /// The App Group actually available to this process, if any.
    static let groupID: String? = {
        var candidates: [String] = []
        if let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
           let data = try? Data(contentsOf: url) {
            candidates = ProvisioningProfile.appGroups(from: data)
        }
        if let declared = Bundle.main.object(forInfoDictionaryKey: "HAAppGroup") as? String, !declared.isEmpty {
            candidates.append(declared)
        }
        candidates.append(configuredGroup)
        var seen = Set<String>()
        let ordered = candidates.filter { seen.insert($0).inserted }
        let preferred = ProvisioningProfile.pickGroup(configured: configuredGroup, available: ordered)
        for id in [preferred].compactMap({ $0 }) + ordered {
            if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) != nil { return id }
        }
        return nil
    }()

    static var containerURL: URL? {
        groupID.flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
    }

    static var isShared: Bool { containerURL != nil }

    static var localURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(fileName)
    }

    static var dataURL: URL {
        containerURL?.appendingPathComponent(fileName) ?? localURL
    }

    static var store: JSONFileStore<AlarmData> { JSONFileStore(url: dataURL) }

    static func load() -> AlarmData {
        if let data = try? store.load() { return data }
        // First launch with an App Group: migrate a local file if present.
        if isShared, let local = try? JSONFileStore<AlarmData>(url: localURL).load() {
            return local
        }
        return AlarmData()
    }

    static var defaults: UserDefaults {
        groupID.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    // MARK: Pending command (from a control / Siri running outside the app)

    private static let pendingKey = "pendingDeepLink"
    private static let pendingDateKey = "pendingDeepLinkDate"

    static func setPending(_ link: DeepLink) {
        defaults.set(link.url.absoluteString, forKey: pendingKey)
        defaults.set(Date().timeIntervalSince1970, forKey: pendingDateKey)
    }

    /// Returns (and clears) a pending link created in the last 2 minutes.
    static func takePending() -> DeepLink? {
        let d = defaults
        guard let s = d.string(forKey: pendingKey) else { return nil }
        let t = d.double(forKey: pendingDateKey)
        d.removeObject(forKey: pendingKey)
        d.removeObject(forKey: pendingDateKey)
        guard Date().timeIntervalSince1970 - t < 120, let url = URL(string: s) else { return nil }
        return DeepLink(url: url)
    }
}
