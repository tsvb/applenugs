import SwiftUI

/// Sign-in is nugs.net's own page in a system browser sheet (authorization
/// code + PKCE); the app never asks for, sees or stores a password.
struct LoginView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
                Text("AppleNugs")
                    .font(.largeTitle.weight(.semibold))
                Text("A personal native client for nugs.net")
                    .foregroundStyle(.secondary)
            }

            if let error = app.loginError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .frame(maxWidth: 360)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await app.loginWithBrowser() }
            } label: {
                if app.isLoggingIn {
                    ProgressView().controlSize(.small).frame(minWidth: 160)
                } else {
                    Label("Sign in with nugs.net", systemImage: "globe")
                        .frame(minWidth: 160)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(app.isLoggingIn)
            .accessibilityIdentifier("login.signIn")

            Text("You sign in on nugs.net’s own page; this app never sees your password.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
