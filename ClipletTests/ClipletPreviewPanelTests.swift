import AppKit
import XCTest
@testable import Cliplet

@MainActor
final class ClipletPreviewPanelTests: XCTestCase {
    func testPreviewPanelIsNonActivatingAndCanBeHidden() {
        let item = ClipboardItem(
            kind: .text,
            text: "Nimclip preview",
            contentHash: UUID().uuidString,
            sourceAppName: "测试"
        )
        let controller = ClipletPreviewPanelController()

        controller.show(
            item: item,
            imageURL: nil,
            thumbnailURL: nil,
            referenceDate: Date(),
            relativeTo: nil
        )

        let panel = controller.panel
        XCTAssertNotNil(panel)
        XCTAssertEqual(panel?.level, .popUpMenu)
        XCTAssertEqual(panel?.ignoresMouseEvents, false)
        XCTAssertEqual(panel?.acceptsMouseMovedEvents, true)
        XCTAssertEqual(panel?.styleMask.contains(.nonactivatingPanel), true)
        XCTAssertEqual(panel?.isVisible, true)

        if let darkAppearance = NSAppearance(named: .darkAqua) {
            controller.applyAppearance(darkAppearance)
            XCTAssertEqual(
                panel?.appearance?.bestMatch(from: [.aqua, .darkAqua]),
                .darkAqua
            )
        }

        let firstContentController = panel?.contentViewController
        let secondItem = ClipboardItem(
            kind: .text,
            text: "Updated preview",
            contentHash: UUID().uuidString,
            sourceAppName: "测试"
        )
        controller.show(
            item: secondItem,
            imageURL: nil,
            thumbnailURL: nil,
            referenceDate: Date(),
            relativeTo: nil
        )
        XCTAssertTrue(panel?.contentViewController === firstContentController)

        controller.hide()
        XCTAssertEqual(panel?.isVisible, false)
    }

    func testPreviewStaysVisibleWhilePointerIsInsideThenClosesAfterExit() async {
        let item = ClipboardItem(
            kind: .text,
            text: String(repeating: "可滚动预览内容\n", count: 40),
            contentHash: UUID().uuidString,
            sourceAppName: "测试"
        )
        let controller = ClipletPreviewPanelController(hideDelay: .milliseconds(10))
        controller.show(
            item: item,
            imageURL: nil,
            thumbnailURL: nil,
            referenceDate: Date(),
            relativeTo: nil
        )

        controller.setPreviewPointerInside(true)
        controller.requestHide()
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(controller.panel?.isVisible, true)

        controller.setPreviewPointerInside(false)
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(controller.panel?.isVisible, false)
    }

    func testWideImagePreviewStaysContentFocusedAndWithinScreen() {
        let size = ClipletPreviewPanelController.preferredSize(
            kind: .image,
            imageSize: CGSize(width: 1_920, height: 1_080),
            hasTags: false,
            visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900)
        )

        XCTAssertGreaterThanOrEqual(size.width, 740)
        XCTAssertLessThanOrEqual(size.width, 780)
        XCTAssertGreaterThan(size.height, 420)
        XCTAssertLessThan(size.height, 540)
    }

    func testTextPreviewAdaptsToContentLength() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let short = ClipletPreviewPanelController.preferredSize(
            kind: .text,
            imageSize: nil,
            hasTags: false,
            visibleFrame: visibleFrame,
            text: "一段简短文本"
        )
        let long = ClipletPreviewPanelController.preferredSize(
            kind: .text,
            imageSize: nil,
            hasTags: false,
            visibleFrame: visibleFrame,
            text: String(repeating: "完整内容需要继续阅读。", count: 80)
        )

        XCTAssertEqual(short.width, 480)
        XCTAssertLessThanOrEqual(short.height, 220)
        XCTAssertGreaterThan(long.width, short.width)
        XCTAssertGreaterThan(long.height, short.height)
        XCTAssertLessThanOrEqual(long.height, 680)
    }

    func testPortraitPreviewAndFallbackOriginStayInsideVisibleFrame() {
        let visibleFrame = CGRect(x: 100, y: 80, width: 900, height: 640)
        let size = ClipletPreviewPanelController.preferredSize(
            kind: .image,
            imageSize: CGSize(width: 900, height: 1_600),
            hasTags: true,
            visibleFrame: visibleFrame
        )
        let origin = ClipletPreviewPanelController.preferredOrigin(
            previewSize: size,
            sourceFrame: CGRect(x: 420, y: 160, width: 420, height: 560),
            visibleFrame: visibleFrame
        )
        let previewFrame = CGRect(origin: origin, size: size)

        XCTAssertGreaterThanOrEqual(previewFrame.minX, visibleFrame.minX + 16)
        XCTAssertGreaterThanOrEqual(previewFrame.minY, visibleFrame.minY + 16)
        XCTAssertLessThanOrEqual(previewFrame.maxX, visibleFrame.maxX - 16)
        XCTAssertLessThanOrEqual(previewFrame.maxY, visibleFrame.maxY - 16)
    }
}
