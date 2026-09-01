import Photos

/// Pure mapping from PhotoKit's authorization status to the app's
/// framework-independent `PhotoAccessStatus`. Kept separate from the live
/// service so the mapping itself is unit-testable without a real photo
/// library or permission prompt.
enum PhotoKitAuthorizationMapping {
    static func accessStatus(for status: PHAuthorizationStatus) -> PhotoAccessStatus {
        switch status {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .authorized: .authorized
        case .limited: .limited
        @unknown default: .denied
        }
    }
}
