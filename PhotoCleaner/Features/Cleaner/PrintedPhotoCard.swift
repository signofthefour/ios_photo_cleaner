import SwiftUI

struct PrintedPhotoCard: View {
    let preview: LocalPhotoPreview?
    let metadata: PhotoCardMetadata
    let previewStatusText: String?
    let isFavorite: Bool
    let keepAction: () -> Void
    let queueAction: () -> Void

    var body: some View {
        VStack(spacing: PhotoCleanerTheme.photoFrameInset) {
            ZStack(alignment: .bottom) {
                Color.secondary.opacity(0.12)

                previewImage
                    .padding(PhotoCleanerTheme.photoFrameInset)

                if let previewStatusText {
                    Text(previewStatusText)
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
    private var previewImage: some View {
        switch preview?.content {
        case let .systemSymbol(name):
            Image(systemName: name)
                .resizable()
                .scaledToFit()
        case let .encodedImageData(data):
            if let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                placeholderImage
            }
        case nil:
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
