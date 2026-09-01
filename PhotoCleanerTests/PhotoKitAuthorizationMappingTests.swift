import Photos
import XCTest
@testable import PhotoCleaner

final class PhotoKitAuthorizationMappingTests: XCTestCase {
    func testEachPhotoKitStatusMapsToTheExpectedAccessStatus() {
        XCTAssertEqual(PhotoKitAuthorizationMapping.accessStatus(for: .notDetermined), .notDetermined)
        XCTAssertEqual(PhotoKitAuthorizationMapping.accessStatus(for: .restricted), .restricted)
        XCTAssertEqual(PhotoKitAuthorizationMapping.accessStatus(for: .denied), .denied)
        XCTAssertEqual(PhotoKitAuthorizationMapping.accessStatus(for: .authorized), .authorized)
        XCTAssertEqual(PhotoKitAuthorizationMapping.accessStatus(for: .limited), .limited)
    }
}
