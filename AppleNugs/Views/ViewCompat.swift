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
}
