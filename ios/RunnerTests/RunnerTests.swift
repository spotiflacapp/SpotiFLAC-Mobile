import Foundation
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {
    func testParsesOAuthCallback() {
        let route = ExtensionCallbackParser.parse(
            URL(string: "spotiflac://callback?code=auth-code&state=spotify-web")!
        )

        XCTAssertEqual(
            route,
            ExtensionCallbackRoute(
                code: "auth-code",
                extensionId: "spotify-web",
                isSessionGrant: false
            )
        )
    }

    func testParsesSignedSessionGrant() {
        let route = ExtensionCallbackParser.parse(
            URL(
                string:
                    "spotiflac://session-grant?grant=session-token&state=provider"
            )!
        )

        XCTAssertEqual(
            route,
            ExtensionCallbackRoute(
                code: "session-token",
                extensionId: "provider",
                isSessionGrant: true
            )
        )
    }

    func testRejectsUntrustedOrIncompleteCallbacks() {
        XCTAssertNil(
            ExtensionCallbackParser.parse(
                URL(string: "https://callback?code=auth&state=provider")!
            )
        )
        XCTAssertNil(
            ExtensionCallbackParser.parse(
                URL(string: "spotiflac://unknown?code=auth&state=provider")!
            )
        )
        XCTAssertNil(
            ExtensionCallbackParser.parse(
                URL(string: "spotiflac://callback?code=auth")!
            )
        )
        XCTAssertNil(
            ExtensionCallbackParser.parse(
                URL(string: "spotiflac://callback?state=provider")!
            )
        )
    }
}
