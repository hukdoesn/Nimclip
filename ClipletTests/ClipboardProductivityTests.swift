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

    func testPresentationKindClassificationBoundsVeryLargeClipboardText() {
        let text = String(repeating: "普通文本内容 ", count: 100_000)
            + "\nfunc delayedMarker() {}\nclass DelayedMarker {}"

        XCTAssertEqual(
            ClipboardPresentationKind.classify(kind: .text, text: text),
            .text,
            "Presentation classification must not rescan an entire oversized clipboard entry"
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

    func testPreparingToShowSelectsNewestItemAndRequestsTopScroll() throws {
        var now = Date(timeIntervalSince1970: 1_000)
        let schema = Schema([ClipboardItem.self, ClipTag.self, AppSettings.self])
        let configuration = ModelConfiguration(
            "ClipboardPresentationResetTests",
            schema: schema,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(for: schema, configurations: configuration)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ClipboardPresentationResetTests-\(UUID().uuidString)"
            )
        let store = try ClipboardStore(
            modelContainer: container,
            imagesDirectory: directory,
            now: { now }
        )
        _ = try store.ingestText("较早记录")
        now.addTimeInterval(1)
        _ = try store.ingestText("打开时的最新记录")

        let pasteboard = NSPasteboard(
            name: .init("ClipboardPresentationResetTests.source.\(UUID().uuidString)")
        )
        let monitor = ClipboardMonitor(
            pasteboard: pasteboard,
            pollingInterval: .seconds(3_600)
        )
        let viewModel = ClipletViewModel(store: store, monitor: monitor)
        defer {
            viewModel.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }

        viewModel.prepareToShow()
        XCTAssertEqual(viewModel.selectedItemID, viewModel.items.first?.id)
        let firstPresentationGeneration = viewModel.listPresentationGeneration

        viewModel.selectNext()
        XCTAssertNotEqual(viewModel.selectedItemID, viewModel.items.first?.id)

        now.addTimeInterval(1)
        let newest = try store.ingestText("后来复制的新记录")
        viewModel.prepareToShow()

        XCTAssertEqual(viewModel.selectedItemID, newest.id)
        XCTAssertEqual(
            viewModel.listPresentationGeneration,
            firstPresentationGeneration + 1
        )

        viewModel.prepareToShow()
        XCTAssertEqual(viewModel.selectedItemID, newest.id)
        XCTAssertEqual(
            viewModel.listPresentationGeneration,
            firstPresentationGeneration + 1,
            "Reopening without new content must preserve the reusable list position"
        )
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

    func testManualImageTextIndexingRunsSeriallyAndRefreshesSearch() async throws {
        let schema = Schema([ClipboardItem.self, ClipTag.self, AppSettings.self])
        let configuration = ModelConfiguration(
            "ClipboardManualImageTextTests",
            schema: schema,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(for: schema, configurations: configuration)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ClipboardManualImageTextTests-\(UUID().uuidString)"
            )
        let store = try ClipboardStore(
            modelContainer: container,
            imagesDirectory: directory
        )
        _ = try store.ingestImage(try pngData(variant: 1))
        _ = try store.ingestImage(try pngData(variant: 2))

        let pasteboard = NSPasteboard(
            name: .init("ClipboardManualImageTextTests.source.\(UUID().uuidString)")
        )
        let monitor = ClipboardMonitor(
            pasteboard: pasteboard,
            pollingInterval: .seconds(3_600)
        )
        let recognizer = StubImageTextRecognizer(
            results: ["Invoice number INV-2026", "项目截图"]
        )
        let viewModel = ClipletViewModel(
            store: store,
            monitor: monitor,
            imageTextRecognizer: recognizer
        )
        defer {
            viewModel.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }

        XCTAssertEqual(viewModel.unindexedImageCount, 2)
        viewModel.indexExistingImageText()
        try await waitUntil {
            !viewModel.isIndexingImageText
                && store.unindexedImageItems.isEmpty
        }

        let statistics = await recognizer.statistics()
        XCTAssertEqual(statistics.callCount, 2)
        XCTAssertEqual(statistics.maximumConcurrentCalls, 1)
        XCTAssertEqual(viewModel.imageTextIndexCompletedCount, 2)
        XCTAssertEqual(viewModel.imageTextIndexFailureCount, 0)

        viewModel.searchText = "INV-2026"
        XCTAssertEqual(viewModel.items.count, 1)
        XCTAssertEqual(viewModel.items.first?.kind, .image)

        viewModel.indexExistingImageText()
        await Task.yield()
        let statisticsAfterRetry = await recognizer.statistics()
        XCTAssertEqual(statisticsAfterRetry.callCount, 2)
    }

    func testNewImagesAreIndexedAutomaticallyOnlyWhenEnabled() async throws {
        let schema = Schema([ClipboardItem.self, ClipTag.self, AppSettings.self])
        let configuration = ModelConfiguration(
            "ClipboardAutomaticImageTextTests",
            schema: schema,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(for: schema, configurations: configuration)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ClipboardAutomaticImageTextTests-\(UUID().uuidString)"
            )
        let store = try ClipboardStore(
            modelContainer: container,
            imagesDirectory: directory
        )
        let pasteboard = NSPasteboard(
            name: .init("ClipboardAutomaticImageTextTests.source.\(UUID().uuidString)")
        )
        let monitor = ClipboardMonitor(
            pasteboard: pasteboard,
            pollingInterval: .seconds(3_600)
        )
        let recognizer = StubImageTextRecognizer(results: ["Receipt total 42"])
        let viewModel = ClipletViewModel(
            store: store,
            monitor: monitor,
            imageTextRecognizer: recognizer
        )
        defer {
            viewModel.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }

        pasteboard.clearContents()
        pasteboard.setData(try pngData(variant: 3), forType: .png)
        monitor.pollNow()
        try await waitUntil {
            store.items.count == 1
                && store.items.first?.imageTextIndexedAt != nil
        }

        XCTAssertEqual(
            store.filteredItems(searchText: "Receipt total").count,
            1
        )
        let automaticStatistics = await recognizer.statistics()
        XCTAssertEqual(automaticStatistics.callCount, 1)

        viewModel.automaticImageTextRecognition = false
        pasteboard.clearContents()
        pasteboard.setData(try pngData(variant: 4), forType: .png)
        monitor.pollNow()
        try await waitUntil { store.items.count == 2 }
        try await Task.sleep(for: .milliseconds(100))

        let disabledStatistics = await recognizer.statistics()
        XCTAssertEqual(disabledStatistics.callCount, 1)
        XCTAssertEqual(store.unindexedImageItems.count, 1)
    }

    private func pngData(variant: UInt8) throws -> Data {
        var data = try XCTUnwrap(
            Data(
                base64Encoded:
                    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
            )
        )
        // PNG decoders ignore trailing bytes, while the store hash stays unique.
        data.append(variant)
        return data
    }

    private func waitUntil(
        timeout: TimeInterval = 3,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() >= deadline {
                XCTFail("Timed out waiting for the asynchronous condition")
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

private actor StubImageTextRecognizer: ClipboardImageTextRecognizing {
    private let results: [String]
    private var nextResultIndex = 0
    private var callCount = 0
    private var concurrentCalls = 0
    private var maximumConcurrentCalls = 0

    init(results: [String]) {
        self.results = results
    }

    func recognizeText(at imageURL: URL) async throws -> String {
        callCount += 1
        concurrentCalls += 1
        maximumConcurrentCalls = max(maximumConcurrentCalls, concurrentCalls)
        defer { concurrentCalls -= 1 }

        try await Task.sleep(for: .milliseconds(25))
        guard !results.isEmpty else { return "" }
        let result = results[min(nextResultIndex, results.count - 1)]
        nextResultIndex += 1
        return result
    }

    func statistics() -> (callCount: Int, maximumConcurrentCalls: Int) {
        (callCount, maximumConcurrentCalls)
    }
}
