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
    private var timelineGroups: [TimelineGroup]
    private var albums: [PhotoAlbum]
    private var assetsBySource: [CleaningSource: [PhotoAsset]]
    private var previewsByAssetID: [String: LocalPhotoPreview]
    private var previewDelayNanosecondsByAssetID: [String: UInt64] = [:]
    private var assetIDsByAlbumID: [String: Set<String>] = [:]
    private var forcedError: MockPhotoLibraryError?
    private let changeBroadcaster = PhotoLibraryChangeBroadcaster()

    nonisolated var libraryChanges: AsyncStream<Void> {
        changeBroadcaster.makeStream()
    }

    private(set) var previewRequests: [PhotoPreviewRequest] = []
    private(set) var favoriteMutations: [FavoriteMutation] = []
    private(set) var albumAssignments: [AlbumAssignment] = []
    private(set) var createdAlbumNames: [String] = []
    private(set) var deletedIDBatches: [[String]] = []

    init(
        accessStatus: PhotoAccessStatus = .limited,
        timelineGroups: [TimelineGroup] = [],
        albums: [PhotoAlbum] = [],
        assetsBySource: [CleaningSource: [PhotoAsset]] = [:],
        previewsByAssetID: [String: LocalPhotoPreview] = [:],
        forcedError: MockPhotoLibraryError? = nil
    ) {
        self.accessStatus = accessStatus
        self.timelineGroups = timelineGroups
        self.albums = albums
        self.assetsBySource = assetsBySource
        self.previewsByAssetID = previewsByAssetID
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
            PhotoAsset(
                id: "asset-1",
                creationDate: interval.start,
                isFavorite: false,
                previewSymbolName: "photo",
                latitude: 37.5665,
                longitude: 126.9780
            ),
            PhotoAsset(
                id: "asset-2",
                creationDate: interval.start.addingTimeInterval(60),
                isFavorite: true,
                previewSymbolName: "photo.fill",
                latitude: 40.7128,
                longitude: -74.0060
            ),
            PhotoAsset(
                id: "asset-3",
                creationDate: interval.start.addingTimeInterval(120),
                isFavorite: false,
                previewSymbolName: "mountain.2"
            )
        ]
        return MockPhotoLibraryService(
            timelineGroups: [timeline],
            albums: [album],
            assetsBySource: [.timeline(timeline): assets, .album(album): assets],
            previewsByAssetID: [
                "asset-1": .init(content: .systemSymbol("photo"), isDegraded: false),
                "asset-2": .init(content: .systemSymbol("photo.fill"), isDegraded: false),
                "asset-3": .init(content: .systemSymbol("mountain.2"), isDegraded: false)
            ]
        )
    }

    func setAccessStatus(_ status: PhotoAccessStatus) {
        accessStatus = status
    }

    func setForcedError(_ error: MockPhotoLibraryError?) {
        forcedError = error
    }

    func setPreview(_ preview: LocalPhotoPreview?, for assetID: String) {
        previewsByAssetID[assetID] = preview
    }

    func setPreviewDelayNanoseconds(_ delay: UInt64, for assetID: String) {
        previewDelayNanosecondsByAssetID[assetID] = delay
    }

    func setAssets(_ assets: [PhotoAsset], for source: CleaningSource) {
        assetsBySource[source] = assets
    }

    func setAlbums(_ albums: [PhotoAlbum]) {
        self.albums = albums
    }

    /// Seeds initial album membership for a test, distinct from
    /// `addAsset`'s recorded `albumAssignments` audit log so seeding
    /// doesn't look like something the test itself triggered.
    func setAlbumMembership(_ assetIDs: Set<String>, for albumID: String) {
        assetIDsByAlbumID[albumID] = assetIDs
    }

    /// Simulates a library change (an asset added/removed/edited elsewhere)
    /// for tests: emits on `libraryChanges` without altering any fetch
    /// result itself — pair with `setAssets`/`setAlbums` to change what a
    /// subsequent fetch returns.
    func simulateLibraryChange() {
        changeBroadcaster.notify()
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

    func fetchLocalPreview(for request: PhotoPreviewRequest) async throws -> LocalPhotoPreview? {
        try throwIfForced()
        previewRequests.append(request)
        let delay = previewDelayNanosecondsByAssetID[request.assetID] ?? 0
        let preview = previewsByAssetID[request.assetID]
        if delay > 0 {
            try await Task.sleep(nanoseconds: delay)
        }
        return preview
    }

    func setFavorite(_ favorite: Bool, assetID: String) async throws {
        try throwIfForced()
        favoriteMutations.append(.init(assetID: assetID, isFavorite: favorite))
    }

    func addAsset(_ assetID: String, toAlbum albumID: String) async throws {
        try throwIfForced()
        albumAssignments.append(.init(assetID: assetID, albumID: albumID))
        assetIDsByAlbumID[albumID, default: []].insert(assetID)
    }

    func albumIDs(containingAssetID assetID: String) async throws -> Set<String> {
        try throwIfForced()
        return Set(assetIDsByAlbumID.filter { $0.value.contains(assetID) }.keys)
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
