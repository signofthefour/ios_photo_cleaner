import Foundation

struct PhotoAsset: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let creationDate: Date?
    var isFavorite: Bool
    let previewSymbolName: String
    let latitude: Double?
    let longitude: Double?

    init(
        id: String,
        creationDate: Date?,
        isFavorite: Bool,
        previewSymbolName: String,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        self.id = id
        self.creationDate = creationDate
        self.isFavorite = isFavorite
        self.previewSymbolName = previewSymbolName
        self.latitude = latitude
        self.longitude = longitude
    }
}
