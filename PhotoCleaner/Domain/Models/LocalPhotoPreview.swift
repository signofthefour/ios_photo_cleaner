import Foundation

struct PhotoPreviewRequest: Hashable, Codable, Sendable {
    let assetID: String
    let pixelWidth: Int
    let pixelHeight: Int
    /// Requests the best available rendition (exact resize, network access
    /// for iCloud-only originals) instead of the fast local-only preview.
    /// Reserved for the single photo currently on screen in detail — never
    /// for prefetch or grid thumbnails.
    let isHighQuality: Bool

    init(assetID: String, pixelWidth: Int, pixelHeight: Int, isHighQuality: Bool = false) {
        self.assetID = assetID
        self.pixelWidth = max(1, pixelWidth)
        self.pixelHeight = max(1, pixelHeight)
        self.isHighQuality = isHighQuality
    }
}

enum LocalPhotoPreviewContent: Equatable, Sendable {
    case systemSymbol(String)
    case encodedImageData(Data)
}

struct LocalPhotoPreview: Equatable, Sendable {
    let content: LocalPhotoPreviewContent
    let isDegraded: Bool
}
