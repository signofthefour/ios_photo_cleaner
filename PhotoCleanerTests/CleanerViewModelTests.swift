import XCTest
@testable import PhotoCleaner

@MainActor
final class CleanerViewModelTests: XCTestCase {
    func testQueueAndUndoNeverCallDelete() async throws {
        let library = MockPhotoLibraryService.sample
        let repository = InMemorySessionRepository()
        let model = CleanerViewModel(
            source: .album(.init(id: "album", title: "Mock Album", photoCount: 3)),
            library: library,
            sessions: repository
        )

        await model.load()
        await model.queueCurrentForDeletion()
        model.undo()

        let deletedBatches = await library.deletedIDBatches
        XCTAssertTrue(deletedBatches.isEmpty)
        XCTAssertEqual(model.progressText, "1 of 3")
    }

    func testSaveCanBeLoadedByNewViewModel() async throws {
        let library = MockPhotoLibraryService.sample
        let repository = InMemorySessionRepository()
        let source = CleaningSource.album(.init(id: "album", title: "Mock Album", photoCount: 3))
        let first = CleanerViewModel(source: source, library: library, sessions: repository)

        await first.load()
        await first.keepCurrent()
        try await first.save()

        let second = CleanerViewModel(source: source, library: library, sessions: repository)
        await second.load()

        XCTAssertEqual(second.session.currentPosition, 1)
    }

    func testUnavailablePreviewDoesNotBlockQueueDecision() async {
        let library = MockPhotoLibraryService(
            albums: [.init(id: "album", title: "Mock Album", photoCount: 1)],
            assetsBySource: [
                .album(.init(id: "album", title: "Mock Album", photoCount: 1)): [
                    .init(id: "a", creationDate: nil, isFavorite: false, previewSymbolName: "photo")
                ]
            ]
        )
        let repository = InMemorySessionRepository()
        let source = CleaningSource.album(.init(id: "album", title: "Mock Album", photoCount: 1))
        let model = CleanerViewModel(source: source, library: library, sessions: repository)

        await model.load()
        await model.loadCurrentPreview(pixelWidth: 600, pixelHeight: 600)
        await model.queueCurrentForDeletion()

        XCTAssertNil(model.currentPreview)
        XCTAssertEqual(model.previewStatusText, "Local preview unavailable")
        XCTAssertEqual(model.session.pendingDeletionIDs, ["a"])
    }

    func testLatePreviewCannotReplaceNewCurrentAssetPreview() async throws {
        let library = MockPhotoLibraryService.sample
        await library.setPreviewDelayNanoseconds(200_000_000, for: "asset-1")
        let repository = InMemorySessionRepository()
        let source = CleaningSource.album(.init(id: "album", title: "Mock Album", photoCount: 3))
        let model = CleanerViewModel(source: source, library: library, sessions: repository)

        await model.load()
        let firstRequest = Task {
            await model.loadCurrentPreview(pixelWidth: 600, pixelHeight: 600)
        }
        try await Task.sleep(nanoseconds: 20_000_000)
        await model.keepCurrent()
        await model.loadCurrentPreview(pixelWidth: 600, pixelHeight: 600)
        await firstRequest.value

        XCTAssertEqual(model.currentAsset?.id, "asset-2")
        XCTAssertEqual(model.currentPreview?.content, .systemSymbol("photo.fill"))
    }
}
