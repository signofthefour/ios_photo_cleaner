import Foundation

struct TimelineGroup: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let title: String
    let interval: DateInterval
    let photoCount: Int
}

struct PhotoAlbum: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let title: String
    let photoCount: Int
}

enum CleaningSource: Hashable, Codable, Sendable {
    case timeline(TimelineGroup)
    case album(PhotoAlbum)
    /// The whole library, in a shuffled order, started directly from Home
    /// without picking a specific month or album.
    case random
}
