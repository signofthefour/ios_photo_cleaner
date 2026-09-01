import SwiftUI

struct PrintedPhotoCardStampPresentation: Equatable, Sendable {
    let text: String
    let direction: SwipeCommitDirection
    let opacity: Double

    init?(stamp: SwipeStamp?) {
        guard let stamp else { return nil }
        text = stamp.direction == .keep ? "KEEP" : "DELETE"
        direction = stamp.direction
        opacity = stamp.opacity
    }
}

struct PrintedPhotoCardPreviewPresentation {
    enum Content {
        case systemSymbol(String)
        case image(UIImage)
        case placeholder
    }

    let content: Content
    let statusText: String?
    let accessibilityValue: String

    init(
        preview: LocalPhotoPreview?,
        previewStatusText: String?,
        metadata: PhotoCardMetadata,
        isFavorite: Bool
    ) {
        let resolvedContent: Content
        let resolvedStatusText: String?

        switch preview?.content {
        case let .systemSymbol(name):
            resolvedContent = .systemSymbol(name)
            resolvedStatusText = previewStatusText
        case let .encodedImageData(data):
            if let image = UIImage(data: data) {
                resolvedContent = .image(image)
                resolvedStatusText = previewStatusText
            } else {
                resolvedContent = .placeholder
                resolvedStatusText = previewStatusText ?? "Local preview unavailable"
            }
        case nil:
            resolvedContent = .placeholder
            resolvedStatusText = previewStatusText
        }

        content = resolvedContent
        statusText = resolvedStatusText

        let favoriteSentence = isFavorite ? "Favorite." : "Not favorite."
        if let resolvedStatusText {
            accessibilityValue = "\(metadata.accessibilityValue) \(favoriteSentence) \(resolvedStatusText)."
        } else {
            accessibilityValue = "\(metadata.accessibilityValue) \(favoriteSentence)"
        }
    }
}

struct PrintedPhotoCard: View {
    let preview: LocalPhotoPreview?
    let metadata: PhotoCardMetadata
    let previewStatusText: String?
    let isFavorite: Bool
    let keepAction: () -> Void
    let queueAction: () -> Void
    var stamp: SwipeStamp?
    var isInteractive = true

    var body: some View {
        let presentation = PrintedPhotoCardPreviewPresentation(
            preview: preview,
            previewStatusText: previewStatusText,
            metadata: metadata,
            isFavorite: isFavorite
        )

        VStack(spacing: PhotoCleanerTheme.photoFrameInset) {
            ZStack(alignment: .bottom) {
                PhotoCleanerTheme.Palette.background

                previewImage(for: presentation.content)
                    .padding(PhotoCleanerTheme.photoFrameInset)

                if let statusText = presentation.statusText {
                    Text(statusText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(PhotoCleanerTheme.photoFrameInset)
                        .frame(maxWidth: .infinity)
                        .background(.ultraThinMaterial)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: PhotoCleanerTheme.cardCornerRadius - PhotoCleanerTheme.photoFrameInset))

            HStack(alignment: .top, spacing: PhotoCleanerTheme.photoFrameInset) {
                Text(metadata.dateText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(metadata.locationText)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.system(.footnote, design: .serif).italic())
            .foregroundStyle(PhotoCleanerTheme.Palette.ink)
            .lineLimit(nil)
            .minimumScaleFactor(0.8)
        }
        .padding(.top, PhotoCleanerTheme.photoFrameInset)
        .padding(.horizontal, PhotoCleanerTheme.photoFrameInset)
        .padding(.bottom, PhotoCleanerTheme.photoFrameBottomInset)
        .background(PhotoCleanerTheme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: PhotoCleanerTheme.cardCornerRadius))
        .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 10)
        .overlay {
            stampOverlay
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Photo for review")
        .accessibilityValue(presentation.accessibilityValue)
        .accessibilityAction(named: "Keep Photo", keepAction)
        .accessibilityAction(named: "Queue for Deletion", queueAction)
        .accessibilityHidden(!isInteractive)
    }

    @ViewBuilder
    private func previewImage(for content: PrintedPhotoCardPreviewPresentation.Content) -> some View {
        switch content {
        case let .systemSymbol(name):
            Image(systemName: name)
                .resizable()
                .scaledToFit()
        case let .image(image):
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        case .placeholder:
            placeholderImage
        }
    }

    private var placeholderImage: some View {
        Image(systemName: "photo")
            .resizable()
            .scaledToFit()
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var stampOverlay: some View {
        if let presentation = PrintedPhotoCardStampPresentation(stamp: stamp) {
            HStack {
                if presentation.direction == .delete {
                    Spacer(minLength: 0)
                }

                Text(presentation.text)
                    .font(.title2.bold())
                    .foregroundStyle(stampColor(for: presentation.direction))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                stampColor(for: presentation.direction),
                                lineWidth: PhotoCleanerTheme.stampLineWidth
                            )
                    }
                    .rotationEffect(.degrees(presentation.direction == .keep ? -8 : 8))

                if presentation.direction == .keep {
                    Spacer(minLength: 0)
                }
            }
            .padding(PhotoCleanerTheme.spacing)
            .frame(maxHeight: .infinity, alignment: .top)
            .opacity(presentation.opacity)
            .accessibilityHidden(true)
        }
    }

    private func stampColor(for direction: SwipeCommitDirection) -> Color {
        direction == .keep ? PhotoCleanerTheme.Palette.keep : PhotoCleanerTheme.Palette.delete
    }
}
