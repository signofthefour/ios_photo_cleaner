import SwiftUI

@MainActor
struct RootView: View {
    private let container: AppContainer
    @State private var router = AppRouter()

    init(container: AppContainer = .liveMock) {
        self.container = container
    }

    var body: some View {
        NavigationStack(path: $router.path) {
            HomeView(model: container.makeHomeViewModel()) { route in
                router.navigate(to: route)
            }
            .navigationDestination(for: AppRoute.self) { route in
                destination(for: route)
            }
        }
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .sourcePicker:
            SourcePickerView(model: container.makeSourcePickerViewModel()) { source in
                router.navigate(to: .cleaner(source))
            }
        case let .cleaner(source):
            CleanerView(model: container.makeCleanerViewModel(source: source))
        case .deletionReview:
            DeletionReviewView(model: container.makeDeletionReviewViewModel())
        case .settings:
            SettingsView(model: container.makeSettingsViewModel())
        }
    }
}
