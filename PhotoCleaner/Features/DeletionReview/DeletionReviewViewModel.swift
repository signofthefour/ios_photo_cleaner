import Observation

private enum CachedDeletionPreview: Equatable, Sendable {
    case loading
    case available(LocalPhotoPreview)
    case unavailable
}

@MainActor
@Observable
final class DeletionReviewViewModel {
    private let library: any PhotoLibraryServiceProtocol
    private let sessions: any SessionRepositoryProtocol
    private var session: CleaningSession?
    private var previewsByAssetID: [String: CachedDeletionPreview] = [:]

    private(set) var pendingIDs: [String] = []
    private(set) var selectedIDs: Set<String> = []
    private(set) var isLoading = false
    private(set) var isDeleting = false
    private(set) var errorMessage: String?
    private(set) var deletionErrorMessage: String?
    private(set) var deletionSummaryMessage: String?
    private(set) var isCancelled = false

    init(library: any PhotoLibraryServiceProtocol, sessions: any SessionRepositoryProtocol) {
        self.library = library
        self.sessions = sessions
    }

    func preview(for assetID: String) -> LocalPhotoPreview? {
        guard case let .available(preview) = previewsByAssetID[assetID] else { return nil }
        return preview
    }

    /// Loads a thumbnail for every pending id that doesn't have one yet.
    /// Uses the same local-only preview contract as the Cleaner (no
    /// network access, no waiting for higher quality); a failed or
    /// unavailable thumbnail never blocks restore or deletion.
    func loadPreviews(pixelWidth: Int, pixelHeight: Int) async {
        let idsToLoad = pendingIDs.filter { previewsByAssetID[$0] == nil }
        guard !idsToLoad.isEmpty else { return }

        for id in idsToLoad {
            previewsByAssetID[id] = .loading
        }

        let library = self.library
        await withTaskGroup(of: (String, LocalPhotoPreview?).self) { group in
            for id in idsToLoad {
                group.addTask {
                    let request = PhotoPreviewRequest(assetID: id, pixelWidth: pixelWidth, pixelHeight: pixelHeight)
                    let preview = try? await library.fetchLocalPreview(for: request)
                    return (id, preview)
                }
            }
            for await (id, preview) in group {
                previewsByAssetID[id] = preview.map(CachedDeletionPreview.available) ?? .unavailable
            }
        }
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            session = try await sessions.loadCurrent()
            pendingIDs = session?.pendingDeletionIDs ?? []
            selectedIDs = Set(pendingIDs)
        } catch {
            errorMessage = "The pending deletion queue could not be loaded. Please try again."
        }
        isLoading = false
    }

    func restore(id: String) async throws {
        guard var session else { return }
        session.restorePendingDeletion(id: id)
        try await sessions.save(session)
        self.session = session
        pendingIDs = session.pendingDeletionIDs
        selectedIDs.remove(id)
    }

    /// Restores every pending-deletion asset in the queue at once. Independent
    /// of `selectedIDs`, which only governs what a subsequent `confirmDeletion()`
    /// would permanently delete — reusing it here would risk restoring the
    /// wrong set if the user had deselected items they meant to keep queued.
    func restoreAll() async throws {
        guard var session, !pendingIDs.isEmpty else { return }
        session.restoreAllPendingDeletions()
        try await sessions.save(session)
        self.session = session
        pendingIDs = session.pendingDeletionIDs
        selectedIDs.removeAll()
    }

    func selectAll() {
        selectedIDs = Set(pendingIDs)
    }

    func deselectAll() {
        selectedIDs.removeAll()
    }

    func cancel() {
        isCancelled = true
    }

    /// Permanently deletes the selected photos via the injected library
    /// service. Session state is only ever updated after that call
    /// succeeds — a failed or cancelled system deletion leaves the pending
    /// queue exactly as it was.
    func confirmDeletion() async {
        guard !isDeleting, !selectedIDs.isEmpty else { return }

        isDeleting = true
        deletionErrorMessage = nil
        defer { isDeleting = false }

        let idsToDelete = Array(selectedIDs)
        do {
            try await library.deleteAssets(ids: idsToDelete)

            if var session {
                session.markAssetsDeleted(ids: idsToDelete)
                try await sessions.save(session)
                self.session = session
            }
            pendingIDs.removeAll { idsToDelete.contains($0) }
            selectedIDs.subtract(idsToDelete)
            deletionSummaryMessage = idsToDelete.count == 1
                ? "1 photo deleted."
                : "\(idsToDelete.count) photos deleted."
        } catch {
            deletionErrorMessage = "These photos could not be deleted. Please try again."
        }
    }

    func dismissDeletionSummary() {
        deletionSummaryMessage = nil
    }

    func dismissDeletionError() {
        deletionErrorMessage = nil
    }
}
