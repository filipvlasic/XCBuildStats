import XCTest
import ServiceManagement
@testable import XCBuildStats

final class LoginItemTests: XCTestCase {
    func testShouldRegisterByDefaultMatrix() {
        XCTAssertTrue(LoginItem.shouldRegisterByDefault(status: .notRegistered, userDisabled: false), "fresh install → register")
        XCTAssertTrue(LoginItem.shouldRegisterByDefault(status: .notFound, userDisabled: false), "registration dropped by an app update → re-register")
        XCTAssertFalse(LoginItem.shouldRegisterByDefault(status: .enabled, userDisabled: false), "already on → nothing to do")
        XCTAssertFalse(LoginItem.shouldRegisterByDefault(status: .requiresApproval, userDisabled: false), "pending user approval → must not spam register()")
        XCTAssertFalse(LoginItem.shouldRegisterByDefault(status: .notRegistered, userDisabled: true), "user opted out → never re-enable")
        XCTAssertFalse(LoginItem.shouldRegisterByDefault(status: .enabled, userDisabled: true))
    }

    func testEphemeralLocationDetection() {
        XCTAssertFalse(AppLocation.isEphemeral(bundlePath: "/Applications/XCBuildStats.app"))
        XCTAssertFalse(AppLocation.isEphemeral(bundlePath: "/Users/me/Applications/XCBuildStats.app"))
        XCTAssertTrue(AppLocation.isEphemeral(bundlePath: "/Volumes/XCBuildStats/XCBuildStats.app"), "running off the mounted DMG")
        XCTAssertTrue(
            AppLocation.isEphemeral(bundlePath: "/private/var/folders/ab/cd123/T/AppTranslocation/9F1B/d/XCBuildStats.app"),
            "Gatekeeper App Translocation of a quarantined DMG launch"
        )
    }
}
