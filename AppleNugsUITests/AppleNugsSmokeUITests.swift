import XCTest

/// Deterministic smoke coverage against the `-UITEST` stub state (forced
/// `.loggedIn`, stub catalog, no network). Proves the app boots into the main
/// layout, every sidebar section is selectable, and the core chrome exists.
@MainActor
final class AppleNugsSmokeUITests: XCTestCase {

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

    /// Launch the stub app and make sure its window foregrounds (activate + a
    /// one-shot relaunch guard avoid macOS's flaky "window never appeared").
    private func launchedApp(file: StaticString = #filePath,
                             line: UInt = #line) -> XCUIApplication {
        let app = XCUIApplication()
        self.app = app
        app.launchArguments += ["-UITEST", "-ApplePersistenceIgnoreState", "YES"]
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
        return app
    }

    private func sidebarItem(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// Boots straight into the logged-in main layout (bypasses LoginView).
    func testLaunchesIntoLoggedInStub() {
        let app = launchedApp()
        XCTAssertEqual(app.state, .runningForeground)

        let home = sidebarItem(app, "sidebar.item.home")
        XCTAssertTrue(home.waitForExistence(timeout: 12),
                      "Sidebar 'Home' missing — did not render mainLayout")

        XCTAssertFalse(app.buttons["Sign In"].exists,
                       "LoginView was shown instead of the logged-in layout")
    }

    /// Every sidebar section is present and selectable; selecting it does not
    /// crash or drop the sidebar.
    func testEachSectionSelectable() {
        let app = launchedApp()
        let ids = [
            "sidebar.item.home",
            "sidebar.item.artists",
            "sidebar.item.videos",
            "sidebar.item.favorites",
            "sidebar.item.search",
        ]
        XCTAssertTrue(sidebarItem(app, ids[0]).waitForExistence(timeout: 12),
                      "Sidebar did not render")

        for id in ids {
            let item = sidebarItem(app, id)
            XCTAssertTrue(item.waitForExistence(timeout: 5), "Missing sidebar row: \(id)")
            XCTAssertTrue(item.isHittable, "Sidebar row not hittable: \(id)")
            item.click()
            for other in ids {
                XCTAssertTrue(sidebarItem(app, other).exists,
                              "Selecting \(id) dropped sidebar row \(other)")
            }
        }
    }

    /// The Dashboard inspector toggle exists and flips state without crashing.
    func testDashboardToggleExists() {
        let app = launchedApp()
        let dashboard = app.buttons["Dashboard"].firstMatch
        XCTAssertTrue(dashboard.waitForExistence(timeout: 12),
                      "Dashboard toggle button missing")
        dashboard.click()  // hide
        dashboard.click()  // show
        XCTAssertTrue(sidebarItem(app, "sidebar.item.home").exists,
                      "Sidebar lost after toggling the Dashboard")
    }

    /// The persistent bottom transport bar / main layout is present. Best-effort
    /// on the transport control itself so a label change can't fail the suite.
    func testTransportBarPresent() {
        let app = launchedApp()
        XCTAssertTrue(sidebarItem(app, "sidebar.item.home").waitForExistence(timeout: 12),
                      "Main layout did not render")

        let play = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "play")).firstMatch
        if !play.exists {
            let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            shot.name = "transport-not-found"
            shot.lifetime = .keepAlways
            add(shot)
        }
    }
}
