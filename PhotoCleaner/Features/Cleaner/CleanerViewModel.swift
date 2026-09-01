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
    case available(LocalPhotoPreview)
    case unavailable
}

private enum PreviewLoadResult: Sendable {
    case completed(assetID: String, preview: LocalPhotoPreview?)
    case failed(assetID: String)
    case cancelled(assetID: String)

    var assetID: String {
        switch self {
        case let .completed(assetID, _), let .failed(assetID), let .cancelled(assetID):
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

    private(set) var session: CleaningSession
    private(set) var assets: [PhotoAsset] = []
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var errorMessage: String?
    private(set) var saveErrorMessage: String?

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
                // before Deletion Review ever shows them.
                let now = Date()
                session = CleaningSession(
                    id: UUID(), source: source, orderedAssetIDs: fetchedAssets.map(\.id),
                    currentPosition: 0, decisions: [:], pendingDeletionIDs: saved?.pendingDeletionIDs ?? [],
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

    func loadCurrentPreview(pixelWidth: Int, pixelHeight: Int) async {
        guard let assetID = currentAsset?.id else { return }
        await loadPreviews(
            assetIDs: [assetID],
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight
        )
    }

    func loadVisiblePreviews(pixelWidth: Int, pixelHeight: Int) async {
        await loadPreviews(
            assetIDs: visibleCards.map(\.id),
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

    private func loadPreviews(
        assetIDs: [String],
        pixelWidth: Int,
        pixelHeight: Int
    ) async {
        let idsToLoad = assetIDs.filter { previewsByAssetID[$0] == nil }
        guard !idsToLoad.isEmpty else { return }

        for assetID in idsToLoad {
            previewsByAssetID[assetID] = .loading
        }

        let library = self.library
        await withTaskGroup(of: PreviewLoadResult.self) { group in
            for assetID in idsToLoad {
                group.addTask {
                    do {
                        let request = PhotoPreviewRequest(
                            assetID: assetID,
                            pixelWidth: pixelWidth,
                            pixelHeight: pixelHeight
                        )
                        let preview = try await library.fetchLocalPreview(for: request)
                        return .completed(assetID: assetID, preview: preview)
                    } catch is CancellationError {
                        return .cancelled(assetID: assetID)
                    } catch {
                        return .failed(assetID: assetID)
                    }
                }
            }

            for await result in group {
                guard previewsByAssetID[result.assetID] == .loading else { continue }
                switch result {
                case let .completed(_, preview):
                    previewsByAssetID[result.assetID] = preview.map(CachedPreview.available)
                        ?? .unavailable
                case .failed:
                    previewsByAssetID[result.assetID] = .unavailable
                case .cancelled:
                    previewsByAssetID[result.assetID] = nil
                }
            }
        }
    }

    private func preview(for assetID: String) -> LocalPhotoPreview? {
        guard case let .available(preview) = previewsByAssetID[assetID] else { return nil }
        return preview
    }

    private func previewStatus(for assetID: String) -> String? {
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
