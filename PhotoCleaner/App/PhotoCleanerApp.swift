import SwiftUI

@main
struct PhotoCleanerApp: App {
    private let container = AppContainer.liveMock

    var body: some Scene {
        WindowGroup {
            RootView(container: container)
        }
    }
}
