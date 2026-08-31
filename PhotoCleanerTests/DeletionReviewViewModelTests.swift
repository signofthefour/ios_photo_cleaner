import XCTest
@testable import PhotoCleaner

@MainActor
final class DeletionReviewViewModelTests: XCTestCase {
    func testRestoreRemovesOnlyRequestedIdentifierAndSavesQueue() async throws {
        let repository = InMemorySessionRepository(initial: .fixturePendingDeletion(ids: ["a", "b"]))
        let model = DeletionReviewViewModel(sessions: repository)

        await model.load()
        try await model.restore(id: "a")

        XCTAssertEqual(model.pendingIDs, ["b"])
        let saved = try await repository.loadCurrent()
        XCTAssertEqual(saved?.pendingDeletionIDs, ["b"])
    }

    func testCancelRetainsQueue() async throws {
        let repository = InMemorySessionRepository(initial: .fixturePendingDeletion(ids: ["a"]))
        let model = DeletionReviewViewModel(sessions: repository)

        await model.load()
        model.cancel()

        let saved = try await repository.loadCurrent()
        XCTAssertEqual(saved?.pendingDeletionIDs, ["a"])
    }
}
