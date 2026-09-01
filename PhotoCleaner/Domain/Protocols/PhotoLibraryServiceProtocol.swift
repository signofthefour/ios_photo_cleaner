protocol PhotoLibraryServiceProtocol: Sendable {
    /// Emits whenever the underlying library changes (an asset added,
    /// removed, or edited elsewhere — the system Photos app, another
    /// device via iCloud, and so on). Carries no diff: subscribers
    /// re-fetch whatever they're currently showing.
    var libraryChanges: AsyncStream<Void> { get }

    func requestAuthorization() async -> PhotoAccessStatus
    func fetchTimelineGroups() async throws -> [TimelineGroup]
    func fetchAlbums() async throws -> [PhotoAlbum]
    /// The subset of the caller's own albums that already contain this
    /// asset, for the album picker's existing-membership checkmarks.
    func albumIDs(containingAssetID assetID: String) async throws -> Set<String>
    func fetchAssets(for source: CleaningSource) async throws -> [PhotoAsset]
    /// `onProgress` fires only while the asset is actually being downloaded
    /// from iCloud — a fully local asset never calls it. Reports fractional
    /// progress (0...1) from an arbitrary background queue.
    func fetchLocalPreview(
        for request: PhotoPreviewRequest,
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws -> LocalPhotoPreview?
    func setFavorite(_ favorite: Bool, assetID: String) async throws
    func addAsset(_ assetID: String, toAlbum albumID: String) async throws
    func createAlbum(named name: String) async throws -> PhotoAlbum
    func deleteAssets(ids: [String]) async throws
}

extension PhotoLibraryServiceProtocol {
    func fetchLocalPreview(for request: PhotoPreviewRequest) async throws -> LocalPhotoPreview? {
        try await fetchLocalPreview(for: request, onProgress: nil)
    }
}
