import SwiftUI

/// The "Couldn't reach nugs.net" screen, shared by both scene roots. The roots
/// keep the offline Downloads sheet; this view only raises it.
///
/// Plain values in, closures out (no `AppModel`), so the offscreen harness can
/// render it.
///
/// Two gates, deliberately different:
/// - `hasDownloads` shows "Listen offline" — today's gate, unchanged. Tightening
///   it to the 30-day window would hide the user's downloads entirely once
///   verification lapses; the expired case is already explained in the sheet.
/// - `canPlayOffline` (downloads exist AND `OfflineAccessPolicy.allowsOfflinePlay`)
///   shows Yeti's reassurance line, so it never promises what won't happen.
struct ConnectionFailedView: View {
    @Environment(\.theme) private var theme

    let message: String
    let hasDownloads: Bool
    let canPlayOffline: Bool
    let onRetry: () -> Void
    let onListenOffline: () -> Void
    let onSignOut: () -> Void

    var body: some View {
        if theme.caps.contains(.blisterPack) {
            packBody
        } else {
            ContentUnavailableView {
                Label("Couldn't reach nugs.net", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try again", action: onRetry)
                    .buttonStyle(.borderedProminent)
                // The whole point of downloads is being reachable right here.
                if hasDownloads {
                    Button("Listen offline", action: onListenOffline)
                }
                Button("Sign out", action: onSignOut)
            }
        }
    }

    /// The surfaces sheet's connection figure: the small empty pack, a
    /// sentence a person can act on, the raw error last in quiet monospace,
    /// one snow primary. The Mac centers the same column in the window.
    private var packBody: some View {
        VStack(spacing: 0) {
            // `.card.pack.sm { width: 156px }`
            BlisterPack(emptyStyle: .small)
                .frame(width: 156)
                .accessibilityHidden(true)
            Text("Couldn't reach nugs.net")
                .font(theme.type.title(24))
                .foregroundStyle(theme.palette.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.top, 22)
            if canPlayOffline {
                Text("Your downloads still play while you're offline.")
                    .font(theme.type.body(15))
                    .foregroundStyle(theme.palette.textSecondary)
                    .frame(maxWidth: 290)
                    .padding(.top, 6)
            }
            Text(message)
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(theme.palette.textIdle)
                .frame(maxWidth: 290)
                .padding(.top, 10)
            VStack(spacing: 10) {
                Button(action: onRetry) {
                    Text("Try again").frame(maxWidth: .infinity)
                }
                .buttonStyle(.yetiPrimary)
                if hasDownloads {
                    Button(action: onListenOffline) {
                        Text("Listen offline").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.yetiSecondary)
                }
                Button(action: onSignOut) {
                    Text("Sign out")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(theme.palette.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .controlSize(.large)
            .frame(maxWidth: 300)
            .padding(.top, 24)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
