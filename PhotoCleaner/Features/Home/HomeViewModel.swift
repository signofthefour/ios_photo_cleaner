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
            savedSession = try await sessions.loadCurrent()
            pendingDeletionCount = savedSession?.pendingDeletionIDs.count ?? 0
        } catch {
            savedSession = nil
            pendingDeletionCount = 0
            errorMessage = "Your saved cleaning session could not be loaded. Please try again."
        }

        isLoading = false
    }
}
