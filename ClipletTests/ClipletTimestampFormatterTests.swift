import XCTest
@testable import Cliplet

final class ClipletTimestampFormatterTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 1_750_000_000)

    func testRecentTimestampsNeverDisplaySeconds() {
        XCTAssertEqual(formatted(secondsAgo: -120), "刚刚")
        XCTAssertEqual(formatted(secondsAgo: 59), "刚刚")
        XCTAssertEqual(formatted(secondsAgo: 60), "1 分钟前")
        XCTAssertEqual(formatted(secondsAgo: 3_599), "59 分钟前")
    }

    func testOlderTimestampsUseCoarseRelativeUnits() {
        XCTAssertEqual(formatted(secondsAgo: 3_600), "1 小时前")
        XCTAssertEqual(formatted(secondsAgo: 86_399), "23 小时前")
        XCTAssertEqual(formatted(secondsAgo: 86_400), "1 天前")
    }

    private func formatted(secondsAgo: TimeInterval) -> String {
        ClipletTimestampFormatter.string(
            for: referenceDate.addingTimeInterval(-secondsAgo),
            relativeTo: referenceDate,
            calendar: Calendar(identifier: .gregorian)
        )
    }
}
