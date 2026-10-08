import AppKit
import SwiftData
import XCTest
@testable import Cliplet

@MainActor
final class ClipboardBatchDeletionTests: XCTestCase {
    func testMixedSelectionCreatesConfirmationWithoutDeletingOrCopying() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let text = try fixture.store.ingestText("要删除的文本")
        let image = try fixture.store.ingestImage(pngData())
        try fixture.store.setFavorite(true, for: image)
        fixture.viewModel.prepareToShow()

        let pasteboardChangeCount = fixture.pasteboard.changeCount
        fixture.viewModel.beginBatchDeletion(selecting: text.id)
        fixture.viewModel.toggleDeletionSelection(for: image.id)
        let request = try XCTUnwrap(fixture.viewModel.makeBatchDeletionRequest())

        XCTAssertEqual(request.itemIDs, [text.id, image.id])
        XCTAssertEqual(request.favoriteCount, 1)
        XCTAssertEqual(fixture.store.items.count, 2)
        XCTAssertEqual(fixture.pasteboard.changeCount, pasteboardChangeCount)

        fixture.viewModel.toggleDeletionSelection(for: text.id)
        XCTAssertEqual(fixture.viewModel.selectedDeletionItemIDs, [image.id])
        fixture.viewModel.toggleDeletionSelection(for: image.id)
        XCTAssertNil(fixture.viewModel.makeBatchDeletionRequest())
    }

    func testSelectAllOnlyIncludesCurrentResultsAndFiltersClearSelection() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let first = try fixture.store.ingestText("清理：第一条")
        let second = try fixture.store.ingestText("清理：第二条")
        let kept = try fixture.store.ingestText("保留的记录")
        let image = try fixture.store.ingestImage(pngData())
        try fixture.store.setFavorite(true, for: first)
        let tag = try fixture.store.createTag(name: "待整理")
        try fixture.store.assign(tag, to: first)
        fixture.viewModel.prepareToShow()

        fixture.viewModel.searchText = "清理"
        fixture.viewModel.beginBatchDeletion()
        fixture.viewModel.toggleSelectAllForDeletion()
        XCTAssertEqual(fixture.viewModel.selectedDeletionItemIDs, [first.id, second.id])
        XCTAssertTrue(fixture.viewModel.areAllItemsSelectedForDeletion)
        fixture.viewModel.toggleSelectAllForDeletion()
        XCTAssertTrue(fixture.viewModel.selectedDeletionItemIDs.isEmpty)

        fixture.viewModel.toggleSelectAllForDeletion()
        fixture.viewModel.searchText = ""
        XCTAssertTrue(fixture.viewModel.selectedDeletionItemIDs.isEmpty)
        fixture.viewModel.toggleSelectAllForDeletion()
        fixture.viewModel.selectedContentFilter = .image
        XCTAssertTrue(fixture.viewModel.selectedDeletionItemIDs.isEmpty)
        fixture.viewModel.toggleSelectAllForDeletion()
        XCTAssertEqual(fixture.viewModel.selectedDeletionItemIDs, [image.id])

        fixture.viewModel.selectedContentFilter = .all
        fixture.viewModel.toggleSelectAllForDeletion()
        fixture.viewModel.selectedSection = .favorites
        XCTAssertTrue(fixture.viewModel.selectedDeletionItemIDs.isEmpty)
        fixture.viewModel.toggleSelectAllForDeletion()
        XCTAssertEqual(fixture.viewModel.selectedDeletionItemIDs, [first.id])

        fixture.viewModel.selectedTagID = tag.id
        XCTAssertTrue(fixture.viewModel.selectedDeletionItemIDs.isEmpty)
        fixture.viewModel.toggleSelectAllForDeletion()
        fixture.viewModel.searchText = "没有匹配的内容"
        fixture.viewModel.toggleSelectAllForDeletion()
        XCTAssertTrue(fixture.viewModel.selectedDeletionItemIDs.isEmpty)
        XCTAssertFalse(fixture.viewModel.areAllItemsSelectedForDeletion)
        XCTAssertNil(fixture.viewModel.makeBatchDeletionRequest())
        XCTAssertTrue(fixture.store.items.contains { $0.id == kept.id })
    }

    func testConfirmationDeletesOnlyItsSnapshotAndRefreshesSelection() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let text = try fixture.store.ingestText("清理文本")
        let image = try fixture.store.ingestImage(pngData())
        let deletedIDs: Set<UUID> = [text.id, image.id]
        try fixture.store.setFavorite(true, for: text)
        let imageURL = try XCTUnwrap(fixture.store.imageURL(for: image))
        let thumbnailURL = try XCTUnwrap(fixture.store.thumbnailURL(for: image))
        fixture.viewModel.prepareToShow()
        fixture.viewModel.beginBatchDeletion()
        fixture.viewModel.toggleSelectAllForDeletion()
        let request = try XCTUnwrap(fixture.viewModel.makeBatchDeletionRequest())

        fixture.pasteboard.clearContents()
        fixture.pasteboard.setString("确认期间新复制的内容", forType: .string)
        fixture.monitor.pollNow()
        let newItem = try XCTUnwrap(fixture.viewModel.items.first { !deletedIDs.contains($0.id) })
        let newID = newItem.id
        XCTAssertEqual(fixture.viewModel.selectedDeletionItemIDs, deletedIDs)
        XCTAssertFalse(fixture.viewModel.areAllItemsSelectedForDeletion)
        // Even a later selection change must not enlarge the confirmed set.
        fixture.viewModel.toggleDeletionSelection(for: newID)
        fixture.viewModel.selectedItemID = text.id

        XCTAssertTrue(fixture.viewModel.confirmBatchDeletion(request))
        XCTAssertEqual(fixture.store.items.map(\.id), [newID])
        XCTAssertEqual(fixture.viewModel.items.map(\.id), [newID])
        XCTAssertEqual(fixture.viewModel.selectedItemID, newID)
        XCTAssertFalse(fixture.viewModel.isBatchDeleteMode)
        XCTAssertTrue(fixture.viewModel.selectedDeletionItemIDs.isEmpty)
        XCTAssertEqual(fixture.viewModel.toastMessage, "已删除 2 条记录")
        XCTAssertFalse(FileManager.default.fileExists(atPath: imageURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: thumbnailURL.path))
    }

    func testCancelAndDismissPreventPendingDeletion() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let item = try fixture.store.ingestText("取消后保留")
        fixture.viewModel.prepareToShow()
        fixture.viewModel.beginBatchDeletion(selecting: item.id)
        let request = try XCTUnwrap(fixture.viewModel.makeBatchDeletionRequest())

        fixture.viewModel.endBatchDeletion()
        XCTAssertFalse(fixture.viewModel.confirmBatchDeletion(request))
        XCTAssertEqual(fixture.store.items.count, 1)

        fixture.viewModel.beginBatchDeletion(selecting: item.id)
        fixture.viewModel.finishDismissing()
        XCTAssertFalse(fixture.viewModel.isBatchDeleteMode)
        XCTAssertTrue(fixture.viewModel.selectedDeletionItemIDs.isEmpty)
        XCTAssertFalse(fixture.viewModel.confirmBatchDeletion(request))
        XCTAssertEqual(fixture.store.items.count, 1)
    }

    func testSelectionPrunesRemovedItemsAndRejectsStaleFilteredRequest() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let first = try fixture.store.ingestText("清理第一条")
        let second = try fixture.store.ingestText("保留第二条")
        let secondID = second.id
        fixture.viewModel.prepareToShow()
        fixture.viewModel.beginBatchDeletion()
        fixture.viewModel.toggleSelectAllForDeletion()
        let request = try XCTUnwrap(fixture.viewModel.makeBatchDeletionRequest())

        fixture.viewModel.delete(first)
        XCTAssertEqual(fixture.viewModel.selectedDeletionItemIDs, [secondID])
        fixture.viewModel.searchText = "没有结果"
        XCTAssertFalse(fixture.viewModel.confirmBatchDeletion(request))
        XCTAssertEqual(fixture.store.items.map(\.id), [secondID])
    }

    private func makeFixture() throws -> BatchDeletionFixture {
        let schema = Schema([ClipboardItem.self, ClipTag.self, AppSettings.self])
        let configuration = ModelConfiguration(
            "ClipboardBatchDeletionTests",
            schema: schema,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(for: schema, configurations: configuration)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardBatchDeletionTests-\(UUID().uuidString)")
        let store = try ClipboardStore(modelContainer: container, imagesDirectory: directory)
        try store.updateSettings(automaticImageTextRecognition: false)
        let pasteboard = NSPasteboard(name: .init("ClipboardBatchDeletionTests-\(UUID().uuidString)"))
        let monitor = ClipboardMonitor(pasteboard: pasteboard, pollingInterval: .seconds(3_600))
        let viewModel = ClipletViewModel(store: store, monitor: monitor)
        return BatchDeletionFixture(
            store: store,
            viewModel: viewModel,
            pasteboard: pasteboard,
            monitor: monitor,
            directory: directory
        )
    }

    private func pngData() throws -> Data {
        try XCTUnwrap(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        ))
    }
}

@MainActor
private struct BatchDeletionFixture {
    let store: ClipboardStore
    let viewModel: ClipletViewModel
    let pasteboard: NSPasteboard
    let monitor: ClipboardMonitor
    let directory: URL

    func cleanup() {
        viewModel.shutdown()
        pasteboard.releaseGlobally()
        try? FileManager.default.removeItem(at: directory)
    }
}
