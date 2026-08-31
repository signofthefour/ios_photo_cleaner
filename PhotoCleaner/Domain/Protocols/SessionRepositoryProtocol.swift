protocol SessionRepositoryProtocol: Sendable {
    func loadCurrent() async throws -> CleaningSession?
    func save(_ session: CleaningSession) async throws
    func removeCurrent() async throws
}
