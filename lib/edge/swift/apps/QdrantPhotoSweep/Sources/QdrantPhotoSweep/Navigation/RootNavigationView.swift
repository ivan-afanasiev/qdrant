import SwiftUI

struct RootNavigationView: View {
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ScanView()
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .settings:
                        SettingsView()
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            path.append(AppRoute.settings)
                        } label: {
                            Image(systemName: QIcons.settings)
                        }
                    }
                }
        }
        .tint(QColors.primary)
    }
}
