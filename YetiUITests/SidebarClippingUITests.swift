import XCTest

/// Sidebar / split-view layout integrity coverage.
///
/// Background — and an honest scope note: the original defect was the left sidebar
/// being clipped off the window's LEFT edge when the window was dragged narrow
/// with the Dashboard open. That specific failure is an *interactive* left-edge
/// drag rendering artifact. It was exhaustively confirmed NOT reproducible by any
/// automated means — a forced `.frame(width:)`, an `NSWindow.setFrame` to the
/// minimum, and XCUITest's own programmatic edge-drag all re-lay-out the content
/// cleanly (the programmatic drag genuinely resizes the window, yet no clip).
/// Only a human's continuous drag reproduces it. So these tests do NOT pretend to
/// reproduce that transient; instead they lock down the durable, deterministic
/// invariant the fix is built on:
///
///   At the window's *enforced minimum* (which `.windowResizability(.contentMinSize)`
///   now derives from the sum of the visible columns' minimums — sidebar 150 +
///   detail 480 + inspector 250 — instead of a hardcoded constant), and across
///   inspector toggles and a real resize-drag, the sidebar column keeps a usable
///   width and every row stays inside the window and reachable.
///
/// This catches gross regressions (sidebar missing, collapsed, off-screen, a min
/// that's far too small, a broken inspector toggle). They run against the `-UITEST`
/// stub state (forced `.loggedIn`, no network) so the sidebar renders without login.
@MainActor
final class SidebarClippingUITests: XCTestCase {

    private let sidebarIDs = [
        "sidebar.item.home",
        "sidebar.item.artists",
        "sidebar.item.videos",
        "sidebar.item.favorites",
        "sidebar.item.search",
    ]

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        app?.terminate()
        app = nil
        // Let the window server settle before the next test's launch — rapid
        // back-to-back launches otherwise wedge ("window never appeared").
        Thread.sleep(forTimeInterval: 1.5)
        super.tearDown()
    }

    /// Launch the stubbed, logged-in app and ensure its window is foregrounded
    /// (activate + a one-shot relaunch guard avoid the flaky "window never
    /// appeared"). When `shrinkToMinimum` is true, pass `-UITestShrinkWindow` so
    /// the app parks the window at its enforced (content-derived) minimum, and
    /// wait for that resize to settle.
    private func launchedApp(shrinkToMinimum: Bool,
                             file: StaticString = #filePath,
                             line: UInt = #line) -> XCUIApplication {
        let app = XCUIApplication()
        self.app = app
        app.launchArguments += ["-UITEST", "-ApplePersistenceIgnoreState", "YES"]
        if shrinkToMinimum {
            app.launchArguments += ["-UITestShrinkWindow"]
        }
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 10)
        app.activate()
        if !app.windows.firstMatch.waitForExistence(timeout: 12) {
            app.terminate()
            _ = app.wait(for: .notRunning, timeout: 5)
            app.launch()
            _ = app.wait(for: .runningForeground, timeout: 10)
            app.activate()
        }
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 12),
                      "window never appeared (app launched but did not foreground)",
                      file: file, line: line)
        if shrinkToMinimum {
            waitForWindowToSettle(app.windows.firstMatch)
        }
        return app
    }

    /// Poll until the window's width stops changing (the `-UITestShrinkWindow`
    /// resize has applied and AppKit has clamped to the minimum).
    private func waitForWindowToSettle(_ window: XCUIElement) {
        Thread.sleep(forTimeInterval: 0.8)   // past the app's 0.4s deferred resize
        var last = window.frame.width
        var stable = 0
        let deadline = Date().addingTimeInterval(6)
        while stable < 3 && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
            let w = window.frame.width
            if abs(w - last) < 1 { stable += 1 } else { stable = 0; last = w }
        }
    }

    private func cell(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// Core assertion: the sidebar column has a usable width and sits fully inside
    /// the window (not overflowed off the left edge), and every row is reachable.
    ///
    /// The per-row accessibility id is on the `Text` label, so a row's
    /// `.frame.width` is the *label* width (~36pt for "Home"), NOT the column
    /// width — so column width is measured from the List element (`sidebar.list`),
    /// and the clip signal is each row's left edge vs. the window's left edge plus
    /// hittability.
    private func assertSidebarNotClipped(_ app: XCUIApplication,
                                         context: String,
                                         file: StaticString = #filePath,
                                         line: UInt = #line) {
        let window = app.windows.firstMatch
        let win = window.frame
        let edgeTolerance: CGFloat = 2
        let minColumnWidth: CGFloat = 140   // column min is 150; a squeeze collapses below this

        // 1) The sidebar column (the List): usable width, fully inside the window.
        let list = app.descendants(matching: .any)
            .matching(identifier: "sidebar.list").firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 12),
                      "[\(context)] sidebar list did not render (win \(win.width))",
                      file: file, line: line)
        let lf = list.frame
        XCTAssertGreaterThanOrEqual(
            lf.minX, win.minX - edgeTolerance,
            "[\(context)] sidebar column left edge \(lf.minX) is left of window \(win.minX) — clipped off the left (win width \(win.width))",
            file: file, line: line)
        XCTAssertGreaterThanOrEqual(
            lf.width, minColumnWidth,
            "[\(context)] sidebar column width \(lf.width) < \(minColumnWidth) — column squeezed (win width \(win.width))",
            file: file, line: line)

        // 2) Every row — reachable and inside the window.
        for id in sidebarIDs {
            let el = cell(app, id)
            XCTAssertTrue(el.waitForExistence(timeout: 5),
                          "[\(context)] '\(id)' not found — sidebar didn't render",
                          file: file, line: line)
            let f = el.frame
            XCTAssertGreaterThanOrEqual(
                f.minX, win.minX - edgeTolerance,
                "[\(context)] '\(id)' left edge \(f.minX) is left of window \(win.minX) — sidebar clipped off the left (win width \(win.width))",
                file: file, line: line)
            XCTAssertTrue(el.isHittable,
                "[\(context)] '\(id)' is not hittable — off-screen/clipped (win width \(win.width))",
                file: file, line: line)
        }

        let shot = XCTAttachment(screenshot: window.screenshot())
        shot.name = "sidebar-\(context)-w\(Int(win.width))"
        shot.lifetime = .keepAlways
        add(shot)
    }

    // MARK: - Integrity cases

    /// At the enforced minimum with the Dashboard open, the sidebar must be intact.
    func testSidebarIntact_atEnforcedMinimum_inspectorOpen() {
        let app = launchedApp(shrinkToMinimum: true)
        assertSidebarNotClipped(app, context: "min-inspectorOpen")
    }

    /// At the enforced minimum with the Dashboard closed (the content-derived
    /// floor drops to two columns), the sidebar must still be intact.
    func testSidebarIntact_atEnforcedMinimum_inspectorClosed() {
        let app = launchedApp(shrinkToMinimum: true)
        let dashboard = app.buttons["Dashboard"].firstMatch
        if dashboard.waitForExistence(timeout: 10) { dashboard.click() }
        assertSidebarNotClipped(app, context: "min-inspectorClosed")
    }

    /// Control: at a comfortable (default) width the sidebar must be perfect.
    func testSidebarIntact_wideWindow() {
        let app = launchedApp(shrinkToMinimum: false)
        assertSidebarNotClipped(app, context: "wide")
    }

    /// Toggling the Dashboard closed then open at the minimum must not break the
    /// sidebar across the re-layout (the inspector-open floor is the demanding one).
    func testSidebarIntact_acrossInspectorToggle_atMinimum() {
        let app = launchedApp(shrinkToMinimum: true)
        let dashboard = app.buttons["Dashboard"].firstMatch
        XCTAssertTrue(dashboard.waitForExistence(timeout: 10),
                      "Dashboard toggle not found")
        dashboard.click()  // close
        assertSidebarNotClipped(app, context: "toggle-closed")
        dashboard.click()  // reopen
        assertSidebarNotClipped(app, context: "toggle-reopened")
    }

    /// A genuine interactive resize-drag (left edge inward, right edge fixed) must
    /// actually shrink the window and leave the sidebar intact. This is the closest
    /// automated proxy for the human gesture; it confirms the window honours its
    /// content-derived minimum during a real drag rather than overflowing.
    func testSidebarIntact_afterResizeDragToMinimum() {
        let app = launchedApp(shrinkToMinimum: false)
        let window = app.windows.firstMatch
        let widthBefore = window.frame.width
        let edge = window.coordinate(withNormalizedOffset: CGVector(dx: 0.0, dy: 0.5))
        edge.press(forDuration: 0.4,
                   thenDragTo: edge.withOffset(CGVector(dx: 800, dy: 0.0)))
        Thread.sleep(forTimeInterval: 0.8)
        let widthAfter = window.frame.width
        XCTAssertLessThan(widthAfter, widthBefore - 50,
            "resize drag did not shrink the window: before=\(widthBefore) after=\(widthAfter)")
        assertSidebarNotClipped(app, context: "afterResizeDrag")
    }
}
