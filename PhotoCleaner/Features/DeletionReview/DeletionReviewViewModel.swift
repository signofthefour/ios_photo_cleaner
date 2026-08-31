import Observation

@MainActor
@Observable
final class DeletionReviewViewModel {
    private let sessions: any SessionRepositoryProtocol
    private var session: CleaningSession?

    private(set) var pendingIDs: [String] = []
    private(set) var selectedIDs: Set<String> = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var confirmationMessage: String?
    private(set) var isCancelled = false

    init(sessions: any SessionRepositoryProtocol) {
        self.sessions = sessions
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

    func selectAll() {
        selectedIDs = Set(pendingIDs)
    }

    func deselectAll() {
        selectedIDs.removeAll()
    }

    func cancel() {
        isCancelled = true
    }

    func confirmMockDeletion() {
        confirmationMessage = "Deletion is disabled in Milestone 1. Your pending queue is unchanged."
    }

    func dismissConfirmation() {
        confirmationMessage = nil
    }
}
