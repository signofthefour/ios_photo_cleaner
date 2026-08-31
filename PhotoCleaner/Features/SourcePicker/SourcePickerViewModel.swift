import Observation

@MainActor
@Observable
final class SourcePickerViewModel {
    enum State: Equatable {
        case loading
        case content(timeline: [TimelineGroup], albums: [PhotoAlbum])
        case empty
        case failed(message: String)
    }

    private let library: any PhotoLibraryServiceProtocol
    private(set) var state: State = .loading

    init(library: any PhotoLibraryServiceProtocol) {
        self.library = library
    }

    func load() async {
        state = .loading
        do {
            async let timeline = library.fetchTimelineGroups()
            async let albums = library.fetchAlbums()
            let (loadedTimeline, loadedAlbums) = try await (timeline, albums)
            state = loadedTimeline.isEmpty && loadedAlbums.isEmpty
                ? .empty
                : .content(timeline: loadedTimeline, albums: loadedAlbums)
        } catch {
            state = .failed(message: "Photo sources could not be loaded. Please try again.")
        }
    }

    func photoCount(for source: CleaningSource) -> Int {
        switch source {
        case let .timeline(group): group.photoCount
        case let .album(album): album.photoCount
        }
    }
}
