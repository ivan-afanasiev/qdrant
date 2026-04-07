import SwiftUI

struct RootNavigationView: View {
    @State private var path: [AppRoute] = []
    @Environment(\.dependencies) private var dependencies

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(
                onStartScan: { dateRange in
                    path.append(.scan(dateRange))
                },
                onResumeScan: { dateRange, sessionId in
                    path.append(.scan(dateRange, resumeSessionId: sessionId))
                },
                onReviewPending: {
                    path.append(.review)
                }
            )
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .scan(let dateRange, let resumeSessionId):
                    ScanView(dateRange: dateRange, resumeSessionId: resumeSessionId) {
                        path.removeAll()
                    }

                case .review:
                    SwipeReviewView(onFinished: {
                        path.removeAll()
                    })

                case .settings:
                    SettingsView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        path.append(.settings)
                    } label: {
                        Image(systemName: QIcons.settings)
                    }
                }
            }
        }
        .tint(QColors.primary)
    }
}
