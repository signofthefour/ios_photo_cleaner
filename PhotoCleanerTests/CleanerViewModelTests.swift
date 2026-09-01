import Foundation
import XCTest
@testable import PhotoCleaner

@MainActor
final class CleanerViewModelTests: XCTestCase {
    func testVisibleCardsContainCurrentAndAtMostTwoSuccessorsInOrder() async {
        let library = MockPhotoLibraryService.sample
        let model = CleanerViewModel(
            source: .album(.init(id: "album", title: "Mock Album", photoCount: 3)),
            library: library,
            sessions: InMemorySessionRepository()
        )

        await model.load()
        XCTAssertEqual(model.visibleCards.map(\.id), ["asset-1", "asset-2", "asset-3"])

        await model.keepCurrent()
        XCTAssertEqual(model.visibleCards.map(\.id), ["asset-2", "asset-3"])
    }

    func testToggleFavoriteIsOptimisticAndPersists() async throws {
        let library = MockPhotoLibraryService.sample
        let model = CleanerViewModel(
            source: .album(.init(id: "album", title: "Mock Album", photoCount: 3)),
            library: library,
            sessions: InMemorySessionRepository()
        )
        await model.load()
        XCTAssertEqual(model.currentAsset?.isFavorite, false)

        await model.toggleFavorite()

        XCTAssertEqual(model.currentAsset?.isFavorite, true)
        let mutations = await library.favoriteMutations
        XCTAssertEqual(mutations, [.init(assetID: "asset-1", isFavorite: true)])
    }

    func testFailedFavoriteToggleRollsBackAndShowsError() async throws {
        let library = MockPhotoLibraryService.sample
        let model = CleanerViewModel(
            source: .album(.init(id: "album", title: "Mock Album", photoCount: 3)),
            library: library,
            sessions: InMemorySessionRepository()
        )
        await model.load()
        await library.setForcedError(.forcedFailure)

        await model.toggleFavorite()

        XCTAssertEqual(model.currentAsset?.isFavorite, false)
        XCTAssertNotNil(model.favoriteErrorMessage)
        let mutations = await library.favoriteMutations
        XCTAssertTrue(mutations.isEmpty)
    }

    func testLoadVisiblePreviewsRequestsAllThreeCardsAndAcceptsDegradedResult() async {
        let library = MockPhotoLibraryService.sample
        await library.setPreview(
            .init(content: .systemSymbol("first-quality"), isDegraded: true),
            for: "asset-1"
        )
        let model = CleanerViewModel(
            source: .album(.init(id: "album", title: "Mock Album", photoCount: 3)),
            library: library,
            sessions: InMemorySessionRepository()
        )

        await model.load()
        await model.loadVisiblePreviews(pixelWidth: 900, pixelHeight: 900)
        let previewRequests = await library.previewRequests

        XCTAssertEqual(
            Set(previewRequests.map(\.assetID)),
            Set(["asset-1", "asset-2", "asset-3"])
        )
        XCTAssertEqual(
            model.visibleCards.first?.preview?.content,
            .systemSymbol("first-quality")
        )
        XCTAssertEqual(model.visibleCards.first?.preview?.isDegraded, true)
    }

    func testFirstCompletedPreviewIsFrozenForAsset() async {
        let library = MockPhotoLibraryService.sample
        await library.setPreview(
            .init(content: .systemSymbol("first-quality"), isDegraded: true),
            for: "asset-1"
        )
        let model = CleanerViewModel(
            source: .album(.init(id: "album", title: "Mock Album", photoCount: 3)),
            library: library,
            sessions: InMemorySessionRepository()
        )

        await model.load()
        await model.loadVisiblePreviews(pixelWidth: 900, pixelHeight: 900)
        await library.setPreview(
            .init(content: .systemSymbol("later-quality"), isDegraded: false),
            for: "asset-1"
        )
        await model.loadVisiblePreviews(pixelWidth: 1200, pixelHeight: 1200)
        let previewRequests = await library.previewRequests

        XCTAssertEqual(
            model.visibleCards.first?.preview?.content,
            .systemSymbol("first-quality")
        )
        XCTAssertEqual(
            previewRequests.filter { $0.assetID == "asset-1" }.count,
            1
        )
    }

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

    func testProgressFractionReflectsDecidedPortionOfSession() async {
        let library = MockPhotoLibraryService.sample
        let model = CleanerViewModel(
            source: .album(.init(id: "album", title: "Mock Album", photoCount: 3)),
            library: library,
            sessions: InMemorySessionRepository()
        )

        await model.load()
        XCTAssertEqual(model.progressFraction, 0)

        await model.keepCurrent()
        XCTAssertEqual(model.progressFraction, 1.0 / 3.0, accuracy: 0.0001)

        await model.keepCurrent()
        await model.keepCurrent()
        XCTAssertEqual(model.progressFraction, 1)
    }

    func testProgressFractionIsZeroForEmptySession() async {
        let library = MockPhotoLibraryService(
            albums: [.init(id: "empty", title: "Empty Album", photoCount: 0)],
            assetsBySource: [.album(.init(id: "empty", title: "Empty Album", photoCount: 0)): []]
        )
        let model = CleanerViewModel(
            source: .album(.init(id: "empty", title: "Empty Album", photoCount: 0)),
            library: library,
            sessions: InMemorySessionRepository()
        )

        await model.load()
        XCTAssertEqual(model.progressFraction, 0)
    }

    func testHandleLibraryChangeMarksDisappearedAssetUnavailableAndAdvances() async {
        let library = MockPhotoLibraryService.sample
        let source = CleaningSource.album(.init(id: "album", title: "Mock Album", photoCount: 3))
        let model = CleanerViewModel(source: source, library: library, sessions: InMemorySessionRepository())

        await model.load()
        XCTAssertEqual(model.currentAsset?.id, "asset-1")

        // Simulate asset-1 disappearing from the library (deleted elsewhere).
        await library.setAssets(
            [
                .init(id: "asset-2", creationDate: nil, isFavorite: true, previewSymbolName: "photo.fill"),
                .init(id: "asset-3", creationDate: nil, isFavorite: false, previewSymbolName: "mountain.2")
            ],
            for: source
        )

        await model.handleLibraryChange()

        XCTAssertEqual(model.session.unavailableAssetIDs, ["asset-1"])
        XCTAssertEqual(model.currentAsset?.id, "asset-2")
    }

    func testHandleLibraryChangeIgnoresFetchFailureAndKeepsCurrentState() async {
        let library = MockPhotoLibraryService.sample
        let source = CleaningSource.album(.init(id: "album", title: "Mock Album", photoCount: 3))
        let model = CleanerViewModel(source: source, library: library, sessions: InMemorySessionRepository())

        await model.load()
        XCTAssertEqual(model.currentAsset?.id, "asset-1")

        await library.setForcedError(.forcedFailure)
        await model.handleLibraryChange()

        XCTAssertEqual(model.currentAsset?.id, "asset-1")
    }

    func testRandomSourceLoadsAndDecidesLikeAnyOtherSource() async throws {
        let asset = PhotoAsset(id: "r1", creationDate: nil, isFavorite: false, previewSymbolName: "photo")
        let library = MockPhotoLibraryService(assetsBySource: [.random: [asset]])
        let model = CleanerViewModel(source: .random, library: library, sessions: InMemorySessionRepository())

        await model.load()
        XCTAssertEqual(model.currentAsset?.id, "r1")

        await model.keepCurrent()
        XCTAssertEqual(model.session.decisions["r1"], .keep)
    }

    func testCompletedSessionStartsFreshAndCarriesForwardPendingDeletion() async throws {
        let library = MockPhotoLibraryService.sample
        let repository = InMemorySessionRepository()
        let source = CleaningSource.album(.init(id: "album", title: "Mock Album", photoCount: 3))

        let first = CleanerViewModel(source: source, library: library, sessions: repository)
        await first.load()
        await first.queueCurrentForDeletion()
        await first.keepCurrent()
        await first.keepCurrent()
        XCTAssertTrue(first.session.isComplete)
        _ = await first.saveForExit()

        let second = CleanerViewModel(source: source, library: library, sessions: repository)
        await second.load()

        XCTAssertEqual(second.session.currentPosition, 0)
        XCTAssertEqual(second.session.orderedAssetIDs, ["asset-1", "asset-2", "asset-3"])
        XCTAssertEqual(second.session.pendingDeletionIDs, ["asset-1"])
        XCTAssertEqual(second.session.decisions["asset-1"], .pendingDelete)
    }

    /// Regression test: a carried-forward pending-deletion id must also carry
    /// forward its `.pendingDelete` decision, or `restorePendingDeletion(id:)`'s
    /// `decisions[id] == .pendingDelete` guard silently no-ops and Deletion
    /// Review's Restore button appears to do nothing.
    func testCarriedForwardPendingDeletionCanStillBeRestored() async throws {
        let library = MockPhotoLibraryService.sample
        let repository = InMemorySessionRepository()
        let source = CleaningSource.album(.init(id: "album", title: "Mock Album", photoCount: 3))

        let first = CleanerViewModel(source: source, library: library, sessions: repository)
        await first.load()
        await first.queueCurrentForDeletion()
        await first.keepCurrent()
        await first.keepCurrent()
        _ = await first.saveForExit()

        let second = CleanerViewModel(source: source, library: library, sessions: repository)
        await second.load()
        XCTAssertEqual(second.session.pendingDeletionIDs, ["asset-1"])

        let review = DeletionReviewViewModel(library: library, sessions: repository)
        await review.load()
        try await review.restore(id: "asset-1")

        XCTAssertTrue(review.pendingIDs.isEmpty)
        let saved = try await repository.loadCurrent()
        XCTAssertEqual(saved?.pendingDeletionIDs, [])
    }

    func testPendingDeletionCarriesForwardWhenSwitchingToADifferentSource() async throws {
        let albumA = PhotoAlbum(id: "album-a", title: "Album A", photoCount: 2)
        let albumB = PhotoAlbum(id: "album-b", title: "Album B", photoCount: 1)
        let library = MockPhotoLibraryService(
            albums: [albumA, albumB],
            assetsBySource: [
                .album(albumA): [
                    .init(id: "a1", creationDate: nil, isFavorite: false, previewSymbolName: "photo"),
                    .init(id: "a2", creationDate: nil, isFavorite: false, previewSymbolName: "photo")
                ],
                .album(albumB): [
                    .init(id: "b1", creationDate: nil, isFavorite: false, previewSymbolName: "photo")
                ]
            ]
        )
        let repository = InMemorySessionRepository()

        let first = CleanerViewModel(source: .album(albumA), library: library, sessions: repository)
        await first.load()
        await first.queueCurrentForDeletion()
        await first.keepCurrent()
        _ = await first.saveForExit()

        let second = CleanerViewModel(source: .album(albumB), library: library, sessions: repository)
        await second.load()

        XCTAssertEqual(second.session.currentPosition, 0)
        XCTAssertEqual(second.session.orderedAssetIDs, ["b1"])
        XCTAssertEqual(second.session.pendingDeletionIDs, ["a1"])
        XCTAssertEqual(second.session.decisions["a1"], .pendingDelete)
    }

    func testSaveCanBeLoadedByNewViewModel() async throws {
        let library = MockPhotoLibraryService.sample
        let repository = InMemorySessionRepository()
        let source = CleaningSource.album(.init(id: "album", title: "Mock Album", photoCount: 3))
        let first = CleanerViewModel(source: source, library: library, sessions: repository)

        await first.load()
        await first.keepCurrent()
        let shouldDismiss = await first.saveForExit()
        XCTAssertTrue(shouldDismiss)

        let second = CleanerViewModel(source: source, library: library, sessions: repository)
        await second.load()

        XCTAssertEqual(second.session.currentPosition, 1)
    }

    func testExitSaveReturnsSuccessOnlyAfterRepositoryPersistsSession() async {
        let library = MockPhotoLibraryService.sample
        let repository = ThrowingSessionRepository()
        let source = CleaningSource.album(.init(id: "album", title: "Mock Album", photoCount: 3))
        let model = CleanerViewModel(source: source, library: library, sessions: repository)

        await model.load()
        await model.keepCurrent()

        let shouldDismiss = await model.saveForExit()
        let persistedSession = await repository.currentSession

        XCTAssertTrue(shouldDismiss)
        XCTAssertFalse(model.isSaving)
        XCTAssertNil(model.saveErrorMessage)
        XCTAssertEqual(persistedSession?.currentPosition, 1)
    }

    func testFailedExitSaveKeepsSessionAndExposesRecoverableError() async {
        let library = MockPhotoLibraryService.sample
        let repository = ThrowingSessionRepository(shouldThrowOnSave: true)
        let source = CleaningSource.album(.init(id: "album", title: "Mock Album", photoCount: 3))
        let model = CleanerViewModel(source: source, library: library, sessions: repository)

        await model.load()
        await model.queueCurrentForDeletion()

        let shouldDismiss = await model.saveForExit()
        let persistedSession = await repository.currentSession

        XCTAssertFalse(shouldDismiss)
        XCTAssertFalse(model.isSaving)
        XCTAssertEqual(
            model.saveErrorMessage,
            "This cleaning session could not be saved. Please try again."
        )
        XCTAssertEqual(model.session.pendingDeletionIDs, ["asset-1"])
        XCTAssertNil(persistedSession)
    }

    func testExitSaveCanRetryAfterFailure() async {
        let library = MockPhotoLibraryService.sample
        let repository = ThrowingSessionRepository(shouldThrowOnSave: true)
        let source = CleaningSource.album(.init(id: "album", title: "Mock Album", photoCount: 3))
        let model = CleanerViewModel(source: source, library: library, sessions: repository)

        await model.load()
        await model.keepCurrent()
        let shouldDismissAfterFailure = await model.saveForExit()
        XCTAssertFalse(shouldDismissAfterFailure)

        await repository.setShouldThrowOnSave(false)
        let shouldDismiss = await model.saveForExit()
        let persistedSession = await repository.currentSession

        XCTAssertTrue(shouldDismiss)
        XCTAssertNil(model.saveErrorMessage)
        XCTAssertEqual(persistedSession?.currentPosition, 1)
    }

    func testExitSaveIgnoresDuplicateRequestWhileSaving() async {
        let library = MockPhotoLibraryService.sample
        let repository = ThrowingSessionRepository(saveDelayNanoseconds: 200_000_000)
        let source = CleaningSource.album(.init(id: "album", title: "Mock Album", photoCount: 3))
        let model = CleanerViewModel(source: source, library: library, sessions: repository)

        await model.load()
        let firstSave = Task { await model.saveForExit() }
        let firstSaveStarted = await waitForSaveCall(in: repository)
        XCTAssertTrue(firstSaveStarted)
        guard firstSaveStarted else {
            firstSave.cancel()
            _ = await firstSave.value
            return
        }

        XCTAssertTrue(model.isSaving)
        let duplicateShouldDismiss = await model.saveForExit()
        let firstShouldDismiss = await firstSave.value
        let saveCallCount = await repository.saveCallCount

        XCTAssertFalse(duplicateShouldDismiss)
        XCTAssertTrue(firstShouldDismiss)
        XCTAssertEqual(saveCallCount, 1)
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

    func testThrownPreviewErrorDoesNotBlockQueueDecisionOrDeleteAssets() async {
        let source = CleaningSource.album(.init(id: "album", title: "Mock Album", photoCount: 1))
        let library = MockPhotoLibraryService(
            albums: [.init(id: "album", title: "Mock Album", photoCount: 1)],
            assetsBySource: [
                source: [
                    .init(id: "a", creationDate: nil, isFavorite: false, previewSymbolName: "photo")
                ]
            ]
        )
        let repository = InMemorySessionRepository()
        let model = CleanerViewModel(source: source, library: library, sessions: repository)

        await model.load()
        XCTAssertEqual(model.currentAsset?.id, "a")

        await library.setForcedError(.forcedFailure)
        await model.loadCurrentPreview(pixelWidth: 600, pixelHeight: 600)
        await model.queueCurrentForDeletion()
        let deletedBatches = await library.deletedIDBatches

        XCTAssertNil(model.currentPreview)
        XCTAssertEqual(model.previewStatusText, "Local preview unavailable")
        XCTAssertEqual(model.session.orderedAssetIDs, ["a"])
        XCTAssertEqual(model.session.currentPosition, 1)
        XCTAssertEqual(model.session.decisions, ["a": .pendingDelete])
        XCTAssertEqual(model.session.pendingDeletionIDs, ["a"])
        XCTAssertTrue(model.session.unavailableAssetIDs.isEmpty)
        XCTAssertTrue(deletedBatches.isEmpty)
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

    func testDownloadingFromiCloudShowsStatusTextWhileInFlightAndClearsOnCompletion() async {
        let library = MockPhotoLibraryService.sample
        await library.setSimulatesCloudDownload(for: "asset-1")
        await library.setPreviewDelayNanoseconds(200_000_000, for: "asset-1")
        let source = CleaningSource.album(.init(id: "album", title: "Mock Album", photoCount: 3))
        let model = CleanerViewModel(source: source, library: library, sessions: InMemorySessionRepository())

        await model.load()
        let task = Task { await model.loadCurrentPreview(pixelWidth: 900, pixelHeight: 900) }

        let sawDownloadingStatus = await waitForCondition { model.previewStatusText == "Downloading from iCloud…" }
        XCTAssertTrue(sawDownloadingStatus)

        await task.value

        XCTAssertNil(model.previewStatusText)
        XCTAssertEqual(model.currentPreview?.content, .systemSymbol("photo"))
    }

    func testAvailableCardPresentationKeepsExistingAccessibilitySentences() {
        let metadata = PhotoCardMetadata(
            asset: .init(
                id: "a",
                creationDate: nil,
                isFavorite: true,
                previewSymbolName: "photo"
            )
        )
        let preview = LocalPhotoPreview(content: .systemSymbol("photo"), isDegraded: false)

        let presentation = PrintedPhotoCardPreviewPresentation(
            preview: preview,
            previewStatusText: nil,
            metadata: metadata,
            isFavorite: true
        )

        guard case let .systemSymbol(name) = presentation.content else {
            return XCTFail("Available symbol preview should remain available")
        }
        XCTAssertEqual(name, "photo")
        XCTAssertNil(presentation.statusText)
        XCTAssertEqual(
            presentation.accessibilityValue,
            "Captured Unknown date. Location No location. Favorite."
        )
    }

    func testNilUnavailableCardPresentationIncludesVisibleStatusInAccessibilityValue() {
        let metadata = PhotoCardMetadata(
            asset: .init(
                id: "a",
                creationDate: nil,
                isFavorite: false,
                previewSymbolName: "photo"
            )
        )

        let presentation = PrintedPhotoCardPreviewPresentation(
            preview: nil,
            previewStatusText: "Local preview unavailable",
            metadata: metadata,
            isFavorite: false
        )

        guard case .placeholder = presentation.content else {
            return XCTFail("Unavailable preview should use the placeholder")
        }
        XCTAssertEqual(presentation.statusText, "Local preview unavailable")
        XCTAssertEqual(
            presentation.accessibilityValue,
            "Captured Unknown date. Location No location. Not favorite. Local preview unavailable."
        )
    }

    func testUndecodableCardPresentationIncludesVisibleStatusInAccessibilityValue() {
        let metadata = PhotoCardMetadata(
            asset: .init(
                id: "a",
                creationDate: nil,
                isFavorite: true,
                previewSymbolName: "photo"
            )
        )
        let preview = LocalPhotoPreview(
            content: .encodedImageData(Data("not image data".utf8)),
            isDegraded: false
        )

        let presentation = PrintedPhotoCardPreviewPresentation(
            preview: preview,
            previewStatusText: nil,
            metadata: metadata,
            isFavorite: true
        )

        guard case .placeholder = presentation.content else {
            return XCTFail("Undecodable image data should use the placeholder")
        }
        XCTAssertEqual(presentation.statusText, "Local preview unavailable")
        XCTAssertEqual(
            presentation.accessibilityValue,
            "Captured Unknown date. Location No location. Favorite. Local preview unavailable."
        )
    }

    func testKeepStampPresentationIncludesTextDirectionAndOpacity() {
        let presentation = PrintedPhotoCardStampPresentation(
            stamp: .init(direction: .keep, opacity: 0.5)
        )

        XCTAssertEqual(presentation?.text, "KEEP")
        XCTAssertEqual(presentation?.direction, .keep)
        XCTAssertEqual(presentation?.opacity, 0.5)
    }

    func testDeleteStampPresentationIncludesTextDirectionAndOpacity() {
        let presentation = PrintedPhotoCardStampPresentation(
            stamp: .init(direction: .delete, opacity: 1)
        )

        XCTAssertEqual(presentation?.text, "DELETE")
        XCTAssertEqual(presentation?.direction, .delete)
        XCTAssertEqual(presentation?.opacity, 1)
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

    private func waitForCondition(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<1_000 {
            if condition() {
                return true
            }
            await Task.yield()
        }
        return false
    }

    private func waitForSaveCall(in repository: ThrowingSessionRepository) async -> Bool {
        for _ in 0..<1_000 {
            if await repository.saveCallCount > 0 {
                return true
            }
            await Task.yield()
        }
        return false
    }
}

private enum ThrowingSessionRepositoryError: Error {
    case forcedSaveFailure
}

private actor ThrowingSessionRepository: SessionRepositoryProtocol {
    private(set) var currentSession: CleaningSession?
    private(set) var saveCallCount = 0
    private var shouldThrowOnSave: Bool
    private let saveDelayNanoseconds: UInt64

    init(
        initial: CleaningSession? = nil,
        shouldThrowOnSave: Bool = false,
        saveDelayNanoseconds: UInt64 = 0
    ) {
        currentSession = initial
        self.shouldThrowOnSave = shouldThrowOnSave
        self.saveDelayNanoseconds = saveDelayNanoseconds
    }

    func loadCurrent() async throws -> CleaningSession? {
        currentSession
    }

    func save(_ session: CleaningSession) async throws {
        saveCallCount += 1
        if saveDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: saveDelayNanoseconds)
        }
        if shouldThrowOnSave {
            throw ThrowingSessionRepositoryError.forcedSaveFailure
        }
        currentSession = session
    }

    func removeCurrent() async throws {
        currentSession = nil
    }

    func setShouldThrowOnSave(_ shouldThrow: Bool) {
        shouldThrowOnSave = shouldThrow
    }
}
