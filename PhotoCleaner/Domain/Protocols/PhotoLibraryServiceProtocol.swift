protocol PhotoLibraryServiceProtocol: Sendable {
    /// Emits whenever the underlying library changes (an asset added,
    /// removed, or edited elsewhere — the system Photos app, another
    /// device via iCloud, and so on). Carries no diff: subscribers
    /// re-fetch whatever they're currently showing.
    var libraryChanges: AsyncStream<Void> { get }

    func requestAuthorization() async -> PhotoAccessStatus
    func fetchTimelineGroups() async throws -> [TimelineGroup]
    func fetchAlbums() async throws -> [PhotoAlbum]
    func fetchAssets(for source: CleaningSource) async throws -> [PhotoAsset]
    func fetchLocalPreview(for request: PhotoPreviewRequest) async throws -> LocalPhotoPreview?
    func setFavorite(_ favorite: Bool, assetID: String) async throws
    func addAsset(_ assetID: String, toAlbum albumID: String) async throws
    func createAlbum(named name: String) async throws -> PhotoAlbum
    func deleteAssets(ids: [String]) async throws
}
