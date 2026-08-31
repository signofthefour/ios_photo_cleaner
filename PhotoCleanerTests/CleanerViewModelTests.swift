import Foundation
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
        await model.loadCurrentPreview(pixelWidth: 900, pixelHeight: 900)

        XCTAssertNil(model.currentPreview)
        XCTAssertEqual(model.previewStatusText, "Local preview unavailable")
        XCTAssertEqual(model.session.pendingDeletionIDs, ["a"])
    }

    func testLatePreviewCannotReplaceNewCurrentAssetPreview() async {
        let library = MockPhotoLibraryService.sample
        await library.setPreviewDelayNanoseconds(200_000_000, for: "asset-1")
        let repository = InMemorySessionRepository()
        let source = CleaningSource.album(.init(id: "album", title: "Mock Album", photoCount: 3))
        let model = CleanerViewModel(source: source, library: library, sessions: repository)

        await model.load()
        let firstRequest = Task {
            await model.loadCurrentPreview(pixelWidth: 600, pixelHeight: 600)
        }
        let firstRequestStarted = await waitForPreviewRequest(assetID: "asset-1", in: library)
        XCTAssertTrue(firstRequestStarted)
        guard firstRequestStarted else {
            firstRequest.cancel()
            await firstRequest.value
            return
        }
        await model.keepCurrent()
        await model.loadCurrentPreview(pixelWidth: 600, pixelHeight: 600)
        await firstRequest.value

        XCTAssertEqual(model.currentAsset?.id, "asset-2")
        XCTAssertEqual(model.currentPreview?.content, .systemSymbol("photo.fill"))
    }

    func testUndecodableEncodedPreviewUsesPlaceholderWithVisibleUnavailableStatus() {
        let preview = LocalPhotoPreview(
            content: .encodedImageData(Data("not image data".utf8)),
            isDegraded: false
        )

        let presentation = PrintedPhotoCardPreviewPresentation(
            preview: preview,
            previewStatusText: nil
        )

        guard case .placeholder = presentation.content else {
            return XCTFail("Undecodable image data should use the placeholder")
        }
        XCTAssertEqual(presentation.statusText, "Local preview unavailable")
    }

    private func waitForPreviewRequest(
        assetID: String,
        in library: MockPhotoLibraryService
    ) async -> Bool {
        for _ in 0..<1_000 {
            let requests = await library.previewRequests
            if requests.contains(where: { $0.assetID == assetID }) {
                return true
            }
            await Task.yield()
        }
        return false
    }
}
