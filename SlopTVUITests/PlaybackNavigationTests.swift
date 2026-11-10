import XCTest

/// Checks that the Siri Remote's Back/Menu button leaves the player and returns to the app,
/// instead of getting stuck in the player or exiting to the tvOS home screen.
final class PlaybackNavigationTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testBackButtonClosesLivePlayer() {
        let app = XCUIApplication()
        app.launchArguments = ["-autoplayLive"]
        app.launch()

        // The app opens the live player about a second after launch; give the stream time to start.
        sleep(12)
        add(XCTAttachment(screenshot: app.screenshot()))

        // Home's billboard button is hidden while the full-screen player covers Home.
        let homeButton = app.buttons["Watch Live"]
        XCTAssertFalse(homeButton.exists, "the live player didn't open")

        // Back first closes whatever the player has open (info panel, controls), then the player.
        var presses = 0
        while !homeButton.exists && presses < 4 {
            XCUIRemote.shared.press(.menu)
            presses += 1
            _ = homeButton.waitForExistence(timeout: 3)
        }

        XCTAssertTrue(homeButton.waitForExistence(timeout: 10), "still in the player after pressing Back")
        XCTAssertEqual(app.state, .runningForeground, "Back left the app instead of the player")
        add(XCTAttachment(screenshot: app.screenshot()))
    }
}
