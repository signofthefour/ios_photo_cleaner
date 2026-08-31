import SwiftUI

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

    var body: some View {
        let presentation = PrintedPhotoCardPreviewPresentation(
            preview: preview,
            previewStatusText: previewStatusText,
            metadata: metadata,
            isFavorite: isFavorite
        )

        VStack(spacing: PhotoCleanerTheme.photoFrameInset) {
            ZStack(alignment: .bottom) {
                Color.secondary.opacity(0.12)

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

            HStack(alignment: .top, spacing: PhotoCleanerTheme.photoFrameInset) {
                Text(metadata.dateText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(metadata.locationText)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.footnote)
            .foregroundStyle(.black)
            .lineLimit(nil)
            .minimumScaleFactor(0.8)
        }
        .padding(.top, PhotoCleanerTheme.photoFrameInset)
        .padding(.horizontal, PhotoCleanerTheme.photoFrameInset)
        .padding(.bottom, PhotoCleanerTheme.photoFrameBottomInset)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: PhotoCleanerTheme.cardCornerRadius))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Photo for review")
        .accessibilityValue(presentation.accessibilityValue)
        .accessibilityAction(named: "Keep Photo", keepAction)
        .accessibilityAction(named: "Queue for Deletion", queueAction)
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
}
