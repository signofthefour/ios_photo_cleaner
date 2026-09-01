import XCTest
@testable import PhotoCleaner

@MainActor
final class SourcePickerViewModelTests: XCTestCase {
    func testLoadShowsTimelineAndAlbums() async {
        let model = SourcePickerViewModel(library: MockPhotoLibraryService.sample)

        await model.load()

        guard case let .content(timeline, albums) = model.state else {
            return XCTFail("Expected content state")
        }
        XCTAssertEqual(timeline.map(\.id), ["recent"])
        XCTAssertEqual(albums.map(\.id), ["album"])
    }

    func testLoadShowsEmptyWhenNoSourcesExist() async {
        let model = SourcePickerViewModel(library: MockPhotoLibraryService())

        await model.load()

        XCTAssertEqual(model.state, .empty)
    }

    func testLoadShowsRecoverableFailure() async {
        let library = MockPhotoLibraryService(forcedError: .forcedFailure)
        let model = SourcePickerViewModel(library: library)

        await model.load()

        guard case .failed = model.state else {
            return XCTFail("Expected failed state")
        }
    }

    func testRefreshIfNeededUpdatesCountsWhileInContentState() async {
        let library = MockPhotoLibraryService.sample
        let model = SourcePickerViewModel(library: library)
        await model.load()

        await library.setAlbums([.init(id: "album", title: "Mock Album", photoCount: 9)])
        await model.refreshIfNeeded()

        guard case let .content(_, albums) = model.state else {
            return XCTFail("Expected content state")
        }
        XCTAssertEqual(albums.first?.photoCount, 9)
    }

    func testRefreshIfNeededDoesNothingBeforeInitialLoad() async {
        let model = SourcePickerViewModel(library: MockPhotoLibraryService.sample)

        await model.refreshIfNeeded()

        XCTAssertEqual(model.state, .loading)
    }

    func testRefreshIfNeededIgnoresFailureAndKeepsExistingContent() async {
        let library = MockPhotoLibraryService.sample
        let model = SourcePickerViewModel(library: library)
        await model.load()

        await library.setForcedError(.forcedFailure)
        await model.refreshIfNeeded()

        guard case .content = model.state else {
            return XCTFail("Expected content state to be retained")
        }
    }

    func testSelectionReportsExactCount() {
        let model = SourcePickerViewModel(library: MockPhotoLibraryService.sample)
        let source = CleaningSource.album(.init(id: "album", title: "Trips", photoCount: 42))

        XCTAssertEqual(model.photoCount(for: source), 42)
    }
}
