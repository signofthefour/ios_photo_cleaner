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
}
