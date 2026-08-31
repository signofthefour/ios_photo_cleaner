actor InMemorySessionRepository: SessionRepositoryProtocol {
    private var currentSession: CleaningSession?

    init(initial: CleaningSession? = nil) {
        currentSession = initial
    }

    func loadCurrent() async throws -> CleaningSession? {
        currentSession
    }

    func save(_ session: CleaningSession) async throws {
        currentSession = session
    }

    func removeCurrent() async throws {
        currentSession = nil
    }
}
