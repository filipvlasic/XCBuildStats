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

    func testConsentGatedFolderDetection() {
        let home: String = "/Users/me"
        XCTAssertTrue(AppLocation.isConsentGated(path: "/Users/me/Documents/DerivedData", home: home))
        XCTAssertTrue(AppLocation.isConsentGated(path: "/Users/me/Downloads/DD", home: home))
        XCTAssertTrue(AppLocation.isConsentGated(path: "/Users/me/Desktop", home: home))
        XCTAssertTrue(AppLocation.isConsentGated(path: "/Users/me/Library/Mobile Documents/com~apple~CloudDocs/DD", home: home), "iCloud Drive")
        XCTAssertTrue(AppLocation.isConsentGated(path: "/Users/me/Library/CloudStorage/Dropbox/DD", home: home))
        XCTAssertTrue(AppLocation.isConsentGated(path: "/Users/me/Projects/../Documents/DD", home: home), "path traversal must not bypass the check")

        XCTAssertFalse(AppLocation.isConsentGated(path: "/Users/me/Library/Developer/Xcode/DerivedData", home: home))
        XCTAssertFalse(AppLocation.isConsentGated(path: "/Users/me/DocumentsFoo/DD", home: home), "sibling folder with a gated prefix")
        XCTAssertFalse(AppLocation.isConsentGated(path: "/Volumes/ExternalSSD/DerivedData", home: home), "external volumes stay honored — the OS prompt there is about the user's own chosen data location")
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
