import AppKit
import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import Cliplet

@MainActor
final class ClipboardStoreTests: XCTestCase {
    func testDefaultsAndTextDeduplication() throws {
        var now = Date(timeIntervalSince1970: 1_000)
        let fixture = try makeStore(now: { now })
        defer { fixture.cleanup() }

        XCTAssertEqual(fixture.store.settings.historyLimit, 500)
        XCTAssertEqual(fixture.store.settings.retentionDays, 7)
        XCTAssertEqual(
            fixture.store.settings.appearanceModeRawValue,
            NimclipAppearanceMode.dark.rawValue
        )
        XCTAssertFalse(fixture.store.settings.hasExplicitAppearanceSelection)

        let original = try fixture.store.ingestText(
            "Nimclip",
            sourceAppBundleIdentifier: "com.example.first",
            sourceAppName: "First"
        )
        now.addTimeInterval(60)
        let duplicate = try fixture.store.ingestText(
            "Nimclip",
            sourceAppBundleIdentifier: "com.example.second",
            sourceAppName: "Second"
        )

        XCTAssertEqual(original.id, duplicate.id)
        XCTAssertEqual(fixture.store.items.count, 1)
        XCTAssertEqual(duplicate.sourceAppName, "Second")
        XCTAssertEqual(duplicate.updatedAt, now)
    }

    func testSystemAppearanceResolutionUsesTheCurrentMacAppearance() throws {
        XCTAssertEqual(
            NimclipAppearanceMode.resolvedSystemMode(
                from: try XCTUnwrap(NSAppearance(named: .aqua))
            ),
            .light
        )
        XCTAssertEqual(
            NimclipAppearanceMode.resolvedSystemMode(
                from: try XCTUnwrap(NSAppearance(named: .darkAqua))
            ),
            .dark
        )
    }

    func testUnselectedAppearanceTracksStartupSystemUntilUserChooses() throws {
        let unselected = AppSettings(
            appearanceMode: .dark,
            hasExplicitAppearanceSelection: false
        )
        let followsSystem = try makeStore(
            preloadedSettings: unselected,
            initialAppearanceMode: .light
        )
        defer { followsSystem.cleanup() }

        XCTAssertEqual(
            followsSystem.store.settings.appearanceModeRawValue,
            NimclipAppearanceMode.light.rawValue
        )
        XCTAssertFalse(followsSystem.store.settings.hasExplicitAppearanceSelection)

        try followsSystem.store.updateSettings(appearanceMode: .dark)
        XCTAssertTrue(followsSystem.store.settings.hasExplicitAppearanceSelection)

        let explicit = AppSettings(
            appearanceMode: .dark,
            hasExplicitAppearanceSelection: true
        )
        let keepsChoice = try makeStore(
            preloadedSettings: explicit,
            initialAppearanceMode: .light
        )
        defer { keepsChoice.cleanup() }

        XCTAssertEqual(
            keepsChoice.store.settings.appearanceModeRawValue,
            NimclipAppearanceMode.dark.rawValue
        )
        XCTAssertTrue(keepsChoice.store.settings.hasExplicitAppearanceSelection)
    }

    func testSamePlainTextWithDifferentFormattingCreatesDistinctHistoryItems() throws {
        var now = Date(timeIntervalSince1970: 2_000)
        let fixture = try makeStore(now: { now })
        defer { fixture.cleanup() }

        let boldArchive = formattedTextArchive(
            text: "Same text",
            html: "<p><strong>Same text</strong></p>"
        )
        let italicArchive = formattedTextArchive(
            text: "Same text",
            html: "<p><em>Same text</em></p>"
        )
        let bold = try fixture.store.ingestText(
            "Same text",
            archive: boldArchive,
            sourceAppName: "Pages"
        )
        now.addTimeInterval(30)
        let italic = try fixture.store.ingestText(
            "Same text",
            archive: italicArchive,
            sourceAppName: "Notes"
        )

        XCTAssertNotEqual(bold.id, italic.id)
        XCTAssertNotEqual(bold.contentHash, italic.contentHash)
        XCTAssertEqual(fixture.store.items.count, 2)
        XCTAssertEqual(fixture.store.pasteboardArchive(for: bold), boldArchive)
        XCTAssertEqual(fixture.store.pasteboardArchive(for: italic), italicArchive)

        now.addTimeInterval(30)
        let duplicateBold = try fixture.store.ingestText(
            "Same text",
            archive: boldArchive,
            sourceAppName: "TextEdit"
        )

        XCTAssertEqual(duplicateBold.id, bold.id)
        XCTAssertEqual(duplicateBold.updatedAt, now)
        XCTAssertEqual(duplicateBold.sourceAppName, "TextEdit")
        XCTAssertEqual(fixture.store.items.count, 2)
    }

    func testRepresentationOrderDoesNotDefeatFormattedContentDeduplication() throws {
        let fixture = try makeStore()
        defer { fixture.cleanup() }

        let archive = formattedTextArchive(
            text: "Stable order",
            html: "<strong>Stable order</strong>"
        )
        let reorderedArchive = ClipboardPasteboardArchive(
            items: archive.items.map {
                .init(representations: Array($0.representations.reversed()))
            }
        )

        let first = try fixture.store.ingestText("Stable order", archive: archive)
        let duplicate = try fixture.store.ingestText(
            "Stable order",
            archive: reorderedArchive
        )

        XCTAssertEqual(first.id, duplicate.id)
        XCTAssertEqual(fixture.store.items.count, 1)
        XCTAssertEqual(fixture.store.pasteboardArchive(for: duplicate), reorderedArchive)
    }

    func testLegacyTextWithoutArchiveFallsBackToPlainText() throws {
        let fixture = try makeStore()
        defer { fixture.cleanup() }

        let legacyItem = try fixture.store.ingestText(
            "Legacy plain text",
            sourceAppName: "Older Nimclip"
        )
        XCTAssertNil(fixture.store.pasteboardArchive(for: legacyItem))

        let pasteboard = NSPasteboard(
            name: .init("ClipletTests.legacy-fallback.\(UUID().uuidString)")
        )
        let coordinator = PasteCoordinator(pasteboard: pasteboard)
        let payload: ClipboardPastePayload
        if let archive = fixture.store.pasteboardArchive(for: legacyItem) {
            payload = .archive(archive)
        } else {
            payload = .text(try XCTUnwrap(legacyItem.text))
        }

        try coordinator.copy(payload)

        XCTAssertEqual(pasteboard.string(forType: .string), "Legacy plain text")
        XCTAssertNil(pasteboard.data(forType: .html))
        XCTAssertNil(pasteboard.data(forType: .rtf))
        XCTAssertTrue(ClipletPasteboardMarker.isPresent(on: pasteboard))
    }

    func testFormattedArchivePersistsWhenDiskStoreIsReopened() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipletDiskTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appendingPathComponent("history.store")
        let archive = formattedTextArchive(
            text: "Persistent formatting",
            html: "<p><strong>Persistent formatting</strong></p>"
        )
        let itemID = try writeArchive(archive, storeURL: storeURL, directory: directory)
        let restoredArchive = try readArchive(
            itemID: itemID,
            storeURL: storeURL,
            directory: directory
        )

        XCTAssertEqual(restoredArchive, archive)
    }

    func testSearchFavoritesAndTags() throws {
        let fixture = try makeStore()
        defer { fixture.cleanup() }

        let note = try fixture.store.ingestText("Release checklist", sourceAppName: "Notes")
        _ = try fixture.store.ingestText("Unrelated content", sourceAppName: "Safari")
        let work = try fixture.store.createTag(name: "工作", colorHex: "3B82F6")
        try fixture.store.assign(work, to: note)
        try fixture.store.setFavorite(true, for: note)

        XCTAssertEqual(fixture.store.filteredItems(searchText: "release").map(\.id), [note.id])
        XCTAssertEqual(fixture.store.filteredItems(searchText: "工作").map(\.id), [note.id])
        XCTAssertEqual(fixture.store.filteredItems(favoritesOnly: true).map(\.id), [note.id])
        XCTAssertEqual(fixture.store.filteredItems(tag: work).map(\.id), [note.id])
    }

    func testRetentionExpiresOnlyUnfavoritedItems() throws {
        var now = Date(timeIntervalSince1970: 10_000)
        let fixture = try makeStore(now: { now })
        defer { fixture.cleanup() }

        let expired = try fixture.store.ingestText("old")
        let protected = try fixture.store.ingestText("favorite")
        try fixture.store.setFavorite(true, for: protected)

        now.addTimeInterval(31 * 24 * 60 * 60)
        try fixture.store.enforceRetention()

        XCTAssertFalse(fixture.store.items.contains { $0.id == expired.id })
        XCTAssertTrue(fixture.store.items.contains { $0.id == protected.id })
    }

    func testImagePersistsTypeAndRemovesFilesOnDelete() throws {
        let fixture = try makeStore()
        defer { fixture.cleanup() }

        let pngData = try XCTUnwrap(
            Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")
        )
        let item = try fixture.store.ingestImage(
            pngData,
            typeIdentifier: UTType.png.identifier,
            sourceAppName: "Preview"
        )
        let originalURL = try XCTUnwrap(fixture.store.imageURL(for: item))
        let thumbnailURL = try XCTUnwrap(fixture.store.thumbnailURL(for: item))

        XCTAssertEqual(item.imageTypeIdentifier, UTType.png.identifier)
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: thumbnailURL.path))

        try fixture.store.delete(item)
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: thumbnailURL.path))
    }

    func testOversizedImageIsRejectedBeforeDecoding() throws {
        let fixture = try makeStore()
        defer { fixture.cleanup() }

        let data = Data(count: ClipboardStore.maximumImageBytes + 1)
        XCTAssertThrowsError(try fixture.store.ingestImage(data)) { error in
            guard case ClipboardStoreError.imageTooLarge = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertTrue(fixture.store.items.isEmpty)
    }

    func testSettingsAcceptExactValuesAndClampToSupportedRanges() throws {
        let fixture = try makeStore()
        defer { fixture.cleanup() }

        try fixture.store.updateSettings(
            historyLimit: 123,
            retentionDays: 42,
            appearanceMode: .light,
            language: .english
        )
        XCTAssertEqual(fixture.store.settings.historyLimit, 123)
        XCTAssertEqual(fixture.store.settings.retentionDays, 42)
        XCTAssertEqual(
            fixture.store.settings.appearanceModeRawValue,
            NimclipAppearanceMode.light.rawValue
        )
        XCTAssertTrue(fixture.store.settings.hasExplicitAppearanceSelection)
        XCTAssertEqual(
            fixture.store.settings.languageRawValue,
            NimclipLanguage.english.rawValue
        )

        try fixture.store.updateSettings(historyLimit: 1, retentionDays: 999)
        XCTAssertEqual(fixture.store.settings.historyLimit, ClipboardStore.minimumHistoryLimit)
        XCTAssertEqual(fixture.store.settings.retentionDays, ClipboardStore.maximumRetentionDays)
    }

    func testAppearanceModePersistsWhenStoreIsReopened() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipletAppearanceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appendingPathComponent("appearance.store")
        do {
            let store = try makeDiskStore(storeURL: storeURL, directory: directory)
            try store.updateSettings(appearanceMode: .light)
        }

        let reopenedStore = try makeDiskStore(storeURL: storeURL, directory: directory)
        XCTAssertEqual(
            reopenedStore.settings.appearanceModeRawValue,
            NimclipAppearanceMode.light.rawValue
        )
        XCTAssertTrue(reopenedStore.settings.hasExplicitAppearanceSelection)
    }

    func testLanguagePersistsWhenStoreIsReopened() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipletLanguageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appendingPathComponent("language.store")
        do {
            let store = try makeDiskStore(storeURL: storeURL, directory: directory)
            try store.updateSettings(language: .english)
        }

        let reopenedStore = try makeDiskStore(storeURL: storeURL, directory: directory)
        XCTAssertEqual(
            reopenedStore.settings.languageRawValue,
            NimclipLanguage.english.rawValue
        )
    }

    func testUntouchedLegacyDefaultMigratesWithoutOverwritingAUserChoice() throws {
        let createdAt = Date(timeIntervalSince1970: 1_000)
        let untouched = AppSettings(
            retentionDays: AppSettings.legacyDefaultRetentionDays,
            createdAt: createdAt,
            updatedAt: createdAt
        )
        let migratedStore = try makeStore(preloadedSettings: untouched)
        defer { migratedStore.cleanup() }

        XCTAssertEqual(migratedStore.store.settings.retentionDays, 7)

        let customized = AppSettings(
            retentionDays: AppSettings.legacyDefaultRetentionDays,
            createdAt: createdAt,
            updatedAt: createdAt.addingTimeInterval(60)
        )
        let preservedStore = try makeStore(preloadedSettings: customized)
        defer { preservedStore.cleanup() }

        XCTAssertEqual(preservedStore.store.settings.retentionDays, 30)
    }

    private func makeStore(
        now: @escaping () -> Date = Date.init,
        preloadedSettings: AppSettings? = nil,
        initialAppearanceMode: NimclipAppearanceMode = .dark
    ) throws -> StoreFixture {
        let schema = Schema([ClipboardItem.self, ClipTag.self, AppSettings.self])
        let configuration = ModelConfiguration(
            "ClipletTests",
            schema: schema,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(for: schema, configurations: configuration)
        if let preloadedSettings {
            let context = ModelContext(container)
            context.insert(preloadedSettings)
            try context.save()
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipletTests-\(UUID().uuidString)", isDirectory: true)
        let store = try ClipboardStore(
            modelContainer: container,
            imagesDirectory: directory,
            initialAppearanceMode: initialAppearanceMode,
            now: now
        )
        return StoreFixture(store: store, directory: directory)
    }

    private func formattedTextArchive(
        text: String,
        html: String
    ) -> ClipboardPasteboardArchive {
        ClipboardPasteboardArchive(
            items: [
                .init(
                    representations: [
                        .init(
                            typeIdentifier: NSPasteboard.PasteboardType.string.rawValue,
                            data: Data(text.utf8)
                        ),
                        .init(
                            typeIdentifier: NSPasteboard.PasteboardType.html.rawValue,
                            data: Data(html.utf8)
                        )
                    ]
                )
            ]
        )
    }

    private func writeArchive(
        _ archive: ClipboardPasteboardArchive,
        storeURL: URL,
        directory: URL
    ) throws -> UUID {
        let store = try makeDiskStore(storeURL: storeURL, directory: directory)
        return try store.ingestText("Persistent formatting", archive: archive).id
    }

    private func readArchive(
        itemID: UUID,
        storeURL: URL,
        directory: URL
    ) throws -> ClipboardPasteboardArchive {
        let store = try makeDiskStore(storeURL: storeURL, directory: directory)
        let item = try XCTUnwrap(store.items.first { $0.id == itemID })
        return try XCTUnwrap(store.pasteboardArchive(for: item))
    }

    private func makeDiskStore(
        storeURL: URL,
        directory: URL,
        initialAppearanceMode: NimclipAppearanceMode = .dark
    ) throws -> ClipboardStore {
        let schema = Schema([ClipboardItem.self, ClipTag.self, AppSettings.self])
        let configuration = ModelConfiguration(
            "ClipletDiskTests",
            schema: schema,
            url: storeURL
        )
        let container = try ModelContainer(for: schema, configurations: configuration)
        return try ClipboardStore(
            modelContainer: container,
            imagesDirectory: directory.appendingPathComponent("images", isDirectory: true),
            initialAppearanceMode: initialAppearanceMode
        )
    }
}

@MainActor
private struct StoreFixture {
    let store: ClipboardStore
    let directory: URL

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }
}
