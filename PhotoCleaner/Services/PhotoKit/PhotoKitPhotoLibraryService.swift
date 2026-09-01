import Photos
import UIKit

enum PhotoKitServiceError: Error, Equatable, Sendable {
    case albumNotFound
    case imageLoadFailed
    /// A mutation that belongs to a later milestone. Thrown rather than
    /// silently no-op'd or performed for real, since none of these are wired
    /// to any UI action in this milestone.
    case notImplemented(String)
}

/// `PhotoLibraryServiceProtocol` backed by the real PhotoKit library.
///
/// Scope for this milestone: authorization and read-only browsing
/// (timeline groups, albums, assets, local previews). Favorite/album
/// mutation and deletion are later milestones and intentionally throw
/// `.notImplemented` here rather than perform a real library mutation.
///
/// Preview requests always set `isNetworkAccessAllowed = false`: a
/// cloud-optimized asset is never downloaded to satisfy a swipe decision,
/// and only the first locally available result is used even when
/// PhotoKit's `.opportunistic` delivery mode would later deliver a
/// higher-quality rendition.
final class PhotoKitPhotoLibraryService: PhotoLibraryServiceProtocol, @unchecked Sendable {
    private let imageManager: PHImageManager

    init(imageManager: PHImageManager = .default()) {
        self.imageManager = imageManager
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
        }
    }

    func fetchLocalPreview(for request: PhotoPreviewRequest) async throws -> LocalPhotoPreview? {
        guard let asset = fetchAsset(byLocalIdentifier: request.assetID) else { return nil }
        return try await loadPreview(
            for: asset,
            pixelWidth: request.pixelWidth,
            pixelHeight: request.pixelHeight
        )
    }

    func setFavorite(_ favorite: Bool, assetID: String) async throws {
        throw PhotoKitServiceError.notImplemented("Favorite mutation ships in Milestone 4")
    }

    func addAsset(_ assetID: String, toAlbum albumID: String) async throws {
        throw PhotoKitServiceError.notImplemented("Album assignment ships in Milestone 4")
    }

    func createAlbum(named name: String) async throws -> PhotoAlbum {
        throw PhotoKitServiceError.notImplemented("Album creation ships in Milestone 4")
    }

    func deleteAssets(ids: [String]) async throws {
        throw PhotoKitServiceError.notImplemented(
            "Permanent deletion ships in Milestone 5 behind a separate confirmation"
        )
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
        pixelHeight: Int
    ) async throws -> LocalPhotoPreview? {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isSynchronous = false

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
                        guard let image, let data = image.jpegData(compressionQuality: 0.85) else {
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
