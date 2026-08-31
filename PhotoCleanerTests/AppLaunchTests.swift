import XCTest
@testable import PhotoCleaner

final class AppLaunchTests: XCTestCase {
    @MainActor
    func testRootViewCanBeConstructed() {
        _ = RootView()
    }
}
