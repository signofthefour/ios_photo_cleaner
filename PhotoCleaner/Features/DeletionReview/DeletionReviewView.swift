import SwiftUI

@MainActor
struct DeletionReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: DeletionReviewViewModel
    @State private var isConfirmingDelete = false
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    init(model: DeletionReviewViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        Group {
            if model.isLoading {
                ProgressView("Loading Queue")
            } else if let error = model.errorMessage {
                ContentUnavailableView("Could Not Load Queue", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if model.pendingIDs.isEmpty {
                ContentUnavailableView("Queue Is Empty", systemImage: "trash.slash", description: Text("No photos are pending deletion."))
            } else {
                ScrollView {
                    Text("Review every identifier below before any permanent deletion request.")
                        .font(.callout)
                        .foregroundStyle(PhotoCleanerTheme.Palette.inkSoft)
                        .padding(.horizontal)
                        .padding(.top, PhotoCleanerTheme.spacing)
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(model.pendingIDs, id: \.self) { id in
                            VStack(spacing: 6) {
                                ZStack(alignment: .topTrailing) {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(PhotoCleanerTheme.Palette.line)
                                        .aspectRatio(1, contentMode: .fit)
                                        .overlay {
                                            thumbnail(for: model.preview(for: id))
                                        }
                                        .clipShape(RoundedRectangle(cornerRadius: 12))

                                    if model.selectedIDs.contains(id) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.callout)
                                            .foregroundStyle(.white, PhotoCleanerTheme.Palette.ink)
                                            .padding(6)
                                    }
                                }

                                Text(id)
                                    .font(.caption2)
                                    .foregroundStyle(PhotoCleanerTheme.Palette.inkSoft)
                                    .lineLimit(1)

                                Button("Restore") { Task { try? await model.restore(id: id) } }
                                    .font(.caption)
                                    .disabled(model.isDeleting)
                            }
                            .padding(10)
                            .background(PhotoCleanerTheme.Palette.surface)
                            .clipShape(RoundedRectangle(cornerRadius: PhotoCleanerTheme.rowCornerRadius))
                            .overlay {
                                RoundedRectangle(cornerRadius: PhotoCleanerTheme.rowCornerRadius)
                                    .stroke(PhotoCleanerTheme.Palette.line, lineWidth: 1)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityValue(model.selectedIDs.contains(id) ? "Selected" : "Not selected")
                        }
                    }.padding()
                }
            }
        }
        .background(PhotoCleanerTheme.Palette.background)
        .navigationTitle("Pending Deletion")
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button("Select All") { model.selectAll() }
                    .disabled(model.isDeleting)
                Button("Deselect All") { model.deselectAll() }
                    .disabled(model.isDeleting)
                Button("Restore All") { Task { try? await model.restoreAll() } }
                    .disabled(model.isDeleting)
                Spacer()
                Button("Cancel") { model.cancel(); dismiss() }
                    .tint(PhotoCleanerTheme.Palette.inkSoft)
                    .disabled(model.isDeleting)
                deleteButton
            }
        }
        .confirmationDialog(
            deleteConfirmationTitle,
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Permanently", role: .destructive) {
                Task { await model.confirmDeletion() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone from Photo Cleaner. iOS will also ask you to confirm.")
        }
        .alert("Deleted", isPresented: Binding(
            get: { model.deletionSummaryMessage != nil },
            set: { if !$0 { model.dismissDeletionSummary() } }
        )) {
            Button("OK") {}
        } message: {
            Text(model.deletionSummaryMessage ?? "")
        }
        .alert("Could Not Delete", isPresented: Binding(
            get: { model.deletionErrorMessage != nil },
            set: { if !$0 { model.dismissDeletionError() } }
        )) {
            Button("OK") {}
        } message: {
            Text(model.deletionErrorMessage ?? "")
        }
        .task { await model.load() }
        .task(id: model.pendingIDs) {
            await model.loadPreviews(pixelWidth: 300, pixelHeight: 300)
        }
    }

    private var deleteConfirmationTitle: String {
        "Permanently delete \(model.selectedIDs.count) photo\(model.selectedIDs.count == 1 ? "" : "s")?"
    }

    @ViewBuilder
    private func thumbnail(for preview: LocalPhotoPreview?) -> some View {
        switch preview?.content {
        case let .systemSymbol(name):
            Image(systemName: name)
                .resizable()
                .scaledToFit()
                .padding(16)
                .foregroundStyle(PhotoCleanerTheme.Palette.inkSoft)
        case let .encodedImageData(data):
            if let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholderThumbnail
            }
        case nil:
            placeholderThumbnail
        }
    }

    private var placeholderThumbnail: some View {
        Image(systemName: "photo")
            .font(.title2)
            .foregroundStyle(PhotoCleanerTheme.Palette.inkSoft)
    }

    @ViewBuilder
    private var deleteButton: some View {
        if model.isDeleting {
            ProgressView()
                .accessibilityLabel("Deleting photos")
        } else {
            Button("Delete \(model.selectedIDs.count) Photo\(model.selectedIDs.count == 1 ? "" : "s")") {
                isConfirmingDelete = true
            }
            .disabled(model.selectedIDs.isEmpty)
            .tint(PhotoCleanerTheme.Palette.delete)
        }
    }
}
