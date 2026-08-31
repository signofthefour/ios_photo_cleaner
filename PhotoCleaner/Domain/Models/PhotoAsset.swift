import Foundation

struct PhotoAsset: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let creationDate: Date?
    var isFavorite: Bool
    let previewSymbolName: String
}
