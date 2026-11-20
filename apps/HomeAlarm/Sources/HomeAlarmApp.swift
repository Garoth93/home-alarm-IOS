import SwiftUI
import AlarmCore
import AppIntents

@main
struct HomeAlarmApp: App {
    @State private var model = AppModel.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ThemedRoot()
                .environment(model)
                .onOpenURL { url in model.handle(url: url) }
        }
        .onChange(of: scenePhase) { _, phase in
            model.setActive(phase == .active)
        }
    }
}

/// Builds the Material palette for the current light/dark appearance.
private struct ThemedRoot: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var systemScheme

    private var scheme: ColorScheme {
        switch model.settings.appearance {
        case .system: return systemScheme
        case .light: return .light
        case .dark: return .dark
        }
    }

    var body: some View {
        let theme = M3Theme(seed: Palette.defaultAccent, dark: scheme == .dark)
        RootView()
            .environment(\.m3, theme)
            .tint(theme.primary)
            .preferredColorScheme(model.settings.appearance == .system ? nil : scheme)
    }
}

/// Siri / Spotlight / Action button phrases.
struct AlarmShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RunAlarmActionIntent(),
            phrases: [
                "Comando \(.applicationName)",
                "Usa \(.applicationName)",
                "\(\.$action) con \(.applicationName)"
            ],
            shortTitle: "Comando antifurto",
            systemImageName: "shield.lefthalf.filled"
        )
    }
}
