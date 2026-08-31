import Foundation
import Observation

@MainActor
@Observable
final class CleanerViewModel {
    private let source: CleaningSource
    private let library: any PhotoLibraryServiceProtocol
    private let sessions: any SessionRepositoryProtocol

    private(set) var session: CleaningSession
    private(set) var assets: [PhotoAsset] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

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
        _ = session.undoLastDecision()
    }

    func save() async throws {
        try await sessions.save(session)
    }

    private func decideCurrent(_ decision: PhotoDecision) {
        guard let currentAsset else { return }
        do {
            try session.decide(decision, assetID: currentAsset.id)
            skipUnavailableCurrentAssets()
        } catch {
            errorMessage = "That photo could not be updated. Please try again."
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
