import XCTest
@testable import PhotoCleaner

@MainActor
final class HomeViewModelTests: XCTestCase {
    func testLoadShowsAccessAndSavedSession() async {
        let library = MockPhotoLibraryService.sample
        let repository = InMemorySessionRepository(initial: .fixture(assetIDs: ["a"]))
        let model = HomeViewModel(library: library, sessions: repository)

        await model.load()

        XCTAssertEqual(model.accessStatus, .limited)
        XCTAssertNotNil(model.savedSession)
    }

    func testCompletedSessionIsNotOfferedAsContinueButPendingDeletionStillCounts() async {
        let library = MockPhotoLibraryService.sample
        let repository = InMemorySessionRepository(initial: .fixturePendingDeletion(ids: ["a", "b"]))
        let model = HomeViewModel(library: library, sessions: repository)

        await model.load()

        XCTAssertNil(model.savedSession)
        XCTAssertEqual(model.pendingDeletionCount, 2)
    }

    func testRoutesRemainStronglyTyped() {
        let router = AppRouter()

        router.navigate(to: .sourcePicker)

        XCTAssertEqual(router.path, [.sourcePicker])
    }
}
