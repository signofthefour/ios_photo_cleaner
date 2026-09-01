import Photos
import UIKit

enum PhotoKitServiceError: Error, Equatable, Sendable {
    case albumNotFound
    case assetNotFound
    case imageLoadFailed
    case deletionFailed
    case favoriteUpdateFailed
    case albumAssignmentFailed
    case albumCreationFailed
}

/// `PhotoLibraryServiceProtocol` backed by the real PhotoKit library.
///
/// Preview requests default to a fast, local-only rendition:
/// `isNetworkAccessAllowed = false`, so a cloud-optimized asset is never
/// downloaded to satisfy a swipe decision, and only the first locally
/// available result is used even when PhotoKit's `.opportunistic` delivery
/// mode would later deliver a higher-quality rendition. A request with
/// `PhotoPreviewRequest.isHighQuality` set instead asks PhotoKit for its
/// best rendition (`.highQualityFormat`, exact resize, iCloud download
/// allowed) — reserved for the single photo currently in detail view.
final class PhotoKitPhotoLibraryService: NSObject, PhotoLibraryServiceProtocol, PHPhotoLibraryChangeObserver, @unchecked Sendable {
    private let imageManager: PHImageManager
    private let changeBroadcaster = PhotoLibraryChangeBroadcaster()
    private let registrationLock = NSLock()
    private var isRegisteredWithPhotoLibrary = false

    var libraryChanges: AsyncStream<Void> {
        registerWithPhotoLibraryIfNeeded()
        return changeBroadcaster.makeStream()
    }

    init(imageManager: PHImageManager = .default()) {
        self.imageManager = imageManager
        super.init()
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    /// Registration is lazy (on first `libraryChanges` access) rather than
    /// in `init`, so constructing this service never touches PhotoKit
    /// before the caller actually wants change events.
    private func registerWithPhotoLibraryIfNeeded() {
        registrationLock.lock()
        defer { registrationLock.unlock() }
        guard !isRegisteredWithPhotoLibrary else { return }
        isRegisteredWithPhotoLibrary = true
        PHPhotoLibrary.shared().register(self)
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        changeBroadcaster.notify()
    }

    func requestAuthorization() async -> PhotoAccessStatus {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return PhotoKitAuthorizationMapping.accessStatus(for: status)
    }

    func fetchTimelineGroups() async throws -> [TimelineGroup] {
        try Task.checkCancellation()
        return PhotoTimelineGrouping.groups(for: fetchAllPhotoDescriptors())
    }

    func fetchAlbums() async throws -> [PhotoAlbum] {
        try Task.checkCancellation()
        let collections = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .albumRegular,
            options: nil
        )

        var albums: [PhotoAlbum] = []
        collections.enumerateObjects { collection, _, _ in
            let count = PHAsset.fetchAssets(in: collection, options: Self.imageFetchOptions()).count
            guard count > 0 else { return }
            albums.append(
                PhotoAlbum(
                    id: collection.localIdentifier,
                    title: collection.localizedTitle ?? "Untitled Album",
                    photoCount: count
                )
            )
        }
        return albums.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func fetchAssets(for source: CleaningSource) async throws -> [PhotoAsset] {
        try Task.checkCancellation()
        switch source {
        case let .timeline(group):
            return fetchAssets(matching: group)
        case let .album(album):
            return try fetchAssets(inAlbumID: album.id)
        case .random:
            return fetchShuffledLibraryAssets()
        }
    }

    func fetchLocalPreview(
        for request: PhotoPreviewRequest,
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws -> LocalPhotoPreview? {
        guard let asset = fetchAsset(byLocalIdentifier: request.assetID) else { return nil }
        return try await loadPreview(
            for: asset,
            pixelWidth: request.pixelWidth,
            pixelHeight: request.pixelHeight,
            isHighQuality: request.isHighQuality,
            onProgress: onProgress
        )
    }

    func setFavorite(_ favorite: Bool, assetID: String) async throws {
        try Task.checkCancellation()
        guard let asset = fetchAsset(byLocalIdentifier: assetID) else {
            throw PhotoKitServiceError.assetNotFound
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest(for: asset).isFavorite = favorite
            } completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? PhotoKitServiceError.favoriteUpdateFailed)
                }
            }
        }
    }

    func addAsset(_ assetID: String, toAlbum albumID: String) async throws {
        try Task.checkCancellation()
        guard let asset = fetchAsset(byLocalIdentifier: assetID) else {
            throw PhotoKitServiceError.assetNotFound
        }
        let collections = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [albumID],
            options: nil
        )
        guard let collection = collections.firstObject else {
            throw PhotoKitServiceError.albumNotFound
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                guard let request = PHAssetCollectionChangeRequest(for: collection) else { return }
                request.addAssets([asset] as NSArray)
            } completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? PhotoKitServiceError.albumAssignmentFailed)
                }
            }
        }
    }

    func createAlbum(named name: String) async throws -> PhotoAlbum {
        try Task.checkCancellation()
        var placeholder: PHObjectPlaceholder?
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name)
                placeholder = request.placeholderForCreatedAssetCollection
            } completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? PhotoKitServiceError.albumCreationFailed)
                }
            }
        }
        guard let identifier = placeholder?.localIdentifier else {
            throw PhotoKitServiceError.albumCreationFailed
        }
        return PhotoAlbum(id: identifier, title: name, photoCount: 0)
    }

    /// Uses `PHAssetCollection.fetchAssetCollectionsContaining(_:with:options:)`
    /// — one PhotoKit call for exactly this question — filtered to
    /// `.albumRegular` to match `fetchAlbums()`'s own filtering.
    func albumIDs(containingAssetID assetID: String) async throws -> Set<String> {
        try Task.checkCancellation()
        guard let asset = fetchAsset(byLocalIdentifier: assetID) else { return [] }
        let collections = PHAssetCollection.fetchAssetCollectionsContaining(asset, with: .album, options: nil)
        var ids: Set<String> = []
        collections.enumerateObjects { collection, _, _ in
            guard collection.assetCollectionSubtype == .albumRegular else { return }
            ids.insert(collection.localIdentifier)
        }
        return ids
    }

    /// Permanently deletes the given assets. iOS itself presents a native
    /// confirmation alert for `PHAssetChangeRequest.deleteAssets`, on top of
    /// this app's own Deletion Review screen — the user confirms twice.
    /// Ids that no longer resolve to a real asset (already removed from the
    /// library some other way) are treated as already-deleted rather than an
    /// error, so the caller can still resolve them out of its pending queue.
    func deleteAssets(ids: [String]) async throws {
        try Task.checkCancellation()
        let assetsToDelete = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        guard assetsToDelete.count > 0 else { return }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assetsToDelete)
            } completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? PhotoKitServiceError.deletionFailed)
                }
            }
        }
    }

    // MARK: - Fetching

    private func fetchAllPhotoDescriptors() -> [PhotoTimelineGrouping.AssetDescriptor] {
        let result = PHAsset.fetchAssets(with: .image, options: nil)
        var descriptors: [PhotoTimelineGrouping.AssetDescriptor] = []
        descriptors.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            descriptors.append(.init(id: asset.localIdentifier, creationDate: asset.creationDate))
        }
        return descriptors
    }

    private func fetchAssets(matching group: TimelineGroup) -> [PhotoAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        if group.id == PhotoTimelineGrouping.unknownGroupID {
            options.predicate = NSPredicate(
                format: "mediaType == %d AND creationDate == nil",
                PHAssetMediaType.image.rawValue
            )
        } else {
            options.predicate = NSPredicate(
                format: "mediaType == %d AND creationDate >= %@ AND creationDate < %@",
                PHAssetMediaType.image.rawValue,
                group.interval.start as NSDate,
                group.interval.end as NSDate
            )
        }

        let result = PHAsset.fetchAssets(with: options)
        var assets: [PhotoAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            assets.append(Self.photoAsset(from: asset))
        }
        return assets
    }

    private func fetchAssets(inAlbumID albumID: String) throws -> [PhotoAsset] {
        let collections = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [albumID],
            options: nil
        )
        guard let collection = collections.firstObject else {
            throw PhotoKitServiceError.albumNotFound
        }

        let result = PHAsset.fetchAssets(in: collection, options: Self.imageFetchOptions())
        var assets: [PhotoAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            assets.append(Self.photoAsset(from: asset))
        }
        return assets
    }

    /// Caps how many assets a "Random" session pulls in. `result.count` is
    /// a cheap metadata query, but enumerating the whole library to build
    /// every `PhotoAsset` (each touching `location`, `creationDate`, etc.)
    /// is not — on a large library that scan is what made this source slow
    /// to open. Sampling indices first and reading only those keeps this
    /// fast regardless of library size.
    private static let randomSourceSampleSize = 200

    private func fetchShuffledLibraryAssets() -> [PhotoAsset] {
        let result = PHAsset.fetchAssets(with: .image, options: nil)
        var rng = SystemRandomNumberGenerator()
        let indices = RandomPhotoOrdering.sampleIndices(
            count: result.count,
            sampleSize: Self.randomSourceSampleSize,
            using: &rng
        )
        let assets = indices.map { Self.photoAsset(from: result.object(at: $0)) }
        return RandomPhotoOrdering.shuffled(assets, using: &rng)
    }

    private func fetchAsset(byLocalIdentifier id: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    }

    private static func imageFetchOptions() -> PHFetchOptions {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return options
    }

    private static func photoAsset(from asset: PHAsset) -> PhotoAsset {
        PhotoAsset(
            id: asset.localIdentifier,
            creationDate: asset.creationDate,
            isFavorite: asset.isFavorite,
            previewSymbolName: "photo",
            latitude: asset.location?.coordinate.latitude,
            longitude: asset.location?.coordinate.longitude
        )
    }

    // MARK: - Preview loading

    private func loadPreview(
        for asset: PHAsset,
        pixelWidth: Int,
        pixelHeight: Int,
        isHighQuality: Bool,
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws -> LocalPhotoPreview? {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = isHighQuality
        options.deliveryMode = isHighQuality ? .highQualityFormat : .opportunistic
        options.resizeMode = isHighQuality ? .exact : .fast
        options.isSynchronous = false
        if let onProgress {
            options.progressHandler = { progress, _, _, _ in
                onProgress(progress)
            }
        }

        let box = PhotoKitImageRequestBox()
        let imageManager = self.imageManager

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<LocalPhotoPreview?, Error>) in
                let requestID = imageManager.requestImage(
                    for: asset,
                    targetSize: CGSize(width: pixelWidth, height: pixelHeight),
                    contentMode: .aspectFill,
                    options: options
                ) { image, info in
                    box.complete(imageManager: imageManager) {
                        let wasCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                        if wasCancelled {
                            continuation.resume(throwing: CancellationError())
                            return
                        }
                        if info?[PHImageErrorKey] != nil {
                            continuation.resume(throwing: PhotoKitServiceError.imageLoadFailed)
                            return
                        }
                        let compressionQuality: CGFloat = isHighQuality ? 0.92 : 0.85
                        guard let image, let data = image.jpegData(compressionQuality: compressionQuality) else {
                            continuation.resume(returning: nil)
                            return
                        }
                        let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                        continuation.resume(
                            returning: LocalPhotoPreview(content: .encodedImageData(data), isDegraded: isDegraded)
                        )
                    }
                }
                box.register(requestID: requestID, imageManager: imageManager)
            }
        } onCancel: {
            box.cancel(imageManager: imageManager)
        }
    }
}
