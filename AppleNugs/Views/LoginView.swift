import SwiftUI

/// Sign-in is nugs.net's own page in a system browser sheet (authorization
/// code + PKCE); the app never asks for, sees or stores a password.
struct LoginView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        LoginContent(isLoggingIn: app.isLoggingIn, error: app.loginError) {
            Task { await app.loginWithBrowser() }
        }
    }
}

/// The sign-in screen itself, from plain values (no `AppModel`), so the
/// offscreen harness can render it.
///
/// Note it shows BEFORE login, under whatever theme was persisted last.
struct LoginContent: View {
    @Environment(\.theme) private var theme

    let isLoggingIn: Bool
    let error: String?
    let onSignIn: () -> Void

    var body: some View {
        if theme.caps.contains(.blisterPack) {
            packBody
        } else {
            standardBody
        }
    }

    // MARK: Yeti

    /// The surfaces sheet's sign-in figure: the EMPTY pack with the "Yeti"
    /// nameplate printed on its card (the app before the show arrives), one
    /// snow primary, a failure said in snow — never red. The Mac centers the
    /// same column in the window.
    private var packBody: some View {
        VStack(spacing: 0) {
            // `.card.pack { width: 210px }`, `.plate-sm { font-weight: 900;
            // font-size: 30px; letter-spacing: -.02em }`
            BlisterPack(emptyStyle: .regular) {
                Text("Yeti")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .tracking(-0.6)
                    .foregroundStyle(theme.palette.textPrimary)
                    .lineLimit(1)
            }
            .frame(width: 210)
            .accessibilityElement(children: .combine)

            Text("An unofficial player for nugs.net")
                .font(theme.type.body(15))
                .foregroundStyle(theme.palette.textSecondary)
                .padding(.top, 22)

            if let error {
                Text(error)
                    .font(theme.type.body(15).weight(.semibold))
                    .foregroundStyle(theme.palette.textPrimary)
                    .frame(maxWidth: 300)
                    .padding(.top, 10)
            }

            Button {
                // The button stays at full strength while the browser sheet is
                // up (it reads "Opening nugs.net…"), so it can't be `.disabled`
                // — that would dim it to half. Guard the second tap instead.
                guard !isLoggingIn else { return }
                onSignIn()
            } label: {
                Group {
                    if isLoggingIn {
                        HStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.small)
                                .tint(theme.palette.base)
                                // macOS draws its spinner by appearance, not
                                // tint: a light appearance gives night ink.
                                .environment(\.colorScheme, .light)
                            Text("Opening nugs.net…")
                        }
                    } else {
                        Label("Sign in with nugs.net", systemImage: "globe")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.yetiPrimary)
            .controlSize(.large)
            .frame(maxWidth: 300)
            .padding(.top, 24)
            // Not `.disabled` (see the guard above), so say the state instead.
            .accessibilityValue(isLoggingIn ? "Opening nugs.net" : "")
            .accessibilityIdentifier("login.signIn")

            VStack(spacing: 6) {
                Text("You sign in on nugs.net’s own page; this app never sees your password.")
                Text("Unofficial. Not affiliated with nugs.net or Apple.")
            }
            .font(theme.type.body(12.5))
            .foregroundStyle(theme.palette.textIdle)
            .frame(maxWidth: 300)
            .padding(.top, 14)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Other themes (unchanged)

    private var standardBody: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
                Text("Yeti")
                    .font(.largeTitle.weight(.semibold))
                Text("An unofficial player for nugs.net")
                    .foregroundStyle(.secondary)
            }

            if let error {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .frame(maxWidth: 360)
                    .multilineTextAlignment(.center)
            }

            Button {
                onSignIn()
            } label: {
                if isLoggingIn {
                    ProgressView().controlSize(.small).frame(minWidth: 160)
                } else {
                    Label("Sign in with nugs.net", systemImage: "globe")
                        .frame(minWidth: 160)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoggingIn)
            .accessibilityIdentifier("login.signIn")

            VStack(spacing: 4) {
                Text("You sign in on nugs.net’s own page; this app never sees your password.")
                Text("Unofficial. Not affiliated with nugs.net or Apple.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: 380)
            .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
