import Foundation

struct PhotoPreviewRequest: Hashable, Codable, Sendable {
    let assetID: String
    let pixelWidth: Int
    let pixelHeight: Int

    init(assetID: String, pixelWidth: Int, pixelHeight: Int) {
        self.assetID = assetID
        self.pixelWidth = max(1, pixelWidth)
        self.pixelHeight = max(1, pixelHeight)
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
