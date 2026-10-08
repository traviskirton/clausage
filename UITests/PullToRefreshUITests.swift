import XCTest

/// Drives a slow pull on the Usage screen (sample data) so the states can be screenshotted from outside with
/// `xcrun simctl io <sim> screenshot` while the finger is held. Not a pass/fail test.
/// Env (prefix TEST_RUNNER_ when passed through xcodebuild): PTR_DRAG points to drag, PTR_HOLD seconds to hold.
final class PullToRefreshUITests: XCTestCase {
    func testPullAndHold() {
        let env = ProcessInfo.processInfo.environment
        let distance = Double(env["PTR_DRAG"] ?? "160") ?? 160
        let hold = Double(env["PTR_HOLD"] ?? "4") ?? 4
        let app = XCUIApplication()
        app.launchArguments = ["--sample", "max-idle"]
        app.launch()
        sleep(3)
        let start = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: distance)),
                    withVelocity: .slow, thenHoldForDuration: hold)
        sleep(5)
    }
}
