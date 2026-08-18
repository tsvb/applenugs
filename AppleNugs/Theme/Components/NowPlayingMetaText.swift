import SwiftUI

/// The now-playing "artist · show" line, with the artist and the show
/// individually clickable.
///
/// Renders **exactly one** `Text(AttributedString)` — no wrapper stack, no
/// `contentShape`, no frame of its own — so it is a drop-in for the plain
/// `Text` it replaces at all sixteen render sites. Callers keep their entire
/// modifier chain (`.font`, `.tracking`, `.lineLimit`, `.truncationMode`,
/// `.multilineTextAlignment`); those are View modifiers and propagate to the
/// descendant Text, so metrics and truncation are unchanged. That matters:
/// several of these surfaces have no slack at all (the cassette's 25:16 ratio,
/// the pill's text budget, the faceplate's fixed-width ticker).
///
/// **Invisible at rest.** Each link run is given the surrounding foreground
/// color explicitly, which SwiftUI honors over its own link tint — verified by
/// rendering plain and linked lines offscreen and comparing pixels, they are
/// identical. On hover (macOS only; there is no hover on iOS) the linkable runs
/// pick up a dotted underline, leaving the " · " separator bare, so the reveal
/// says which parts are actionable.
///
/// Taps arrive as URLs and are intercepted by `nowPlayingMetaLinks(...)`, which
/// is installed once per scene root — see `NowPlayingMetaRouter`.
struct NowPlayingMetaText: View {
    @Environment(\.theme) private var theme

    let track: QueueTrack?
    var fields: [NowPlayingMetaLine.Field] = [.artist, .show]
    var mode: NowPlayingMetaLine.Mode = .joined
    var casing: NowPlayingMetaLine.Casing = .asIs
    /// The glyph color. Callers that paint from a theme token can leave this
    /// nil and set `.foregroundStyle` as they always have; the cassette passes
    /// its local paper `ink` here because the run color has to be set on the
    /// attributed string, not inherited, for the link runs to match.
    var tint: Color?
    /// Rendered when there is no track. Absorbs the ticker surfaces' idle copy.
    var idle: String?
    /// False renders inert text with no destinations at all — the offline
    /// Downloads sheet, where there is no navigation stack behind to push onto.
    var showsLinks: Bool = true
    /// False keeps the destinations reachable (context menu, VoiceOver actions)
    /// but does NOT make the glyphs a tap target.
    ///
    /// For surfaces whose whole body is already one tap target: the iOS pill
    /// (48pt capsule, body tap opens the full-screen player) and the Home
    /// "Continue listening" hero (body tap toggles playback). A 10pt rival hit
    /// area inside those means a mis-tap sends you somewhere else entirely, and
    /// in both cases the primary tap leads straight to a surface where the same
    /// links ARE tappable.
    var tappableText: Bool = true

    @State private var hovering = false

    private var segments: [NowPlayingMetaLine.Segment] {
        NowPlayingMeta.segments(track, fields: fields, mode: mode, casing: casing)
    }

    @ViewBuilder
    var body: some View {
        if segments.isEmpty, (idle ?? "").isEmpty {
            // Nothing to say — render NOTHING, not an empty Text, which would
            // still claim a line's height. Most of the sites this replaces were
            // `if let` and depended on that: the cassette's 25:16 ratio budget
            // has ~19pt of slack and has already been yielded twice by a label
            // growing a line.
            EmptyView()
        } else {
            Text(attributed)
                .modifier(MetaHover(hovering: $hovering,
                                    enabled: showsLinks && tappableText && hasLinks))
                .accessibilityElement()
                .accessibilityLabel(segments.map(\.text).joined())
                .modifier(MetaActions(targets: showsLinks ? linkTargets : []))
        }
    }

    private var hasLinks: Bool { !linkTargets.isEmpty }

    private var linkTargets: [NowPlayingMetaLine.Target] {
        segments.compactMap(\.target)
    }

    private var attributed: AttributedString {
        let runs = segments
        guard !runs.isEmpty else {
            return AttributedString(idle ?? "", attributes: container(color: tint))
        }
        var out = AttributedString()
        for segment in runs {
            let target = (showsLinks && tappableText) ? segment.target : nil
            // The color is set explicitly on EVERY run, linked or not. Without
            // it SwiftUI paints link runs in its own tint and the line stops
            // matching the rest of the surface — that explicit color is what
            // makes the link invisible at rest.
            let color = tint ?? (target != nil ? theme.palette.textSecondary : nil)
            out.append(AttributedString(
                segment.text,
                attributes: container(color: color,
                                      link: target?.url,
                                      underlined: target != nil && hovering)))
        }
        return out
    }

    /// Built with the `AttributedStringKey`-type subscript rather than the
    /// dynamic-member form (`run.foregroundColor = …`): the latter forms a key
    /// path over a non-Sendable attribute type, which warns under
    /// `SWIFT_STRICT_CONCURRENCY=complete` and is an error in Swift 6.
    private func container(color: Color?,
                           link: URL? = nil,
                           underlined: Bool = false) -> AttributeContainer {
        var c = AttributeContainer()
        if let color {
            c[AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] = color
        }
        if let link {
            c[AttributeScopes.FoundationAttributes.LinkAttribute.self] = link
        }
        if underlined {
            c[AttributeScopes.SwiftUIAttributes.UnderlineStyleAttribute.self] =
                Text.LineStyle(pattern: .dot,
                               color: (color ?? theme.palette.textSecondary).opacity(0.5))
        }
        return c
    }
}

/// Hover is macOS-only, and pointless when nothing on the line is linkable.
private struct MetaHover: ViewModifier {
    @Binding var hovering: Bool
    let enabled: Bool

    func body(content: Content) -> some View {
        #if os(macOS)
        if enabled {
            content.onHover { hovering = $0 }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

/// Named actions for every linkable run, plus the matching context menu.
///
/// These are not a nicety on top of the link runs — they are the only way the
/// artist and show are reachable under VoiceOver, and on iOS the only
/// discoverable affordance at all (no hover). They attach to the container, so
/// they survive the show run being truncated away entirely, which happens
/// routinely on the narrow surfaces.
private struct MetaActions: ViewModifier {
    @Environment(AppModel.self) private var app
    @Environment(UIState.self) private var ui

    let targets: [NowPlayingMetaLine.Target]

    func body(content: Content) -> some View {
        guard !targets.isEmpty else { return AnyView(content) }
        return AnyView(
            targets.reduce(AnyView(content)) { view, target in
                AnyView(view.accessibilityAction(named: Text(target.actionName)) {
                    NowPlayingMetaRouter.open(target, app: app, ui: ui)
                })
            }
            .contextMenu {
                ForEach(targets, id: \.self) { target in
                    Button(target.actionName) {
                        NowPlayingMetaRouter.open(target, app: app, ui: ui)
                    }
                }
            }
        )
    }
}

extension NowPlayingMetaLine.Target {
    var actionName: String {
        switch self {
        case .artist(let name): return "Go to \(name)"
        case .show: return "Go to this show"
        }
    }
}
