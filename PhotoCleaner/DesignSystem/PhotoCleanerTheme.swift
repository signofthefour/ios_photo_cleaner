import SwiftUI

enum PhotoCleanerTheme {
    static let cardCornerRadius: CGFloat = 20
    static let spacing: CGFloat = 16
    static let photoFrameInset: CGFloat = 12
    static let photoFrameBottomInset: CGFloat = 24
    static let rearCardScale: CGFloat = 0.96
    static let rearCardVerticalOffset: CGFloat = 8
    static let stampLineWidth: CGFloat = 3
    static let normalCommitDuration = 0.18
    static let reducedMotionDuration = 0.12

    static let rowCornerRadius: CGFloat = 16
    static let actionButtonDiameter: CGFloat = 44
    static let primaryActionButtonDiameter: CGFloat = 62

    /// Warm, printed-photo palette shared across screens. Named `Palette`
    /// rather than `Color` to avoid shadowing `SwiftUI.Color`.
    enum Palette {
        static let background = Color(red: 0.969, green: 0.957, blue: 0.937)
        static let surface = Color(red: 0.996, green: 0.992, blue: 0.984)
        static let ink = Color(red: 0.141, green: 0.122, blue: 0.110)
        static let inkSoft = Color(red: 0.420, green: 0.384, blue: 0.349)
        static let line = Color(red: 0.894, green: 0.875, blue: 0.839)
        static let keep = Color(red: 0.235, green: 0.561, blue: 0.365)
        static let keepSoft = Color(red: 0.894, green: 0.953, blue: 0.918)
        static let delete = Color(red: 0.851, green: 0.322, blue: 0.290)
        static let deleteSoft = Color(red: 0.984, green: 0.894, blue: 0.886)
    }
}

/// A circular icon button used for the Cleaner's Undo/Delete/Keep/Album
/// controls. Visual only: the label's title remains the accessibility name
/// and any existing `.accessibilityHint`/`.disabled` continues to apply.
struct CleanerCircularButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    var tint: Color
    var diameter: CGFloat = PhotoCleanerTheme.actionButtonDiameter
    var isBordered = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(.system(size: diameter * 0.36, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: diameter, height: diameter)
            .background(
                Circle()
                    .fill(PhotoCleanerTheme.Palette.surface)
                    .overlay(
                        Circle().stroke(
                            isBordered ? tint : PhotoCleanerTheme.Palette.line,
                            lineWidth: isBordered ? 2 : 1
                        )
                    )
            )
            .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
            .opacity(isEnabled ? 1 : 0.35)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
    }
}
