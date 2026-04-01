import SwiftUI

struct RootNavigationView: View {
    @State private var path: [AppRoute] = []
    @Environment(\.dependencies) private var dependencies

    var body: some View {
        NavigationStack(path: $path) {
            DateRangePickerView(onStartScan: { dateRange in
                path.append(.scan(dateRange))
            })
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .dateRangePicker:
                    DateRangePickerView(onStartScan: { dateRange in
                        path.append(.scan(dateRange))
                    })

                case .scan(let dateRange):
                    ScanView(dateRange: dateRange, onComplete: {
                        path.append(.review(threshold: 0.92))
                    })

                case .review(let threshold):
                    SwipeReviewView(threshold: threshold, onFinished: {
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
