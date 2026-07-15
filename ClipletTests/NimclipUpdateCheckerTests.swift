import Foundation
import XCTest
@testable import Cliplet

final class NimclipUpdateCheckerTests: XCTestCase {
    func testVersionComparisonUsesSemanticVersionOrder() {
        XCTAssertTrue(NimclipUpdateChecker.isVersion("v1.1.0", newerThan: "1.0"))
        XCTAssertFalse(NimclipUpdateChecker.isVersion("1.0.0", newerThan: "1.0"))
        XCTAssertFalse(NimclipUpdateChecker.isVersion("1.0.1", newerThan: "1.1.0"))
        XCTAssertTrue(NimclipUpdateChecker.isVersion("2.0", newerThan: "1.99.99"))
    }

    func testStableVersionIsNewerThanPrerelease() {
        XCTAssertTrue(
            NimclipUpdateChecker.isVersion("1.1.0", newerThan: "1.1.0-beta.2")
        )
        XCTAssertFalse(
            NimclipUpdateChecker.isVersion("1.1.0-beta.2", newerThan: "1.1.0")
        )
    }

    func testLatestReleaseResponseCreatesUpdate() throws {
        let data = Data(
            #"{"tag_name":"v1.1.0","html_url":"https://github.com/hukdoesn/Nimclip/releases/tag/v1.1.0","draft":false,"prerelease":false}"#.utf8
        )

        let update = try XCTUnwrap(
            NimclipUpdateChecker.availableUpdate(
                from: data,
                currentVersion: "1.0.0"
            )
        )

        XCTAssertEqual(update.version, "1.1.0")
        XCTAssertEqual(
            update.releaseURL.absoluteString,
            "https://github.com/hukdoesn/Nimclip/releases/tag/v1.1.0"
        )
    }

    func testCurrentOrPrereleaseVersionDoesNotCreateUpdate() throws {
        let currentRelease = Data(
            #"{"tag_name":"v1.0.0","html_url":"https://example.com/current","draft":false,"prerelease":false}"#.utf8
        )
        XCTAssertNil(
            try NimclipUpdateChecker.availableUpdate(
                from: currentRelease,
                currentVersion: "1.0.0"
            )
        )

        let prerelease = Data(
            #"{"tag_name":"v1.2.0-beta.1","html_url":"https://example.com/beta","draft":false,"prerelease":true}"#.utf8
        )
        XCTAssertNil(
            try NimclipUpdateChecker.availableUpdate(
                from: prerelease,
                currentVersion: "1.0.0"
            )
        )
    }
}
