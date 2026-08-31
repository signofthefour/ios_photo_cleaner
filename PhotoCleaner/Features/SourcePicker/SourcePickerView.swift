import SwiftUI

@MainActor
struct SourcePickerView: View {
    private enum Kind: String, CaseIterable {
        case timeline = "By Date"
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
        VStack {
            Picker("Source Type", selection: $kind) {
                ForEach(Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            content
        }
        .navigationTitle("Choose Photos")
        .task { await model.load() }
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
            List {
                if kind == .timeline {
                    ForEach(timeline) { sourceRow(title: $0.title, count: $0.photoCount, source: .timeline($0)) }
                } else {
                    ForEach(albums) { sourceRow(title: $0.title, count: $0.photoCount, source: .album($0)) }
                }
            }
        }
    }

    private func sourceRow(title: String, count: Int, source: CleaningSource) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title).font(.headline)
                Text("\(count) photos").foregroundStyle(.secondary)
            }
            Spacer()
            Button("Start") { onSelect(source) }
                .accessibilityHint("Starts a review of \(count) photos")
        }
    }
}
