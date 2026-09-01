import SwiftUI

@MainActor
struct AlbumPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: AlbumPickerViewModel
    @State private var isPresentingNewAlbumAlert = false
    @State private var newAlbumName = ""

    init(model: AlbumPickerViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        content
            .background(PhotoCleanerTheme.Palette.background)
            .navigationTitle("Add to Album")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $model.searchText, prompt: "Search Albums")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("New Album", systemImage: "plus") {
                        newAlbumName = ""
                        isPresentingNewAlbumAlert = true
                    }
                    .disabled(model.isCreatingAlbum)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("New Album", isPresented: $isPresentingNewAlbumAlert) {
                TextField("Album Name", text: $newAlbumName)
                Button("Create") {
                    Task { await model.createAlbum(named: newAlbumName) }
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Could Not Add Photo", isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.dismissError() } }
            )) {
                Button("OK") {}
            } message: {
                Text(model.errorMessage ?? "")
            }
            .alert("Could Not Create Album", isPresented: Binding(
                get: { model.createAlbumErrorMessage != nil },
                set: { if !$0 { model.dismissCreateAlbumError() } }
            )) {
                Button("OK") {}
            } message: {
                Text(model.createAlbumErrorMessage ?? "")
            }
            .task { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView("Loading Albums")
                .frame(maxHeight: .infinity)
        case .empty:
            ContentUnavailableView("No Albums Yet", systemImage: "rectangle.stack.badge.plus", description: Text("Create one to add this photo to it."))
        case let .failed(message):
            ContentUnavailableView {
                Label("Could Not Load Albums", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Retry") { Task { await model.load() } }
            }
        case .content:
            List(model.filteredAlbums) { album in
                albumRow(album)
            }
            .listStyle(.plain)
        }
    }

    private func albumRow(_ album: PhotoAlbum) -> some View {
        let isMember = model.isMember(of: album)
        return Button {
            Task { await model.add(to: album) }
        } label: {
            HStack(spacing: PhotoCleanerTheme.spacing) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(album.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PhotoCleanerTheme.Palette.ink)
                    Text("\(album.photoCount) photos")
                        .font(.caption)
                        .foregroundStyle(PhotoCleanerTheme.Palette.inkSoft)
                }
                Spacer(minLength: 0)
                if isMember {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(PhotoCleanerTheme.Palette.keep)
                }
            }
        }
        .disabled(isMember)
        .accessibilityValue(isMember ? "Already added" : "Not added")
        .accessibilityHint(isMember ? "" : "Adds this photo to \(album.title)")
    }
}
