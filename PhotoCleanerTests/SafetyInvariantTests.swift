import XCTest
@testable import PhotoCleaner

@MainActor
final class SafetyInvariantTests: XCTestCase {
    func testNonConfirmationActionsNeverDeleteAssets() async throws {
        let library = MockPhotoLibraryService.sample
        let repository = InMemorySessionRepository()
        let source = CleaningSource.album(.init(id: "album", title: "Mock Album", photoCount: 3))
        let cleaner = CleanerViewModel(source: source, library: library, sessions: repository)

        await cleaner.load()
        await cleaner.loadCurrentPreview(pixelWidth: 600, pixelHeight: 600)
        await cleaner.keepCurrent()
        await cleaner.loadCurrentPreview(pixelWidth: 600, pixelHeight: 600)
        await cleaner.queueCurrentForDeletion()
        cleaner.undo()
        await cleaner.queueCurrentForDeletion()
        try await cleaner.save()

        let review = DeletionReviewViewModel(sessions: repository)
        await review.load()
        review.selectAll()
        review.deselectAll()
        review.cancel()
        if let first = review.pendingIDs.first {
            try await review.restore(id: first)
        }

        let deletedBatches = await library.deletedIDBatches
        XCTAssertTrue(deletedBatches.isEmpty)
    }
}
