import SwiftUI
import AlarmCore

enum AppTab: Hashable {
    case home, history, stats, settings
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    @State private var tab: AppTab = .home

    var body: some View {
        @Bindable var model = model
        TabView(selection: $tab) {
            Tab("Antifurto", systemImage: "shield.lefthalf.filled", value: AppTab.home) {
                NavigationStack { HomeView() }
            }
            Tab("Storico", systemImage: "clock.arrow.circlepath", value: AppTab.history) {
                NavigationStack { HistoryView() }
            }
            Tab("Statistiche", systemImage: "chart.bar.xaxis", value: AppTab.stats) {
                NavigationStack { StatsView() }
            }
            Tab("Impostazioni", systemImage: "gearshape.fill", value: AppTab.settings) {
                NavigationStack { SettingsView() }
            }
        }
        .sheet(item: $model.compose) { request in
            MessageComposeView(recipient: request.command.recipient, body: request.command.body) { result in
                model.composeFinished(request, result: result)
            }
            .ignoresSafeArea()
            .interactiveDismissDisabled()
        }
        .sheet(item: $model.confirm) { request in
            ConfirmSheet(request: request)
                .presentationDetents([.height(340)])
                .presentationCornerRadius(32)
        }
        .alert("Attenzione", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .overlay(alignment: .top) {
            if let toast = model.toast {
                ToastView(toast: toast)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { model.toast = nil }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.toast)
        .sensoryFeedback(.success, trigger: model.sentCounter)
    }
}

/// Optional confirmation before opening the SMS composer.
private struct ConfirmSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    let request: ConfirmRequest

    var body: some View {
        let cmd = request.command
        let tones = m3.tones(for: cmd.kind)
        VStack(spacing: 18) {
            IconBadge(icon: cmd.kind == .disarm ? "shield.slash.fill" : (cmd.zone?.icon ?? "questionmark.bubble.fill"),
                      tones: tones, size: 64, cookie: true)
            VStack(spacing: 6) {
                Text(cmd.title)
                    .font(.m3TitleLarge)
                    .foregroundStyle(m3.onSurface)
                Text("\(cmd.house.name) · \(cmd.recipient)")
                    .font(.m3BodyMedium)
                    .foregroundStyle(m3.onSurfaceVariant)
                Text(cmd.maskedBody)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(m3.onSurfaceVariant)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(m3.surfaceContainerHigh, in: Capsule())
            }
            HStack(spacing: 12) {
                PillButton(title: "Annulla", icon: "xmark", tones: m3.neutral, filled: false, height: 54) {
                    model.confirm = nil
                }
                PillButton(title: "Prepara SMS", icon: "paperplane.fill", tones: tones, height: 54) {
                    model.confirmAndSend(request)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(m3.surfaceContainerLow)
    }
}
