import XCTest
@testable import PhotoCleaner

final class MockServicesTests: XCTestCase {
    func testRepositoryRoundTripsValueWithoutPhotoData() async throws {
        let repository = InMemorySessionRepository()
        let session = CleaningSession.fixture(assetIDs: ["a"])

        try await repository.save(session)
        let loaded = try await repository.loadCurrent()

        XCTAssertEqual(loaded?.orderedAssetIDs, ["a"])
    }

    func testMockRecordsDeleteOnlyWhenExplicitlyRequested() async throws {
        let service = MockPhotoLibraryService.sample

        _ = try await service.fetchAssets(
            for: .album(.init(id: "album", title: "Mock Album", photoCount: 3))
        )
        let batchesBeforeDelete = await service.deletedIDBatches
        XCTAssertEqual(batchesBeforeDelete, [])

        try await service.deleteAssets(ids: ["asset-1"])

        let batchesAfterDelete = await service.deletedIDBatches
        XCTAssertEqual(batchesAfterDelete, [["asset-1"]])
    }

    func testAddAssetRecordsAssignmentAndReflectsMembership() async throws {
        let service = MockPhotoLibraryService.sample
        var membership = try await service.albumIDs(containingAssetID: "asset-1")
        XCTAssertTrue(membership.isEmpty)

        try await service.addAsset("asset-1", toAlbum: "album")

        membership = try await service.albumIDs(containingAssetID: "asset-1")
        XCTAssertEqual(membership, ["album"])
        let assignments = await service.albumAssignments
        XCTAssertEqual(assignments, [.init(assetID: "asset-1", albumID: "album")])
    }

    func testSetAlbumMembershipSeedsWithoutRecordingAnAssignment() async throws {
        let service = MockPhotoLibraryService.sample
        await service.setAlbumMembership(["asset-1"], for: "album")

        let membership = try await service.albumIDs(containingAssetID: "asset-1")
        XCTAssertEqual(membership, ["album"])
        let assignments = await service.albumAssignments
        XCTAssertTrue(assignments.isEmpty)
    }
}
