import SwiftUI

struct PrintedPhotoCardPreviewPresentation {
    enum Content {
        case systemSymbol(String)
        case image(UIImage)
        case placeholder
    }

    let content: Content
    let statusText: String?

    init(preview: LocalPhotoPreview?, previewStatusText: String?) {
        switch preview?.content {
        case let .systemSymbol(name):
            content = .systemSymbol(name)
            statusText = previewStatusText
        case let .encodedImageData(data):
            if let image = UIImage(data: data) {
                content = .image(image)
                statusText = previewStatusText
            } else {
                content = .placeholder
                statusText = previewStatusText ?? "Local preview unavailable"
            }
        case nil:
            content = .placeholder
            statusText = previewStatusText
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
            previewStatusText: previewStatusText
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
        .accessibilityValue("\(metadata.accessibilityValue) \(isFavorite ? "Favorite." : "Not favorite.")")
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
