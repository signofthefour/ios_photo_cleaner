import Foundation
import Observation

struct CleanerCardItem: Identifiable, Equatable, Sendable {
    let asset: PhotoAsset
    let preview: LocalPhotoPreview?
    let previewStatusText: String?

    var id: String { asset.id }
}

private enum CachedPreview: Equatable, Sendable {
    case loading
    case available(LocalPhotoPreview, isHighQuality: Bool)
    case unavailable
}

private enum PreviewLoadResult: Sendable {
    case completed(assetID: String, preview: LocalPhotoPreview?, isHighQuality: Bool)
    case failed(assetID: String)
    case cancelled(assetID: String)

    var assetID: String {
        switch self {
        case let .completed(assetID, _, _), let .failed(assetID), let .cancelled(assetID):
            assetID
        }
    }
}

@MainActor
@Observable
final class CleanerViewModel {
    private let source: CleaningSource
    private let library: any PhotoLibraryServiceProtocol
    private let sessions: any SessionRepositoryProtocol
    private var previewsByAssetID: [String: CachedPreview] = [:]
    private var retainedPreviewStatusText: String?
    private var downloadingFromiCloudAssetIDs: Set<String> = []

    private(set) var session: CleaningSession
    private(set) var assets: [PhotoAsset] = []
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var errorMessage: String?
    private(set) var saveErrorMessage: String?
    private(set) var favoriteErrorMessage: String?

    init(
        source: CleaningSource,
        library: any PhotoLibraryServiceProtocol,
        sessions: any SessionRepositoryProtocol
    ) {
        self.source = source
        self.library = library
        self.sessions = sessions
        let now = Date()
        session = CleaningSession(
            id: UUID(), source: source, orderedAssetIDs: [], currentPosition: 0,
            decisions: [:], pendingDeletionIDs: [], unavailableAssetIDs: [],
            createdAt: now, updatedAt: now
        )
    }

    var libraryChanges: AsyncStream<Void> { library.libraryChanges }

    var currentAsset: PhotoAsset? {
        guard session.orderedAssetIDs.indices.contains(session.currentPosition) else { return nil }
        let id = session.orderedAssetIDs[session.currentPosition]
        return assets.first { $0.id == id }
    }

    var currentPreview: LocalPhotoPreview? {
        guard let assetID = currentAsset?.id else { return nil }
        return preview(for: assetID)
    }

    var previewStatusText: String? {
        guard let assetID = currentAsset?.id else { return retainedPreviewStatusText }
        return previewStatus(for: assetID)
    }

    var visibleCards: [CleanerCardItem] {
        let availableByID = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
        return session.orderedAssetIDs
            .dropFirst(session.currentPosition)
            .prefix(3)
            .compactMap { id in
                guard let asset = availableByID[id] else { return nil }
                return CleanerCardItem(
                    asset: asset,
                    preview: preview(for: id),
                    previewStatusText: previewStatus(for: id)
                )
            }
    }

    var progressText: String {
        let count = session.orderedAssetIDs.count
        guard count > 0 else { return "0 of 0" }
        return "\(min(session.currentPosition + 1, count)) of \(count)"
    }

    /// Fraction of the session already decided, for a visual progress bar.
    var progressFraction: Double {
        let count = session.orderedAssetIDs.count
        guard count > 0 else { return 0 }
        return Double(min(session.currentPosition, count)) / Double(count)
    }

    func load() async {
        previewsByAssetID.removeAll()
        retainedPreviewStatusText = nil
        isLoading = true
        errorMessage = nil
        do {
            let fetchedAssets = try await library.fetchAssets(for: source)
            assets = fetchedAssets
            let saved = try await sessions.loadCurrent()
            if let saved, saved.source == source, !saved.isComplete {
                session = saved
                skipUnavailableCurrentAssets()
            } else {
                // A finished review (or one for a different source) is never
                // resumed — its source starts over fresh. Any photos it
                // already queued for deletion are not resumable state, so
                // they carry forward rather than silently disappearing
                // before Deletion Review ever shows them. Their `.pendingDelete`
                // decision carries forward too, since restore/delete rely on
                // `decisions[id] == .pendingDelete` matching `pendingDeletionIDs`.
                let now = Date()
                let carriedPendingDeletionIDs = saved?.pendingDeletionIDs ?? []
                let carriedDecisions = Dictionary(
                    uniqueKeysWithValues: carriedPendingDeletionIDs.map { ($0, PhotoDecision.pendingDelete) }
                )
                session = CleaningSession(
                    id: UUID(), source: source, orderedAssetIDs: fetchedAssets.map(\.id),
                    currentPosition: 0, decisions: carriedDecisions, pendingDeletionIDs: carriedPendingDeletionIDs,
                    unavailableAssetIDs: [], createdAt: now, updatedAt: now
                )
            }
        } catch {
            errorMessage = "This cleaning session could not be loaded. Please try again."
        }
        isLoading = false
    }

    func keepCurrent() async {
        decideCurrent(.keep)
    }

    func queueCurrentForDeletion() async {
        decideCurrent(.pendingDelete)
    }

    func undo() {
        _ = session.undoLastDecision()
        retainedPreviewStatusText = nil
    }

    func saveForExit() async -> Bool {
        guard !isSaving else { return false }

        isSaving = true
        saveErrorMessage = nil
        defer { isSaving = false }

        do {
            try await sessions.save(session)
            return true
        } catch {
            saveErrorMessage = "This cleaning session could not be saved. Please try again."
            return false
        }
    }

    func clearSaveError() {
        saveErrorMessage = nil
    }

    /// Flips `isFavorite` immediately, then confirms with PhotoKit; a
    /// failure flips it back and surfaces a recoverable error. Unlike
    /// keep/queue decisions, favorite status lives entirely in the photo
    /// library, not in `CleaningSession` — there is nothing to save here.
    func toggleFavorite() async {
        guard let assetID = currentAsset?.id,
              let index = assets.firstIndex(where: { $0.id == assetID }) else { return }
        let newValue = !assets[index].isFavorite
        assets[index].isFavorite = newValue
        favoriteErrorMessage = nil
        do {
            try await library.setFavorite(newValue, assetID: assetID)
        } catch {
            assets[index].isFavorite = !newValue
            favoriteErrorMessage = "This photo's favorite status could not be updated. Please try again."
        }
    }

    func clearFavoriteError() {
        favoriteErrorMessage = nil
    }

    func makeAlbumPickerViewModel(assetID: String) -> AlbumPickerViewModel {
        AlbumPickerViewModel(assetID: assetID, library: library)
    }

    /// Re-fetches this source's assets and re-applies the existing
    /// unavailable-asset handling, so a photo deleted elsewhere (the
    /// system Photos app, another device) is skipped rather than leaving
    /// the session stuck on an asset that no longer exists. Best-effort:
    /// a failed refresh is silently ignored rather than surfaced, since
    /// this runs in the background and the current session state remains
    /// valid either way.
    func handleLibraryChange() async {
        guard let refreshedAssets = try? await library.fetchAssets(for: source) else { return }
        assets = refreshedAssets
        skipUnavailableCurrentAssets()
    }

    /// Loads the current asset's preview in high quality: this is the
    /// single photo on screen in detail, unlike the card-stack prefetch
    /// below.
    func loadCurrentPreview(pixelWidth: Int, pixelHeight: Int) async {
        guard let assetID = currentAsset?.id else { return }
        await loadPreviews(
            assetIDs: [assetID],
            highQualityAssetIDs: [assetID],
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight
        )
    }

    /// Prefetches the current card plus its upcoming successors. The
    /// current card and the one right after it are both requested in high
    /// quality, so the incoming card is already sharp the instant a swipe
    /// lands on it — anything further out is a fast local-only prefetch
    /// that upgrades once it itself becomes current or next-up.
    func loadVisiblePreviews(pixelWidth: Int, pixelHeight: Int) async {
        let cards = visibleCards
        let highQualityAssetIDs = Set(cards.prefix(2).map(\.id))
        await loadPreviews(
            assetIDs: cards.map(\.id),
            highQualityAssetIDs: highQualityAssetIDs,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight
        )
    }

    private func decideCurrent(_ decision: PhotoDecision) {
        guard let currentAsset else { return }
        let previousAssetID = currentAsset.id
        let previousPreviewStatusText = previewStatus(for: previousAssetID)
        do {
            try session.decide(decision, assetID: currentAsset.id)
            skipUnavailableCurrentAssets()
            if self.currentAsset?.id != previousAssetID {
                retainedPreviewStatusText = self.currentAsset == nil
                    ? previousPreviewStatusText
                    : nil
            }
        } catch {
            errorMessage = "That photo could not be updated. Please try again."
        }
    }

    /// An asset already cached at low quality is reloaded when it's now
    /// requested as high quality (it just became the current card); an
    /// unavailable or already-loading asset is never retried.
    private func loadPreviews(
        assetIDs: [String],
        highQualityAssetIDs: Set<String>,
        pixelWidth: Int,
        pixelHeight: Int
    ) async {
        let idsToLoad = assetIDs.filter { assetID in
            switch previewsByAssetID[assetID] {
            case nil:
                true
            case let .available(_, isHighQuality):
                highQualityAssetIDs.contains(assetID) && !isHighQuality
            case .loading, .unavailable:
                false
            }
        }
        guard !idsToLoad.isEmpty else { return }

        for assetID in idsToLoad {
            previewsByAssetID[assetID] = .loading
        }

        let library = self.library
        await withTaskGroup(of: PreviewLoadResult.self) { group in
            for assetID in idsToLoad {
                let isHighQuality = highQualityAssetIDs.contains(assetID)
                group.addTask { [weak self] in
                    do {
                        let request = PhotoPreviewRequest(
                            assetID: assetID,
                            pixelWidth: pixelWidth,
                            pixelHeight: pixelHeight,
                            isHighQuality: isHighQuality
                        )
                        let preview = try await library.fetchLocalPreview(for: request) { _ in
                            Task { @MainActor in
                                self?.downloadingFromiCloudAssetIDs.insert(assetID)
                            }
                        }
                        return .completed(assetID: assetID, preview: preview, isHighQuality: isHighQuality)
                    } catch is CancellationError {
                        return .cancelled(assetID: assetID)
                    } catch {
                        return .failed(assetID: assetID)
                    }
                }
            }

            for await result in group {
                downloadingFromiCloudAssetIDs.remove(result.assetID)
                guard previewsByAssetID[result.assetID] == .loading else { continue }
                switch result {
                case let .completed(_, preview, isHighQuality):
                    previewsByAssetID[result.assetID] = preview.map {
                        CachedPreview.available($0, isHighQuality: isHighQuality)
                    } ?? .unavailable
                case .failed:
                    previewsByAssetID[result.assetID] = .unavailable
                case .cancelled:
                    previewsByAssetID[result.assetID] = nil
                }
            }
        }
    }

    private func preview(for assetID: String) -> LocalPhotoPreview? {
        guard case let .available(preview, _) = previewsByAssetID[assetID] else { return nil }
        return preview
    }

    private func previewStatus(for assetID: String) -> String? {
        if downloadingFromiCloudAssetIDs.contains(assetID) {
            return "Downloading from iCloud…"
        }
        guard previewsByAssetID[assetID] == .unavailable else { return nil }
        return "Local preview unavailable"
    }

    private func skipUnavailableCurrentAssets() {
        let availableIDs = Set(assets.map(\.id))
        while session.orderedAssetIDs.indices.contains(session.currentPosition) {
            let id = session.orderedAssetIDs[session.currentPosition]
            guard !availableIDs.contains(id) else { break }
            session.skipUnavailableAsset(id: id)
        }
    }
}
