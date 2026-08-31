import Foundation

enum MockPhotoLibraryError: Error, Equatable {
    case forcedFailure
}

struct FavoriteMutation: Equatable, Sendable {
    let assetID: String
    let isFavorite: Bool
}

struct AlbumAssignment: Equatable, Sendable {
    let assetID: String
    let albumID: String
}

actor MockPhotoLibraryService: PhotoLibraryServiceProtocol {
    private var accessStatus: PhotoAccessStatus
    private let timelineGroups: [TimelineGroup]
    private let albums: [PhotoAlbum]
    private let assetsBySource: [CleaningSource: [PhotoAsset]]
    private var forcedError: MockPhotoLibraryError?

    private(set) var favoriteMutations: [FavoriteMutation] = []
    private(set) var albumAssignments: [AlbumAssignment] = []
    private(set) var createdAlbumNames: [String] = []
    private(set) var deletedIDBatches: [[String]] = []

    init(
        accessStatus: PhotoAccessStatus = .limited,
        timelineGroups: [TimelineGroup] = [],
        albums: [PhotoAlbum] = [],
        assetsBySource: [CleaningSource: [PhotoAsset]] = [:],
        forcedError: MockPhotoLibraryError? = nil
    ) {
        self.accessStatus = accessStatus
        self.timelineGroups = timelineGroups
        self.albums = albums
        self.assetsBySource = assetsBySource
        self.forcedError = forcedError
    }

    static var sample: MockPhotoLibraryService {
        let interval = DateInterval(
            start: Date(timeIntervalSince1970: 1_700_000_000),
            duration: 86_400 * 30
        )
        let timeline = TimelineGroup(
            id: "recent",
            title: "Recent Month",
            interval: interval,
            photoCount: 3
        )
        let album = PhotoAlbum(id: "album", title: "Mock Album", photoCount: 3)
        let assets = [
            PhotoAsset(id: "asset-1", creationDate: interval.start, isFavorite: false, previewSymbolName: "photo"),
            PhotoAsset(id: "asset-2", creationDate: interval.start.addingTimeInterval(60), isFavorite: true, previewSymbolName: "photo.fill"),
            PhotoAsset(id: "asset-3", creationDate: interval.start.addingTimeInterval(120), isFavorite: false, previewSymbolName: "mountain.2")
        ]
        return MockPhotoLibraryService(
            timelineGroups: [timeline],
            albums: [album],
            assetsBySource: [.timeline(timeline): assets, .album(album): assets]
        )
    }

    func setAccessStatus(_ status: PhotoAccessStatus) {
        accessStatus = status
    }

    func setForcedError(_ error: MockPhotoLibraryError?) {
        forcedError = error
    }

    func requestAuthorization() async -> PhotoAccessStatus {
        accessStatus
    }

    func fetchTimelineGroups() async throws -> [TimelineGroup] {
        try throwIfForced()
        return timelineGroups
    }

    func fetchAlbums() async throws -> [PhotoAlbum] {
        try throwIfForced()
        return albums
    }

    func fetchAssets(for source: CleaningSource) async throws -> [PhotoAsset] {
        try throwIfForced()
        return assetsBySource[source] ?? []
    }

    func setFavorite(_ favorite: Bool, assetID: String) async throws {
        try throwIfForced()
        favoriteMutations.append(.init(assetID: assetID, isFavorite: favorite))
    }

    func addAsset(_ assetID: String, toAlbum albumID: String) async throws {
        try throwIfForced()
        albumAssignments.append(.init(assetID: assetID, albumID: albumID))
    }

    func createAlbum(named name: String) async throws -> PhotoAlbum {
        try throwIfForced()
        createdAlbumNames.append(name)
        return PhotoAlbum(id: "created-\(createdAlbumNames.count)", title: name, photoCount: 0)
    }

    func deleteAssets(ids: [String]) async throws {
        try throwIfForced()
        deletedIDBatches.append(ids)
    }

    private func throwIfForced() throws {
        if let forcedError {
            throw forcedError
        }
    }
}
