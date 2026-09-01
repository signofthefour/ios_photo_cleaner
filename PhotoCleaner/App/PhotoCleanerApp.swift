import SwiftUI

@main
struct PhotoCleanerApp: App {
    private let container = AppContainer.live

    var body: some Scene {
        WindowGroup {
            RootView(container: container)
        }
    }
}
