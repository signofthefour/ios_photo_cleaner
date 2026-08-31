@MainActor
final class AppContainer {
    let library: any PhotoLibraryServiceProtocol
    let sessions: any SessionRepositoryProtocol

    init(
        library: any PhotoLibraryServiceProtocol,
        sessions: any SessionRepositoryProtocol
    ) {
        self.library = library
        self.sessions = sessions
    }

    static var liveMock: AppContainer {
        AppContainer(
            library: MockPhotoLibraryService.sample,
            sessions: InMemorySessionRepository()
        )
    }

    func makeHomeViewModel() -> HomeViewModel {
        HomeViewModel(library: library, sessions: sessions)
    }
}
