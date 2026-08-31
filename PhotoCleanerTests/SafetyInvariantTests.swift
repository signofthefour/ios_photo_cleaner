import Foundation
import XCTest
@testable import PhotoCleaner

@MainActor
final class SafetyInvariantTests: XCTestCase {
    func testNonConfirmationActionsNeverDeleteAssets() async throws {
        let library = MockPhotoLibraryService.sample
        let repository = InMemorySessionRepository()
        let source = CleaningSource.album(.init(id: "album", title: "Mock Album", photoCount: 3))
        let cleaner = CleanerViewModel(source: source, library: library, sessions: repository)
        let undecodablePreview = LocalPhotoPreview(
            content: .encodedImageData(Data("not image data".utf8)),
            isDegraded: false
        )

        await library.setPreview(undecodablePreview, for: "asset-1")
        await cleaner.load()
        await cleaner.loadCurrentPreview(pixelWidth: 600, pixelHeight: 600)
        XCTAssertEqual(cleaner.currentPreview, undecodablePreview)
        await cleaner.keepCurrent()
        await cleaner.loadCurrentPreview(pixelWidth: 600, pixelHeight: 600)
        await cleaner.queueCurrentForDeletion()
        cleaner.undo()
        await cleaner.queueCurrentForDeletion()
        let shouldDismiss = await cleaner.saveForExit()
        XCTAssertTrue(shouldDismiss)

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
