import XCTest
@testable import PhotoCleaner

@MainActor
final class AlbumPickerViewModelTests: XCTestCase {
    func testLoadPopulatesAlbumsAndMembership() async throws {
        let library = MockPhotoLibraryService.sample
        await library.setAlbumMembership(["asset-1"], for: "album")
        let model = AlbumPickerViewModel(assetID: "asset-1", library: library)

        await model.load()

        XCTAssertEqual(model.filteredAlbums.map(\.id), ["album"])
        XCTAssertTrue(model.isMember(of: model.filteredAlbums[0]))
    }

    func testEmptyLibraryShowsEmptyState() async throws {
        let library = MockPhotoLibraryService()
        let model = AlbumPickerViewModel(assetID: "asset-1", library: library)

        await model.load()

        XCTAssertEqual(model.state, .empty)
    }

    func testSearchFiltersByTitleCaseInsensitively() async throws {
        let library = MockPhotoLibraryService(
            albums: [
                .init(id: "trips", title: "Trips", photoCount: 1),
                .init(id: "family", title: "Family", photoCount: 2)
            ]
        )
        let model = AlbumPickerViewModel(assetID: "asset-1", library: library)
        await model.load()

        model.searchText = "fam"

        XCTAssertEqual(model.filteredAlbums.map(\.id), ["family"])
    }

    func testAddIsOptimisticAndPersists() async throws {
        let library = MockPhotoLibraryService.sample
        let model = AlbumPickerViewModel(assetID: "asset-1", library: library)
        await model.load()
        let album = model.filteredAlbums[0]
        XCTAssertFalse(model.isMember(of: album))

        await model.add(to: album)

        XCTAssertTrue(model.isMember(of: album))
        let assignments = await library.albumAssignments
        XCTAssertEqual(assignments, [.init(assetID: "asset-1", albumID: "album")])
    }

    func testAddingWhenAlreadyAMemberDoesNothing() async throws {
        let library = MockPhotoLibraryService.sample
        await library.setAlbumMembership(["asset-1"], for: "album")
        let model = AlbumPickerViewModel(assetID: "asset-1", library: library)
        await model.load()

        await model.add(to: model.filteredAlbums[0])

        let assignments = await library.albumAssignments
        XCTAssertTrue(assignments.isEmpty)
    }

    func testFailedAddRollsBackMembershipAndShowsError() async throws {
        let library = MockPhotoLibraryService.sample
        let model = AlbumPickerViewModel(assetID: "asset-1", library: library)
        await model.load()
        let album = model.filteredAlbums[0]
        await library.setForcedError(.forcedFailure)

        await model.add(to: album)

        XCTAssertFalse(model.isMember(of: album))
        XCTAssertNotNil(model.errorMessage)
    }

    func testCreateAlbumInsertsSortedAndAutoAddsCurrentAsset() async throws {
        let library = MockPhotoLibraryService.sample
        let model = AlbumPickerViewModel(assetID: "asset-1", library: library)
        await model.load()

        await model.createAlbum(named: "Aardvarks")

        XCTAssertEqual(model.filteredAlbums.map(\.title), ["Aardvarks", "Mock Album"])
        let created = model.filteredAlbums[0]
        XCTAssertTrue(model.isMember(of: created))
        let assignments = await library.albumAssignments
        XCTAssertEqual(assignments, [.init(assetID: "asset-1", albumID: created.id)])
    }

    func testCreateAlbumWithBlankNameDoesNothing() async throws {
        let library = MockPhotoLibraryService.sample
        let model = AlbumPickerViewModel(assetID: "asset-1", library: library)
        await model.load()

        await model.createAlbum(named: "   ")

        XCTAssertEqual(model.filteredAlbums.count, 1)
        let createdNames = await library.createdAlbumNames
        XCTAssertTrue(createdNames.isEmpty)
    }

    func testFailedCreateAlbumShowsError() async throws {
        let library = MockPhotoLibraryService.sample
        let model = AlbumPickerViewModel(assetID: "asset-1", library: library)
        await model.load()
        await library.setForcedError(.forcedFailure)

        await model.createAlbum(named: "Aardvarks")

        XCTAssertEqual(model.filteredAlbums.count, 1)
        XCTAssertNotNil(model.createAlbumErrorMessage)
    }
}
