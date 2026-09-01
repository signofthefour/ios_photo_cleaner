import Observation

@MainActor
@Observable
final class HomeViewModel {
    private let library: any PhotoLibraryServiceProtocol
    private let sessions: any SessionRepositoryProtocol

    private(set) var isLoading = false
    private(set) var accessStatus: PhotoAccessStatus = .notDetermined
    private(set) var savedSession: CleaningSession?
    private(set) var pendingDeletionCount = 0
    private(set) var errorMessage: String?

    init(
        library: any PhotoLibraryServiceProtocol,
        sessions: any SessionRepositoryProtocol
    ) {
        self.library = library
        self.sessions = sessions
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        accessStatus = await library.requestAuthorization()

        do {
            let saved = try await sessions.loadCurrent()
            // A finished review is never offered as "Continue" — its source
            // starts fresh next time. Anything it queued for deletion still
            // counts, independent of whether that review is done.
            savedSession = (saved?.isComplete == false) ? saved : nil
            pendingDeletionCount = saved?.pendingDeletionIDs.count ?? 0
        } catch {
            savedSession = nil
            pendingDeletionCount = 0
            errorMessage = "Your saved cleaning session could not be loaded. Please try again."
        }

        isLoading = false
    }
}
