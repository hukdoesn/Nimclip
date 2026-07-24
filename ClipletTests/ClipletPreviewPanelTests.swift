import AppKit
import XCTest
@testable import Cliplet

@MainActor
final class ClipletPreviewPanelTests: XCTestCase {
    func testHoldingOptionPreviewsOnlyAfterThePointerHoversAnItem() {
        let hoveredItemID = UUID()
        let interaction = ClipletPreviewInteractionState()

        XCTAssertTrue(interaction.updateOptionState(true))
        XCTAssertTrue(interaction.isOptionPressed)
        XCTAssertNil(interaction.previewItemID)

        XCTAssertTrue(
            interaction.beginPreview(
                for: hoveredItemID,
                optionIsPhysicallyPressed: true
            )
        )
        XCTAssertEqual(interaction.hoveredItemID, hoveredItemID)
        XCTAssertEqual(interaction.previewItemID, hoveredItemID)

        XCTAssertTrue(interaction.updateOptionState(false))
        XCTAssertFalse(interaction.isOptionPressed)
        XCTAssertNil(interaction.previewItemID)
    }

    func testMenuPopoverStaysWithItsOpeningDisplay() {
        XCTAssertEqual(
            ClipletAppDelegate.menuPopoverBehavior,
            .applicationDefined
        )
        XCTAssertFalse(
            ClipletAppDelegate.menuPopoverWindowCollectionBehavior.contains(
                .canJoinAllSpaces
            )
        )
        XCTAssertFalse(
            ClipletAppDelegate.menuPopoverWindowCollectionBehavior.contains(
                .moveToActiveSpace
            )
        )
        XCTAssertTrue(
            ClipletAppDelegate.menuPopoverWindowCollectionBehavior.contains(
                .fullScreenAuxiliary
            )
        )
    }

    func testOptionPrimaryActionStartsPreviewInsteadOfPasting() {
        let itemID = UUID()
        let interaction = ClipletPreviewInteractionState()

        XCTAssertFalse(
            interaction.beginPreview(
                for: itemID,
                optionIsPhysicallyPressed: false
            )
        )
        XCTAssertTrue(
            interaction.beginPreview(
                for: itemID,
                optionIsPhysicallyPressed: true
            )
        )
        XCTAssertEqual(interaction.hoveredItemID, itemID)
        XCTAssertEqual(interaction.previewItemID, itemID)
        XCTAssertTrue(interaction.isOptionPressed)
    }

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
        XCTAssertEqual(panel?.hidesOnDeactivate, false)
        XCTAssertEqual(panel?.isVisible, true)
        XCTAssertFalse(
            panel?.collectionBehavior.contains(.moveToActiveSpace) ?? true
        )
        XCTAssertFalse(
            panel?.collectionBehavior.contains(.canJoinAllSpaces) ?? true
        )

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
        XCTAssertNil(panel?.contentViewController)
    }

    func testPreviewStaysVisibleWhilePointerIsInsideThenClosesAfterExit() async {
        let item = ClipboardItem(
            kind: .text,
            text: String(repeating: "可滚动预览内容\n", count: 40),
            contentHash: UUID().uuidString,
            sourceAppName: "测试"
        )
        let insideController = ClipletPreviewPanelController(
            hideDelay: .seconds(30)
        )
        insideController.show(
            item: item,
            imageURL: nil,
            thumbnailURL: nil,
            referenceDate: Date(),
            relativeTo: nil
        )

        insideController.setPreviewPointerInside(true)
        insideController.requestHide()
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(insideController.panel?.isVisible, true)
        insideController.hide()

        let exitController = ClipletPreviewPanelController(
            hideDelay: .milliseconds(10)
        )
        exitController.show(
            item: item,
            imageURL: nil,
            thumbnailURL: nil,
            referenceDate: Date(),
            relativeTo: nil
        )
        // Keep the real pointer from racing this state-driven unit test when
        // rendering tests execute in parallel and temporarily move the mouse.
        exitController.panel?.setFrameOrigin(
            NSPoint(x: -10_000, y: -10_000)
        )
        exitController.setPreviewPointerInside(false)
        for _ in 0..<200 where exitController.panel?.isVisible == true {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(exitController.panel?.isVisible, false)
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

    func testTextNoteAddsRoomWithoutExceedingTheScreen() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let withoutNote = ClipletPreviewPanelController.preferredSize(
            kind: .text,
            imageSize: nil,
            hasTags: false,
            visibleFrame: visibleFrame,
            text: "一段简短文本"
        )
        let withNote = ClipletPreviewPanelController.preferredSize(
            kind: .text,
            imageSize: nil,
            hasTags: false,
            visibleFrame: visibleFrame,
            text: "一段简短文本",
            note: "这是用于整理收藏内容的备注。"
        )

        XCTAssertGreaterThan(withNote.height, withoutNote.height)
        XCTAssertGreaterThanOrEqual(withNote.height, 215)
        XCTAssertLessThanOrEqual(withNote.height, 680)
    }

    func testPreviewShrinksToAvailableRightSideWithoutOverlappingSource() {
        let visibleFrame = CGRect(x: 100, y: 80, width: 900, height: 640)
        let sourceFrame = CGRect(x: 160, y: 160, width: 420, height: 560)
        let availableWidth = ClipletPreviewPanelController.rightSideAvailableWidth(
            sourceFrame: sourceFrame,
            visibleFrame: visibleFrame
        )
        let size = ClipletPreviewPanelController.preferredSize(
            kind: .image,
            imageSize: CGSize(width: 1_920, height: 1_080),
            hasTags: true,
            visibleFrame: visibleFrame,
            maximumWidth: availableWidth
        )
        let origin = ClipletPreviewPanelController.preferredOrigin(
            previewSize: size,
            sourceFrame: sourceFrame,
            visibleFrame: visibleFrame
        )
        let previewFrame = CGRect(origin: origin, size: size)

        XCTAssertEqual(availableWidth, 392, accuracy: 0.5)
        XCTAssertEqual(size.width, availableWidth, accuracy: 0.5)
        XCTAssertEqual(origin.x, sourceFrame.maxX + 12, accuracy: 0.5)
        XCTAssertGreaterThan(previewFrame.minX, sourceFrame.maxX)
        XCTAssertGreaterThanOrEqual(previewFrame.minX, visibleFrame.minX + 16)
        XCTAssertGreaterThanOrEqual(previewFrame.minY, visibleFrame.minY + 16)
        XCTAssertLessThanOrEqual(previewFrame.maxX, visibleFrame.maxX - 16)
        XCTAssertLessThanOrEqual(previewFrame.maxY, visibleFrame.maxY - 16)
    }

    func testPreviewOriginNeverFallsBackToTheLeftOrCenter() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let sourceFrame = CGRect(x: 120, y: 180, width: 440, height: 600)
        let previewSize = CGSize(width: 1_000, height: 500)

        let origin = ClipletPreviewPanelController.preferredOrigin(
            previewSize: previewSize,
            sourceFrame: sourceFrame,
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(origin.x, sourceFrame.maxX + 12, accuracy: 0.5)
    }
}
