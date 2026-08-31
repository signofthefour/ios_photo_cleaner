import XCTest
@testable import PhotoCleaner

final class LocalPhotoPreviewTests: XCTestCase {
    func testRequestClampsPixelDimensionsAndMockRecordsLocalOnlyRequest() async throws {
        let service = MockPhotoLibraryService.sample
        let request = PhotoPreviewRequest(assetID: "asset-1", pixelWidth: 0, pixelHeight: -4)

        let preview = try await service.fetchLocalPreview(for: request)
        let recorded = await service.previewRequests

        XCTAssertEqual(request.pixelWidth, 1)
        XCTAssertEqual(request.pixelHeight, 1)
        XCTAssertEqual(recorded, [request])
        XCTAssertEqual(preview?.content, .systemSymbol("photo"))
    }

    func testUnavailableLocalPreviewReturnsNilWithoutDeletion() async throws {
        let service = MockPhotoLibraryService()
        let request = PhotoPreviewRequest(assetID: "missing", pixelWidth: 600, pixelHeight: 600)

        let preview = try await service.fetchLocalPreview(for: request)
        let deletedBatches = await service.deletedIDBatches

        XCTAssertNil(preview)
        XCTAssertTrue(deletedBatches.isEmpty)
    }
}
