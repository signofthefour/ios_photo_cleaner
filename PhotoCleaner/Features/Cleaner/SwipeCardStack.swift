import SwiftUI

@MainActor
struct SwipeCardStack: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let cards: [CleanerCardItem]
    let keepAction: () async -> Void
    let queueAction: () async -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var commitGate = SwipeCommitGate()
    @State private var cardOpacity = 1.0
    @State private var forcedStamp: SwipeStamp?
    @State private var hapticTrigger = 0

    var body: some View {
        VStack(spacing: PhotoCleanerTheme.spacing) {
            GeometryReader { geometry in
                ZStack {
                    ForEach(
                        Array(cards.prefix(3).enumerated()).reversed(),
                        id: \.element.id
                    ) { index, card in
                        if index == 0 {
                            topCard(card, cardWidth: geometry.size.width)
                        } else {
                            rearCard(card, depth: index)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .aspectRatio(0.82, contentMode: .fit)
            .frame(maxWidth: 330)

            HStack(spacing: PhotoCleanerTheme.spacing) {
                Button("Queue for Deletion", systemImage: "trash") {
                    beginCommit(.delete, cardWidth: 330)
                }
                .accessibilityHint(
                    "Adds this photo to the pending deletion queue without deleting it"
                )

                Spacer(minLength: 0)

                Button("Keep", systemImage: "checkmark") {
                    beginCommit(.keep, cardWidth: 330)
                }
                .accessibilityHint("Keeps this photo and advances to the next")
            }
            .disabled(commitGate.isCommitting || cards.isEmpty)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: hapticTrigger)
    }

    private func topCard(_ card: CleanerCardItem, cardWidth: CGFloat) -> some View {
        PrintedPhotoCard(
            preview: card.preview,
            metadata: PhotoCardMetadata(asset: card.asset),
            previewStatusText: card.previewStatusText,
            isFavorite: card.asset.isFavorite,
            keepAction: { beginCommit(.keep, cardWidth: cardWidth) },
            queueAction: { beginCommit(.delete, cardWidth: cardWidth) },
            stamp: forcedStamp ?? SwipeCardInteraction.stamp(
                translation: dragOffset.width,
                cardWidth: cardWidth
            )
        )
        .offset(x: dragOffset.width, y: dragOffset.height * 0.15)
        .rotationEffect(
            .degrees(
                SwipeCardInteraction.rotationDegrees(
                    translation: dragOffset.width,
                    cardWidth: cardWidth
                )
            )
        )
        .opacity(cardOpacity)
        .gesture(dragGesture(cardWidth: cardWidth))
        .zIndex(3)
    }

    private func rearCard(_ card: CleanerCardItem, depth: Int) -> some View {
        PrintedPhotoCard(
            preview: card.preview,
            metadata: PhotoCardMetadata(asset: card.asset),
            previewStatusText: card.previewStatusText,
            isFavorite: card.asset.isFavorite,
            keepAction: {},
            queueAction: {},
            stamp: nil,
            isInteractive: false
        )
        .scaleEffect(
            1 - (CGFloat(depth) * (1 - PhotoCleanerTheme.rearCardScale))
        )
        .offset(y: CGFloat(depth) * PhotoCleanerTheme.rearCardVerticalOffset)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .zIndex(Double(3 - depth))
    }

    private func dragGesture(cardWidth: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard !commitGate.isCommitting else { return }
                forcedStamp = nil
                dragOffset = value.translation
            }
            .onEnded { value in
                guard !commitGate.isCommitting else { return }
                dragOffset = value.translation
                if let direction = SwipeCardInteraction.commitDirection(
                    translation: value.translation.width,
                    cardWidth: cardWidth
                ) {
                    beginCommit(direction, cardWidth: cardWidth)
                } else {
                    resetRejectedDrag()
                }
            }
    }

    private func beginCommit(_ direction: SwipeCommitDirection, cardWidth: CGFloat) {
        guard commitGate.begin() else { return }

        forcedStamp = SwipeStamp(direction: direction, opacity: 1)
        hapticTrigger += 1

        Task { @MainActor in
            if reduceMotion {
                withAnimation(.linear(duration: PhotoCleanerTheme.reducedMotionDuration)) {
                    cardOpacity = 0
                }
                await waitForAnimation(PhotoCleanerTheme.reducedMotionDuration)
            } else {
                withAnimation(.easeIn(duration: PhotoCleanerTheme.normalCommitDuration)) {
                    dragOffset.width = direction.sign * cardWidth * 1.4
                }
                await waitForAnimation(PhotoCleanerTheme.normalCommitDuration)
            }

            switch direction {
            case .keep:
                await keepAction()
            case .delete:
                await queueAction()
            }

            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                dragOffset = .zero
                cardOpacity = 1
                forcedStamp = nil
                commitGate.reset()
            }
        }
    }

    private func resetRejectedDrag() {
        if !reduceMotion {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
                dragOffset = .zero
            }
            return
        }

        guard commitGate.begin() else { return }
        Task { @MainActor in
            withAnimation(.linear(duration: PhotoCleanerTheme.reducedMotionDuration)) {
                cardOpacity = 0
            }
            await waitForAnimation(PhotoCleanerTheme.reducedMotionDuration)

            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                dragOffset = .zero
                forcedStamp = nil
            }

            withAnimation(.linear(duration: PhotoCleanerTheme.reducedMotionDuration)) {
                cardOpacity = 1
            }
            await waitForAnimation(PhotoCleanerTheme.reducedMotionDuration)
            commitGate.reset()
        }
    }

    private func waitForAnimation(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }
}
