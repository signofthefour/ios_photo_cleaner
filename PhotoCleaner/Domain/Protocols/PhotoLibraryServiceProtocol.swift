protocol PhotoLibraryServiceProtocol: Sendable {
    func requestAuthorization() async -> PhotoAccessStatus
    func fetchTimelineGroups() async throws -> [TimelineGroup]
    func fetchAlbums() async throws -> [PhotoAlbum]
    func fetchAssets(for source: CleaningSource) async throws -> [PhotoAsset]
    func setFavorite(_ favorite: Bool, assetID: String) async throws
    func addAsset(_ assetID: String, toAlbum albumID: String) async throws
    func createAlbum(named name: String) async throws -> PhotoAlbum
    func deleteAssets(ids: [String]) async throws
}
