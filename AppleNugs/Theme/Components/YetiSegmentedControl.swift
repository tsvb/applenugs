import SwiftUI

/// Yeti's segmented control (`.seg` in the surfaces sheet): a 34pt shelf
/// track, radius 10, 3pt inset, and one lighter thumb under the selected
/// segment that slides between them. Labels are heavy rounded 13.5 — snow on
/// the thumb, slush off it. Hosts use it in place of a system
/// `Picker(.segmented)`.
///
/// The font is the same selected or not (only the color changes), so a
/// segment's label never changes width as the thumb moves. The thumb's
/// animation is scoped to the thumb itself: whatever the host swaps in below
/// on a selection change is not animated by this control.
///
/// Accessibility: the group carries `label` (the label the system picker had)
/// and each segment is a button with `.isSelected` on the chosen one, the
/// shape VoiceOver reads for a system segmented control.
struct YetiSegmentedControl<Value: Hashable>: View {
    struct Option {
        let value: Value
        let title: String
    }

    let label: String
    @Binding var selection: Value
    let options: [Option]

    init(_ label: String, selection: Binding<Value>, options: [Option]) {
        self.label = label
        self._selection = selection
        self.options = options
    }

    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The selected segment: a lighter shelf than `palette.raised` (#18203A),
    /// as the sheet draws it. A constant here rather than a Palette field —
    /// nothing else in the design uses it.
    static var thumbFill: Color { Color(hex: 0x2A355A) }

    private static var height: CGFloat { 34 }
    private static var inset: CGFloat { 3 }

    private var selectedIndex: Int {
        options.firstIndex { $0.value == selection } ?? 0
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                segment(option)
            }
        }
        .background(alignment: .leading) { thumb }
        .padding(Self.inset)
        .frame(height: Self.height)
        .background(theme.palette.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    private func segment(_ option: Option) -> some View {
        let on = option.value == selection
        return Button {
            selection = option.value
        } label: {
            Text(option.title)
                .font(theme.type.title(13.5))
                .foregroundStyle(on ? theme.palette.textPrimary : theme.palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                // The thumb's shape: the segment's own box, which the thumb fills.
                .foilFocusOutline(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        // The label draws the foil focus outline (macOS); no system ring too.
        .macFocusEffectDisabled()
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityRemoveTraits(on ? [] : .isSelected)
    }

    /// One thumb, offset to the selected segment, so it slides rather than
    /// cross-fading between segments.
    private var thumb: some View {
        GeometryReader { geo in
            let count = CGFloat(max(options.count, 1))
            let width = geo.size.width / count
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Self.thumbFill)
                .shadow(color: .black.opacity(0.45), radius: 1, y: 1)
                .frame(width: width, height: geo.size.height)
                .offset(x: width * CGFloat(selectedIndex))
                .animation(reduceMotion ? nil : .spring(duration: 0.3), value: selectedIndex)
        }
        .accessibilityHidden(true)
    }
}
