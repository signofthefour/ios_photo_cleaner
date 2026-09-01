import SwiftUI

@MainActor
struct SourcePickerView: View {
    private enum Kind: String, CaseIterable {
        case timeline = "By Month"
        case albums = "Albums"
    }

    @State private var model: SourcePickerViewModel
    @State private var kind: Kind = .timeline
    let onSelect: (CleaningSource) -> Void

    init(model: SourcePickerViewModel, onSelect: @escaping (CleaningSource) -> Void) {
        _model = State(initialValue: model)
        self.onSelect = onSelect
    }

    var body: some View {
        VStack(spacing: PhotoCleanerTheme.spacing) {
            Picker("Source Type", selection: $kind) {
                ForEach(Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, PhotoCleanerTheme.spacing)

            content
        }
        .background(PhotoCleanerTheme.Palette.background)
        .navigationTitle("Choose Photos")
        .task { await model.load() }
        .task {
            for await _ in model.libraryChanges {
                await model.refreshIfNeeded()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView("Loading Sources")
                .frame(maxHeight: .infinity)
        case .empty:
            ContentUnavailableView("No Photos Found", systemImage: "photo.on.rectangle.angled")
        case let .failed(message):
            ContentUnavailableView {
                Label("Could Not Load Sources", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Retry") { Task { await model.load() } }
            }
        case let .content(timeline, albums):
            ScrollView {
                LazyVStack(spacing: 10) {
                    if kind == .timeline {
                        ForEach(timeline) { sourceRow(title: $0.title, count: $0.photoCount, source: .timeline($0)) }
                    } else {
                        ForEach(albums) { sourceRow(title: $0.title, count: $0.photoCount, source: .album($0)) }
                    }
                }
                .padding(PhotoCleanerTheme.spacing)
            }
        }
    }

    private func sourceRow(title: String, count: Int, source: CleaningSource) -> some View {
        HStack(spacing: PhotoCleanerTheme.spacing) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PhotoCleanerTheme.Palette.ink)
                Text("\(count) photos")
                    .font(.caption)
                    .foregroundStyle(PhotoCleanerTheme.Palette.inkSoft)
            }
            Spacer(minLength: 0)
            Button("Start") { onSelect(source) }
                .accessibilityHint("Starts a review of \(count) photos")
                .buttonStyle(.borderedProminent)
                .tint(PhotoCleanerTheme.Palette.ink)
        }
        .padding(14)
        .background(PhotoCleanerTheme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: PhotoCleanerTheme.rowCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: PhotoCleanerTheme.rowCornerRadius)
                .stroke(PhotoCleanerTheme.Palette.line, lineWidth: 1)
        }
    }
}
