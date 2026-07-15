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

    func testEnglishTimestampsUseEnglishUnits() {
        XCTAssertEqual(formatted(secondsAgo: 60, language: .english), "1 minute ago")
        XCTAssertEqual(formatted(secondsAgo: 7_200, language: .english), "2 hours ago")
        XCTAssertEqual(formatted(secondsAgo: 172_800, language: .english), "2 days ago")
    }

    func testEnglishAuthorLabelsKeepChineseDisplayName() {
        XCTAssertEqual(
            NimclipLanguage.english.localized("微信二维码，联系人胡图图不涂涂"),
            "WeChat QR code for 胡图图不涂涂"
        )
        XCTAssertEqual(
            NimclipLanguage.english.localized("支付宝收款码，收款人胡图图不涂涂"),
            "Alipay QR code for 胡图图不涂涂"
        )
    }

    private func formatted(
        secondsAgo: TimeInterval,
        language: NimclipLanguage = .defaultLanguage
    ) -> String {
        ClipletTimestampFormatter.string(
            for: referenceDate.addingTimeInterval(-secondsAgo),
            relativeTo: referenceDate,
            calendar: Calendar(identifier: .gregorian),
            language: language
        )
    }
}
