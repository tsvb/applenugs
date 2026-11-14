import SwiftUI

/// The toast's capsule, shared by both scene roots (`RootView`, `IOSRootView`);
/// each root keeps its own placement, transition and hit testing.
///
/// The surfaces sheet's `.toast`: glass with a frost hairline, heavy rounded
/// type, and a mark that says how it went — a snow check, or a slush warning
/// mark for a failure.
///
/// Plain values and `\.theme` only, so the offscreen harness can render it.
struct ToastCapsule: View {
    @Environment(\.theme) private var theme

    let text: String
    let kind: UIState.Toast.Kind

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: kind == .failure ? "exclamationmark.circle" : "checkmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(kind == .failure
                                 ? theme.palette.textSecondary : theme.palette.textPrimary)
                .accessibilityHidden(true)
            Text(text)
                .font(theme.type.title(14))
                .foregroundStyle(theme.palette.textPrimary)
                .lineLimit(1)
        }
        // `.toast { height: 38px; padding: 0 16px 0 12px }`
        .padding(.leading, 12)
        .padding(.trailing, 16)
        .frame(height: 38)
        .background(.regularMaterial, in: Capsule())
        .overlay { Capsule().strokeBorder(theme.palette.hairline, lineWidth: 1) }
        // `0 12px 22px -10px rgba(0,0,0,.75)`
        .shadow(color: .black.opacity(0.55), radius: 11, y: 8)
    }
}
