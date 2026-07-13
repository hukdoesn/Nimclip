import AppKit
import SwiftData
import XCTest
@testable import Cliplet

@MainActor
final class ClipboardProductivityTests: XCTestCase {
    func testPresentationKindClassifiesCommonClipboardContent() {
        XCTAssertEqual(
            ClipboardPresentationKind.classify(kind: .text, text: "明天下午同步产品进度"),
            .text
        )
        XCTAssertEqual(
            ClipboardPresentationKind.classify(
                kind: .text,
                text: "https://developer.apple.com/design/human-interface-guidelines/"
            ),
            .link
        )
        XCTAssertEqual(
            ClipboardPresentationKind.classify(kind: .text, text: "npm run build"),
            .code
        )
        XCTAssertEqual(
            ClipboardPresentationKind.classify(
                kind: .text,
                text: "struct Clip {\n    let value: String\n}"
            ),
            .code
        )
        XCTAssertEqual(
            ClipboardPresentationKind.classify(kind: .image, text: nil),
            .image
        )
    }

    func testContentFiltersOnlyIncludeTheirMatchingKind() {
        XCTAssertTrue(ClipboardContentFilter.all.includes(.image))
        XCTAssertTrue(ClipboardContentFilter.link.includes(.link))
        XCTAssertTrue(ClipboardContentFilter.code.includes(.code))
        XCTAssertFalse(ClipboardContentFilter.text.includes(.link))
        XCTAssertFalse(ClipboardContentFilter.image.includes(.text))
    }

    func testVisibleItemsRefreshWhenSearchFilterOrStoreChanges() throws {
        let schema = Schema([ClipboardItem.self, ClipTag.self, AppSettings.self])
        let configuration = ModelConfiguration(
            "ClipboardVisibleItemsTests",
            schema: schema,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(for: schema, configurations: configuration)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardVisibleItemsTests-\(UUID().uuidString)")
        let store = try ClipboardStore(modelContainer: container, imagesDirectory: directory)
        _ = try store.ingestText("产品发布检查清单")
        _ = try store.ingestText("https://developer.apple.com/")
        _ = try store.ingestText("npm run build")

        let pasteboard = NSPasteboard(
            name: .init("ClipboardVisibleItemsTests.source.\(UUID().uuidString)")
        )
        let monitor = ClipboardMonitor(pasteboard: pasteboard, pollingInterval: .seconds(3_600))
        let viewModel = ClipletViewModel(store: store, monitor: monitor)
        defer {
            viewModel.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }

        XCTAssertEqual(viewModel.items.count, 3)

        viewModel.selectedContentFilter = .link
        XCTAssertEqual(viewModel.items.count, 1)
        XCTAssertEqual(viewModel.presentationKind(for: try XCTUnwrap(viewModel.items.first)), .link)

        viewModel.searchText = "missing"
        XCTAssertTrue(viewModel.items.isEmpty)

        viewModel.searchText = ""
        viewModel.selectedContentFilter = .code
        XCTAssertEqual(viewModel.items.count, 1)

        viewModel.selectedContentFilter = .all
        _ = try store.ingestText("稍后加入的记录")
        viewModel.prepareToShow()
        XCTAssertEqual(viewModel.items.count, 4)
    }

    func testMultipleTextItemsCanBeCombinedInSelectionOrderAndCopied() throws {
        let schema = Schema([ClipboardItem.self, ClipTag.self, AppSettings.self])
        let configuration = ModelConfiguration(
            "ClipboardProductivityTests",
            schema: schema,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(for: schema, configurations: configuration)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardProductivityTests-\(UUID().uuidString)")
        let store = try ClipboardStore(modelContainer: container, imagesDirectory: directory)
        let sourcePasteboard = NSPasteboard(
            name: .init("ClipboardProductivityTests.source.\(UUID().uuidString)")
        )
        let targetPasteboard = NSPasteboard(
            name: .init("ClipboardProductivityTests.target.\(UUID().uuidString)")
        )
        let monitor = ClipboardMonitor(pasteboard: sourcePasteboard, pollingInterval: .seconds(3_600))
        let coordinator = PasteCoordinator(pasteboard: targetPasteboard)
        let viewModel = ClipletViewModel(
            store: store,
            monitor: monitor,
            pasteCoordinator: coordinator
        )
        defer {
            viewModel.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }

        let first = try store.ingestText("第一段\n")
        let second = try store.ingestText("第二段")

        XCTAssertEqual(
            viewModel.combinedText(for: [second.id, first.id]),
            "第二段\n第一段"
        )

        viewModel.copyCombined([first.id, second.id])
        XCTAssertEqual(targetPasteboard.string(forType: .string), "第一段\n第二段")
    }
}
