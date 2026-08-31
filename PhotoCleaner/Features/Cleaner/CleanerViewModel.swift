import Foundation
import Observation

@MainActor
@Observable
final class CleanerViewModel {
    private let source: CleaningSource
    private let library: any PhotoLibraryServiceProtocol
    private let sessions: any SessionRepositoryProtocol
    private var previewGeneration = 0

    private(set) var session: CleaningSession
    private(set) var assets: [PhotoAsset] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var currentPreview: LocalPhotoPreview?
    private(set) var previewStatusText: String?

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

    var currentAsset: PhotoAsset? {
        guard session.orderedAssetIDs.indices.contains(session.currentPosition) else { return nil }
        let id = session.orderedAssetIDs[session.currentPosition]
        return assets.first { $0.id == id }
    }

    var progressText: String {
        let count = session.orderedAssetIDs.count
        guard count > 0 else { return "0 of 0" }
        return "\(min(session.currentPosition + 1, count)) of \(count)"
    }

    func load() async {
        invalidatePreview()
        isLoading = true
        errorMessage = nil
        do {
            let fetchedAssets = try await library.fetchAssets(for: source)
            assets = fetchedAssets
            if let saved = try await sessions.loadCurrent(), saved.source == source {
                session = saved
                skipUnavailableCurrentAssets()
            } else {
                let now = Date()
                session = CleaningSession(
                    id: UUID(), source: source, orderedAssetIDs: fetchedAssets.map(\.id),
                    currentPosition: 0, decisions: [:], pendingDeletionIDs: [],
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
        let previousAssetID = currentAsset?.id
        _ = session.undoLastDecision()
        if currentAsset?.id != previousAssetID {
            invalidatePreview()
        }
    }

    func save() async throws {
        try await sessions.save(session)
    }

    func loadCurrentPreview(pixelWidth: Int, pixelHeight: Int) async {
        previewGeneration += 1
        let generation = previewGeneration
        guard let assetID = currentAsset?.id else {
            currentPreview = nil
            return
        }

        do {
            let request = PhotoPreviewRequest(
                assetID: assetID,
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight
            )
            let preview = try await library.fetchLocalPreview(for: request)
            guard generation == previewGeneration, currentAsset?.id == assetID else { return }
            currentPreview = preview
            previewStatusText = preview == nil ? "Local preview unavailable" : nil
        } catch is CancellationError {
            return
        } catch {
            guard generation == previewGeneration, currentAsset?.id == assetID else { return }
            currentPreview = nil
            previewStatusText = "Local preview unavailable"
        }
    }

    private func decideCurrent(_ decision: PhotoDecision) {
        guard let currentAsset else { return }
        let previousAssetID = currentAsset.id
        do {
            try session.decide(decision, assetID: currentAsset.id)
            skipUnavailableCurrentAssets()
            if self.currentAsset?.id != previousAssetID {
                invalidatePreview(clearStatus: self.currentAsset != nil)
            }
        } catch {
            errorMessage = "That photo could not be updated. Please try again."
        }
    }

    private func invalidatePreview(clearStatus: Bool = true) {
        previewGeneration += 1
        currentPreview = nil
        if clearStatus {
            previewStatusText = nil
        }
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
