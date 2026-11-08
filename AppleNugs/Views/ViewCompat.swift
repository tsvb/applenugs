import SwiftUI

// Small cross-platform view shims. Anything here exists because one platform
// has a modifier the other doesn't, and the call site reads better without an
// `#if` wrapped around it.

extension View {
    /// On iOS, removes the navigation bar's visible title while keeping
    /// `navigationTitle` itself — the next screen's back button and its
    /// long-press history still read it. For a screen whose header already
    /// prints the same name in large type (the artist page), so the bar shows
    /// only the back button. Unchanged on macOS, where the title is the
    /// window's.
    func hidesNavigationBarTitle() -> some View {
        #if os(iOS)
        return toolbar(removing: .title)
        #else
        return self
        #endif
    }

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
}
