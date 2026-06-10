import SwiftUI

struct LoginView: View {
    @Environment(AppModel.self) private var app

    @State private var email = ""
    @State private var password = ""
    @FocusState private var focusedField: Field?

    private enum Field { case email, password }

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

            VStack(spacing: 10) {
                TextField("Email", text: $email)
                    .textContentType(.username)
                    .focused($focusedField, equals: .email)
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .focused($focusedField, equals: .password)
                    .onSubmit { submit() }
            }
            .textFieldStyle(.roundedBorder)
            .frame(width: 300)

            if let error = app.loginError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .frame(maxWidth: 360)
                    .multilineTextAlignment(.center)
            }

            Button {
                submit()
            } label: {
                if app.isLoggingIn {
                    ProgressView().controlSize(.small).frame(width: 60)
                } else {
                    Text("Sign In").frame(width: 60)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(app.isLoggingIn || email.isEmpty || password.isEmpty)

            Text("""
                Sign in with your nugs.net email and password. \
                Apple/Google SSO accounts aren't supported by the password grant. \
                Personal use against your own subscription only.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { focusedField = .email }
    }

    private func submit() {
        guard !email.isEmpty, !password.isEmpty, !app.isLoggingIn else { return }
        Task { await app.login(email: email, password: password) }
    }
}
