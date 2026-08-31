import SwiftUI

@MainActor
struct CleanerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: CleanerViewModel

    init(model: CleanerViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        VStack(spacing: 20) {
            if model.isLoading {
                ProgressView("Loading Photos")
            } else if let message = model.errorMessage {
                ContentUnavailableView("Could Not Load Photo", systemImage: "exclamationmark.triangle", description: Text(message))
            } else if let asset = model.currentAsset {
                Text(model.progressText).font(.headline)
                PrintedPhotoCard(
                    preview: model.currentPreview,
                    metadata: PhotoCardMetadata(asset: asset),
                    previewStatusText: model.previewStatusText,
                    isFavorite: asset.isFavorite,
                    keepAction: { Task { await model.keepCurrent() } },
                    queueAction: { Task { await model.queueCurrentForDeletion() } }
                )
                    .gesture(DragGesture().onEnded { value in
                        if value.translation.width > 60 { Task { await model.keepCurrent() } }
                        if value.translation.width < -60 { Task { await model.queueCurrentForDeletion() } }
                    })
                Label(asset.isFavorite ? "Favorite" : "Not Favorite", systemImage: asset.isFavorite ? "heart.fill" : "heart")
                HStack {
                    Button("Queue for Deletion", systemImage: "trash") { Task { await model.queueCurrentForDeletion() } }
                        .accessibilityHint("Adds this photo to the pending deletion queue without deleting it")
                    Spacer()
                    Button("Keep", systemImage: "checkmark") { Task { await model.keepCurrent() } }
                        .accessibilityHint("Keeps this photo and advances to the next")
                }
            } else {
                ContentUnavailableView("Review Complete", systemImage: "checkmark.circle", description: Text("Review pending deletions before confirming anything."))
            }

            HStack {
                Button("Undo", systemImage: "arrow.uturn.backward") { model.undo() }
                    .disabled(model.session.currentPosition == 0)
                Button("Album Unavailable", systemImage: "rectangle.stack.badge.plus") {}
                    .disabled(true)
                Spacer()
                Button("Close & Save") {
                    Task { try? await model.save(); dismiss() }
                }
            }
        }
        .padding()
        .navigationTitle("Cleaner")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .task(id: model.currentAsset?.id) {
            await model.loadCurrentPreview(pixelWidth: 900, pixelHeight: 900)
        }
    }
}
