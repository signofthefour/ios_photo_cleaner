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

    func testSelectionReportsExactCount() {
        let model = SourcePickerViewModel(library: MockPhotoLibraryService.sample)
        let source = CleaningSource.album(.init(id: "album", title: "Trips", photoCount: 42))

        XCTAssertEqual(model.photoCount(for: source), 42)
    }
}
