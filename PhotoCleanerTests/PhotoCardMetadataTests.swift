import Foundation
import XCTest
@testable import PhotoCleaner

@MainActor
final class PhotoCardMetadataTests: XCTestCase {
    func testFormatsDateAndCoordinatesWithoutGeocoding() {
        let asset = PhotoAsset(
            id: "a",
            creationDate: Date(timeIntervalSince1970: 1_704_067_200),
            isFavorite: false,
            previewSymbolName: "photo",
            latitude: 37.5665,
            longitude: 126.9780
        )

        let metadata = PhotoCardMetadata(asset: asset)

        XCTAssertEqual(metadata.dateText, "01/01/24")
        XCTAssertEqual(metadata.locationText, "37.5665, 126.9780")
        XCTAssertEqual(
            metadata.accessibilityValue,
            "Captured 01/01/24. Location 37.5665, 126.9780."
        )
    }

    func testUsesApprovedFallbacksForMissingMetadata() {
        let asset = PhotoAsset(
            id: "a",
            creationDate: nil,
            isFavorite: false,
            previewSymbolName: "photo",
            latitude: nil,
            longitude: nil
        )

        let metadata = PhotoCardMetadata(asset: asset)

        XCTAssertEqual(metadata.dateText, "Unknown date")
        XCTAssertEqual(metadata.locationText, "No location")
        XCTAssertEqual(
            metadata.accessibilityValue,
            "Captured Unknown date. Location No location."
        )
    }
}
