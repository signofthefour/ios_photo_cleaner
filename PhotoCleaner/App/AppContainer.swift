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

    /// Backed by the real photo library via PhotoKit. Session persistence
    /// remains in-memory only; durable resume is a later milestone.
    static var live: AppContainer {
        AppContainer(
            library: PhotoKitPhotoLibraryService(),
            sessions: InMemorySessionRepository()
        )
    }

    func makeHomeViewModel() -> HomeViewModel {
        HomeViewModel(library: library, sessions: sessions)
    }

    func makeSourcePickerViewModel() -> SourcePickerViewModel {
        SourcePickerViewModel(library: library)
    }

    func makeCleanerViewModel(source: CleaningSource) -> CleanerViewModel {
        CleanerViewModel(source: source, library: library, sessions: sessions)
    }

    func makeDeletionReviewViewModel() -> DeletionReviewViewModel {
        DeletionReviewViewModel(sessions: sessions)
    }

    func makeSettingsViewModel() -> SettingsViewModel {
        SettingsViewModel(library: library)
    }
}
