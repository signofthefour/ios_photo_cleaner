import CoreGraphics

enum SwipeCommitDirection: Equatable, Sendable {
    case keep
    case delete

    var sign: CGFloat {
        self == .keep ? 1 : -1
    }
}

struct SwipeStamp: Equatable, Sendable {
    let direction: SwipeCommitDirection
    let opacity: Double
}

enum SwipeCardInteraction {
    static let commitFraction: CGFloat = 0.25
    static let maximumRotationDegrees: Double = 8

    static func commitDirection(
        translation: CGFloat,
        cardWidth: CGFloat
    ) -> SwipeCommitDirection? {
        guard cardWidth > 0 else { return nil }

        let threshold = cardWidth * commitFraction
        if translation >= threshold { return .keep }
        if translation <= -threshold { return .delete }
        return nil
    }

    static func rotationDegrees(translation: CGFloat, cardWidth: CGFloat) -> Double {
        guard cardWidth > 0 else { return 0 }

        let proportional = Double(translation / cardWidth) * maximumRotationDegrees
        return min(max(proportional, -maximumRotationDegrees), maximumRotationDegrees)
    }

    static func stamp(translation: CGFloat, cardWidth: CGFloat) -> SwipeStamp? {
        guard cardWidth > 0, translation != 0 else { return nil }

        let opacity = min(abs(translation) / (cardWidth * commitFraction), 1)
        return SwipeStamp(
            direction: translation > 0 ? .keep : .delete,
            opacity: Double(opacity)
        )
    }
}

struct SwipeCommitGate: Equatable, Sendable {
    private(set) var isCommitting = false

    mutating func begin() -> Bool {
        guard !isCommitting else { return false }
        isCommitting = true
        return true
    }

    mutating func reset() {
        isCommitting = false
    }
}
