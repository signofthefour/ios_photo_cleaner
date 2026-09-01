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
                VStack(spacing: 6) {
                    Text(model.progressText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PhotoCleanerTheme.Palette.inkSoft)
                    ProgressView(value: model.progressFraction)
                        .tint(PhotoCleanerTheme.Palette.ink)
                        .frame(maxWidth: 260)
                }
                SwipeCardStack(
                    cards: model.visibleCards,
                    keepAction: { await model.keepCurrent() },
                    queueAction: { await model.queueCurrentForDeletion() }
                )
                Label(asset.isFavorite ? "Favorite" : "Not Favorite", systemImage: asset.isFavorite ? "heart.fill" : "heart")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(
                        asset.isFavorite ? PhotoCleanerTheme.Palette.delete : PhotoCleanerTheme.Palette.inkSoft
                    )
            } else {
                ContentUnavailableView("Review Complete", systemImage: "checkmark.circle", description: Text("Review pending deletions before confirming anything."))
            }

            HStack(spacing: PhotoCleanerTheme.spacing) {
                Button("Undo", systemImage: "arrow.uturn.backward") { model.undo() }
                    .buttonStyle(CleanerCircularButtonStyle(tint: PhotoCleanerTheme.Palette.inkSoft, isBordered: false))
                    .disabled(model.session.currentPosition == 0)
                Button("Album Unavailable", systemImage: "rectangle.stack.badge.plus") {}
                    .buttonStyle(CleanerCircularButtonStyle(tint: PhotoCleanerTheme.Palette.inkSoft, isBordered: false))
                    .disabled(true)
                Spacer()
                Button(action: saveAndDismiss) {
                    if model.isSaving {
                        ProgressView()
                            .accessibilityLabel("Saving session")
                    } else {
                        Text("Close & Save")
                    }
                }
                .disabled(model.isSaving)
                .tint(PhotoCleanerTheme.Palette.ink)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PhotoCleanerTheme.Palette.background)
        .navigationTitle("Cleaner")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: saveAndDismiss) {
                    Label("Close Cleaner", systemImage: "chevron.backward")
                        .labelStyle(.iconOnly)
                }
                .disabled(model.isSaving)
                .accessibilityLabel("Close and save")
                .accessibilityHint("Saves this cleaning session before returning")
            }
        }
        .alert("Could Not Save Session", isPresented: saveErrorIsPresented) {
            Button("Retry") { saveAndDismiss() }
            Button("Cancel", role: .cancel) { model.clearSaveError() }
        } message: {
            Text(model.saveErrorMessage ?? "")
        }
        .task { await model.load() }
        .task(id: model.currentAsset?.id) {
            await model.loadVisiblePreviews(pixelWidth: 900, pixelHeight: 900)
        }
        .task {
            for await _ in model.libraryChanges {
                await model.handleLibraryChange()
            }
        }
        .onDisappear {
            // Hiding the back button does not disable the interactive
            // edge-swipe-back gesture, so this is a safety net: whichever
            // way the Cleaner leaves the screen, the session is saved.
            // Idempotent with the explicit Close & Save path above.
            Task { await model.saveForExit() }
        }
    }

    private var saveErrorIsPresented: Binding<Bool> {
        Binding(
            get: { model.saveErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    model.clearSaveError()
                }
            }
        )
    }

    private func saveAndDismiss() {
        Task {
            if await model.saveForExit() {
                dismiss()
            }
        }
    }
}
