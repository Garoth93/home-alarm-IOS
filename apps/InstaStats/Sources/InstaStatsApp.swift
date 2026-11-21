import SwiftUI
import InstaCore

@main
struct InstaStatsApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ThemedRoot()
                .environment(model)
                .onOpenURL { url in
                    // ZIP shared from Files / Safari / Mail ("Apri con instaStats")
                    if url.isFileURL { model.importFiles([url]) }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.saveNow() }
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
