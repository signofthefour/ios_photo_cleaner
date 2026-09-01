import XCTest
@testable import PhotoCleaner

@MainActor
final class DeletionReviewViewModelTests: XCTestCase {
    func testRestoreRemovesOnlyRequestedIdentifierAndSavesQueue() async throws {
        let repository = InMemorySessionRepository(initial: .fixturePendingDeletion(ids: ["a", "b"]))
        let model = DeletionReviewViewModel(library: MockPhotoLibraryService.sample, sessions: repository)

        await model.load()
        try await model.restore(id: "a")

        XCTAssertEqual(model.pendingIDs, ["b"])
        let saved = try await repository.loadCurrent()
        XCTAssertEqual(saved?.pendingDeletionIDs, ["b"])
    }

    func testRestoreAllClearsQueueAndSavesSessionRegardlessOfSelection() async throws {
        let repository = InMemorySessionRepository(initial: .fixturePendingDeletion(ids: ["a", "b"]))
        let model = DeletionReviewViewModel(library: MockPhotoLibraryService.sample, sessions: repository)

        await model.load()
        model.deselectAll()
        try await model.restoreAll()

        XCTAssertTrue(model.pendingIDs.isEmpty)
        XCTAssertTrue(model.selectedIDs.isEmpty)
        let saved = try await repository.loadCurrent()
        XCTAssertEqual(saved?.pendingDeletionIDs, [])
    }

    func testCancelRetainsQueue() async throws {
        let repository = InMemorySessionRepository(initial: .fixturePendingDeletion(ids: ["a"]))
        let model = DeletionReviewViewModel(library: MockPhotoLibraryService.sample, sessions: repository)

        await model.load()
        model.cancel()

        let saved = try await repository.loadCurrent()
        XCTAssertEqual(saved?.pendingDeletionIDs, ["a"])
    }

    func testLoadPreviewsPopulatesThumbnailsForPendingIDs() async throws {
        let library = MockPhotoLibraryService.sample
        let repository = InMemorySessionRepository(initial: .fixturePendingDeletion(ids: ["asset-1", "asset-2"]))
        let model = DeletionReviewViewModel(library: library, sessions: repository)

        await model.load()
        XCTAssertNil(model.preview(for: "asset-1"))

        await model.loadPreviews(pixelWidth: 300, pixelHeight: 300)

        XCTAssertEqual(model.preview(for: "asset-1")?.content, .systemSymbol("photo"))
        XCTAssertEqual(model.preview(for: "asset-2")?.content, .systemSymbol("photo.fill"))
    }

    func testLoadPreviewsLeavesMissingPreviewUnavailableWithoutBlockingRestore() async throws {
        let library = MockPhotoLibraryService.sample
        let repository = InMemorySessionRepository(initial: .fixturePendingDeletion(ids: ["no-preview-asset"]))
        let model = DeletionReviewViewModel(library: library, sessions: repository)

        await model.load()
        await model.loadPreviews(pixelWidth: 300, pixelHeight: 300)

        XCTAssertNil(model.preview(for: "no-preview-asset"))
        try await model.restore(id: "no-preview-asset")
        XCTAssertTrue(model.pendingIDs.isEmpty)
    }

    func testConfirmDeletionRemovesSucceededAssetsFromQueueAndSession() async throws {
        let library = MockPhotoLibraryService.sample
        let repository = InMemorySessionRepository(initial: .fixturePendingDeletion(ids: ["a", "b"]))
        let model = DeletionReviewViewModel(library: library, sessions: repository)

        await model.load()
        await model.confirmDeletion()

        let deletedBatches = await library.deletedIDBatches
        XCTAssertEqual(deletedBatches.count, 1)
        XCTAssertEqual(Set(deletedBatches[0]), ["a", "b"])
        XCTAssertTrue(model.pendingIDs.isEmpty)
        XCTAssertTrue(model.selectedIDs.isEmpty)
        XCTAssertEqual(model.deletionSummaryMessage, "2 photos deleted.")
        let saved = try await repository.loadCurrent()
        XCTAssertEqual(saved?.pendingDeletionIDs, [])
    }

    /// The "unavailable-asset handling" part of Milestone 5's scope: an id
    /// that disappears from the library between being queued and being
    /// confirmed (deleted elsewhere) is treated as already-deleted rather
    /// than an error, so the whole batch still succeeds and every
    /// originally-selected id resolves out of the pending queue.
    func testConfirmDeletionResolvesAnIDThatAlreadyDisappearedFromTheLibrary() async throws {
        let library = MockPhotoLibraryService.sample
        await library.setMissingAssetIDs(["a"])
        let repository = InMemorySessionRepository(initial: .fixturePendingDeletion(ids: ["a", "b"]))
        let model = DeletionReviewViewModel(library: library, sessions: repository)

        await model.load()
        await model.confirmDeletion()

        let deletedBatches = await library.deletedIDBatches
        XCTAssertEqual(deletedBatches, [["b"]])
        XCTAssertTrue(model.pendingIDs.isEmpty)
        XCTAssertNil(model.deletionErrorMessage)
        XCTAssertEqual(model.deletionSummaryMessage, "2 photos deleted.")
        let saved = try await repository.loadCurrent()
        XCTAssertEqual(saved?.pendingDeletionIDs, [])
    }

    func testConfirmDeletionSucceedsWhenEveryQueuedIDHasAlreadyDisappeared() async throws {
        let library = MockPhotoLibraryService.sample
        await library.setMissingAssetIDs(["a", "b"])
        let repository = InMemorySessionRepository(initial: .fixturePendingDeletion(ids: ["a", "b"]))
        let model = DeletionReviewViewModel(library: library, sessions: repository)

        await model.load()
        await model.confirmDeletion()

        let deletedBatches = await library.deletedIDBatches
        XCTAssertTrue(deletedBatches.isEmpty)
        XCTAssertTrue(model.pendingIDs.isEmpty)
        XCTAssertNil(model.deletionErrorMessage)
        let saved = try await repository.loadCurrent()
        XCTAssertEqual(saved?.pendingDeletionIDs, [])
    }

    func testFailedDeletionLeavesQueueAndSessionUnchanged() async throws {
        let library = MockPhotoLibraryService.sample
        await library.setForcedError(.forcedFailure)
        let repository = InMemorySessionRepository(initial: .fixturePendingDeletion(ids: ["a", "b"]))
        let model = DeletionReviewViewModel(library: library, sessions: repository)

        await model.load()
        await model.confirmDeletion()

        let deletedBatches = await library.deletedIDBatches
        XCTAssertTrue(deletedBatches.isEmpty)
        XCTAssertEqual(model.pendingIDs, ["a", "b"])
        XCTAssertEqual(model.selectedIDs, Set(["a", "b"]))
        XCTAssertEqual(model.deletionErrorMessage, "These photos could not be deleted. Please try again.")
        let saved = try await repository.loadCurrent()
        XCTAssertEqual(saved?.pendingDeletionIDs, ["a", "b"])
    }

    func testConfirmDeletionDoesNothingWhenNoneSelected() async throws {
        let library = MockPhotoLibraryService.sample
        let repository = InMemorySessionRepository(initial: .fixturePendingDeletion(ids: ["a"]))
        let model = DeletionReviewViewModel(library: library, sessions: repository)

        await model.load()
        model.deselectAll()
        await model.confirmDeletion()

        let deletedBatches = await library.deletedIDBatches
        XCTAssertTrue(deletedBatches.isEmpty)
        XCTAssertEqual(model.pendingIDs, ["a"])
    }
}
