import SwiftUI
import InstaCore

enum AppTab: Hashable {
    case overview, lists, review, settings
}

/// Navigation targets shared by the tabs.
enum Route: Hashable {
    case list(ListKind)
    case snapshots
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    @State private var tab: AppTab = .overview

    var body: some View {
        TabView(selection: $tab) {
            Tab("Panoramica", systemImage: "chart.pie.fill", value: AppTab.overview) {
                NavigationStack { OverviewView(tab: $tab).withRoutes() }
            }
            Tab("Liste", systemImage: "person.2.fill", value: AppTab.lists) {
                NavigationStack { ListsView().withRoutes() }
            }
            Tab("Rivedi", systemImage: "rectangle.stack.fill", value: AppTab.review) {
                NavigationStack { ReviewView() }
            }
            Tab("Altro", systemImage: "gearshape.fill", value: AppTab.settings) {
                NavigationStack { SettingsView().withRoutes() }
            }
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
                ToastView(toast: toast) { model.undo() }
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay {
            if model.importing {
                ZStack {
                    Color.black.opacity(0.25).ignoresSafeArea()
                    VStack(spacing: 14) {
                        ProgressView().controlSize(.large)
                        Text("Leggo l'export…").font(.m3TitleSmall).foregroundStyle(m3.onSurface)
                    }
                    .padding(28)
                    .background(m3.surfaceContainerHigh, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.toast)
        .animation(.easeInOut(duration: 0.2), value: model.importing)
    }
}

extension View {
    /// Destinations reachable from any tab.
    func withRoutes() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .list(let kind): AccountListView(kind: kind)
            case .snapshots: SnapshotsView()
            }
        }
    }
}
