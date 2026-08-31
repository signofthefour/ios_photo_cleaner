import Foundation

struct PhotoCardMetadata: Equatable, Sendable {
    let dateText: String
    let locationText: String

    init(asset: PhotoAsset) {
        if let creationDate = asset.creationDate {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "dd/MM/yy"
            dateText = formatter.string(from: creationDate)
        } else {
            dateText = "Unknown date"
        }

        if let latitude = asset.latitude, let longitude = asset.longitude {
            locationText = String(
                format: "%.4f, %.4f",
                locale: Locale(identifier: "en_US_POSIX"),
                latitude,
                longitude
            )
        } else {
            locationText = "No location"
        }
    }

    var accessibilityValue: String {
        "Captured \(dateText). Location \(locationText)."
    }
}
