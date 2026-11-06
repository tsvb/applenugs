import SwiftUI

// Small cross-platform view shims. Anything here exists because one platform
// has a modifier the other doesn't, and the call site reads better without an
// `#if` wrapped around it.

extension View {
    /// Inline navigation title on iOS; unchanged on macOS.
    ///
    /// A large title costs ~52pt of a phone and, on the tab roots, prints the
    /// label of the tab the user just tapped. Detail screens print their title
    /// again in the header below it, and Library's only repeats the segment
    /// its Picker already names. Inline keeps the title as a scroll anchor and
    /// hands the space back to content.
    func compactNavigationTitle() -> some View {
        #if os(iOS)
        return navigationBarTitleDisplayMode(.inline)
        #else
        return self
        #endif
    }

    /// Reports this scroll view's motion to the now-playing pill's duck
    /// (`PillDuckScrollReporter`, iOS), and gives its content a bottom margin
    /// that clears the pill. Apply it to the ScrollView/List itself on every
    /// vertically scrolling tab root. Inert unless the pill is mounted as the
    /// iPhone Duo overlay; a no-op on macOS. Pass `insetsContent: false` where
    /// `clearsPillOverlay()` already pads an enclosing view.
    func reportsScrollForPillDuck(insetsContent: Bool = true) -> some View {
        #if os(iOS)
        return modifier(PillDuckScrollReporter(insetsContent: insetsContent))
        #else
        return self
        #endif
    }

    /// Extra bottom safe area clearing the iPhone Duo overlay pill, for a
    /// screen whose bottom edge isn't just a scroll view (`PillOverlayClearance`,
    /// iOS). Inert unless the overlay is mounted; a no-op on macOS.
    func clearsPillOverlay() -> some View {
        #if os(iOS)
        return modifier(PillOverlayClearance())
        #else
        return self
        #endif
    }
}
