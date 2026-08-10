#if os(macOS)
import AppKit
#else
import UIKit
#endif
import AuthenticationServices
import CryptoKit
import Foundation

/// Hosts the browser-based OAuth2 Authorization Code + PKCE login in a
/// system-managed Safari session via `ASWebAuthenticationSession`. Unlike the
/// password grant, this hands authentication off to the real id.nugs.net login
/// page, so Apple/Google/Facebook/SiriusXM SSO and MFA accounts work — those
/// never have a password to POST and so are unreachable by the ROPC flow.
///
/// The whole AuthenticationServices/AppKit surface lives here; callers get back
/// only an authorization code plus the PKCE verifier to exchange for tokens.
@MainActor
final class BrowserAuthService: NSObject, ASWebAuthenticationPresentationContextProviding {
    /// The session must outlive `start()` — if it deallocates, the system
    /// silently tears down the UI and the completion handler never fires.
    private var session: ASWebAuthenticationSession?

    /// Drives one interactive login. Returns the authorization code and the
    /// PKCE `code_verifier` that produced its challenge; the caller exchanges
    /// the code at the token endpoint with that verifier and no client secret.
    static func authorize() async throws -> (code: String, verifier: String) {
        try await BrowserAuthService().run()
    }

    private func run() async throws -> (code: String, verifier: String) {
        let verifier = Self.randomURLSafe(byteCount: 32)
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = Self.randomURLSafe(byteCount: 16)
        let nonce = Self.randomURLSafe(byteCount: 16)

        var comps = URLComponents(url: NugsConstants.authorizeURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "response_mode", value: "query"),
            URLQueryItem(name: "client_id", value: NugsConstants.clientId),
            URLQueryItem(name: "redirect_uri", value: NugsConstants.oauthRedirectURI),
            URLQueryItem(name: "scope", value: NugsConstants.oauthScope),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
        ]

        let callbackURL: URL = try await withCheckedThrowingContinuation { cont in
            let s = ASWebAuthenticationSession(
                url: comps.url!,
                callbackURLScheme: NugsConstants.oauthCallbackScheme
            ) { url, error in
                if let url {
                    cont.resume(returning: url)
                } else if let error {
                    // A user dismissing the sheet is not a failure to surface.
                    if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                        cont.resume(throwing: NugsError.loginCancelled)
                    } else {
                        cont.resume(throwing: error)
                    }
                } else {
                    cont.resume(throwing: NugsError.badResponse("auth session returned no callback URL"))
                }
            }
            s.presentationContextProvider = self          // must be set before start()
            s.prefersEphemeralWebBrowserSession = false   // share Safari cookies so SSO is seamless
            self.session = s                              // retain before start()
            #if os(macOS)
            NSApp.activate(ignoringOtherApps: true)       // foreground, or the sheet never appears
            #endif
            if !s.start() {
                cont.resume(throwing: NugsError.badResponse("could not start the login session"))
            }
        }

        let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state else {
            throw NugsError.badResponse("OAuth state mismatch")
        }
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            let err = items.first(where: { $0.name == "error" })?.value ?? "no authorization code returned"
            throw NugsError.badResponse("OAuth: \(err)")
        }
        return (code, verifier)
    }

    // iOS 26 deprecated every scene-less UIWindow initializer (`init()` and
    // `init(frame:)` both; `init(windowScene:)` is the only survivor), but the
    // last-resort branch still needs one — the alternative is a force-unwrap
    // that would crash the login flow instead of degrading. A deprecated
    // declaration may use same-version deprecated API without warning, and
    // nothing in this project calls this method (the system invokes it as an
    // ASWebAuthenticationSession protocol witness), so the annotation keeps the
    // build clean at no call-site cost.
    //
    // The real lookup lives in `sceneAnchor()`, which is NOT deprecated: this
    // body is kept to a single expression so the annotation can only ever
    // suppress the one `UIWindow()` below, never a future deprecated call added
    // here by mistake.
    @available(iOS, deprecated: 26.0, message: "Retains a scene-less UIWindow fallback by design.")
    func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(macOS)
        return NSApp.windows.first(where: { $0.isKeyWindow }) ?? NSApp.windows.first ?? NSWindow()
        #else
        return Self.sceneAnchor() ?? UIWindow()
        #endif
    }

    #if os(iOS)
    /// The presentation anchor when a window scene exists: the key window, else
    /// any window, else a fresh window on the first connected scene. Returns nil
    /// only when there is no connected window scene at all — a state in which
    /// ASWebAuthenticationSession could not be presenting in the first place.
    private static func sceneAnchor() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: \.isKeyWindow)
            ?? scenes.first?.windows.first
            ?? scenes.first.map { UIWindow(windowScene: $0) }
    }
    #endif

    // --- PKCE helpers -------------------------------------------------------

    private static func randomURLSafe(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
