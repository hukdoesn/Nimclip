import AppKit
import Carbon.HIToolbox
import UniformTypeIdentifiers
import XCTest
@testable import Cliplet

@MainActor
final class ClipboardSystemTests: XCTestCase {
    func testGlobalHotKeyTriggersWhenMainKeyIsPressedBeforeModifiers() {
        let shortcut = GlobalHotKeyShortcut.defaultPaste
        var latch = GlobalHotKeyChordLatch()

        XCTAssertFalse(
            latch.update(
                isPressed: shortcut.matchesPhysicalState(
                    keyIsPressed: true,
                    activeModifiers: 0
                )
            )
        )
        XCTAssertFalse(
            latch.update(
                isPressed: shortcut.matchesPhysicalState(
                    keyIsPressed: true,
                    activeModifiers: UInt32(shiftKey)
                )
            )
        )
        XCTAssertTrue(
            latch.update(
                isPressed: shortcut.matchesPhysicalState(
                    keyIsPressed: true,
                    activeModifiers: UInt32(shiftKey | cmdKey)
                )
            )
        )
    }

    func testGlobalHotKeyOnlyTriggersOnceUntilAnyRequiredKeyIsReleased() {
        let shortcut = GlobalHotKeyShortcut.defaultPaste
        let allModifiers = UInt32(shiftKey | cmdKey)
        var latch = GlobalHotKeyChordLatch()

        XCTAssertTrue(
            latch.update(
                isPressed: shortcut.matchesPhysicalState(
                    keyIsPressed: true,
                    activeModifiers: allModifiers
                )
            )
        )
        XCTAssertFalse(
            latch.update(
                isPressed: shortcut.matchesPhysicalState(
                    keyIsPressed: true,
                    activeModifiers: allModifiers
                )
            )
        )
        XCTAssertFalse(latch.update(isPressed: false))
        XCTAssertTrue(
            latch.update(
                isPressed: shortcut.matchesPhysicalState(
                    keyIsPressed: true,
                    activeModifiers: allModifiers
                )
            )
        )
    }

    func testCarbonAndPhysicalHotKeyPathsDoNotTriggerTwice() {
        var latch = GlobalHotKeyChordLatch()

        XCTAssertTrue(latch.acceptRegisteredHotKeyEvent())
        XCTAssertFalse(latch.update(isPressed: true))
        XCTAssertFalse(latch.acceptRegisteredHotKeyEvent())
        XCTAssertFalse(latch.update(isPressed: false))
        XCTAssertTrue(latch.acceptRegisteredHotKeyEvent())
    }

    func testMissedPhysicalPressStillEmitsReleaseAfterCarbonEvent() {
        var transition = GlobalHotKeyPhysicalTransitionState()

        transition.registeredHotKeyEventReceived()

        XCTAssertEqual(transition.update(isPressed: false), false)
        XCTAssertNil(transition.update(isPressed: false))
        XCTAssertEqual(transition.update(isPressed: true), true)
        XCTAssertEqual(transition.update(isPressed: false), false)
    }

    func testRepeatedQuickCarbonHotKeysEachReceiveASyntheticRelease() {
        var transition = GlobalHotKeyPhysicalTransitionState()
        var latch = GlobalHotKeyChordLatch()

        for _ in 0..<3 {
            XCTAssertTrue(latch.acceptRegisteredHotKeyEvent())
            transition.registeredHotKeyEventReceived()
            XCTAssertEqual(transition.update(isPressed: false), false)
            XCTAssertFalse(latch.update(isPressed: false))
        }
    }

    func testCustomizedGlobalHotKeyAlsoIgnoresPressOrder() {
        let shortcut = GlobalHotKeyShortcut(
            keyCode: UInt32(kVK_ANSI_Q),
            modifiers: UInt32(optionKey | controlKey)
        )
        var latch = GlobalHotKeyChordLatch()

        XCTAssertFalse(
            latch.update(
                isPressed: shortcut.matchesPhysicalState(
                    keyIsPressed: true,
                    activeModifiers: 0
                )
            )
        )
        XCTAssertFalse(
            latch.update(
                isPressed: shortcut.matchesPhysicalState(
                    keyIsPressed: true,
                    activeModifiers: UInt32(optionKey)
                )
            )
        )
        XCTAssertTrue(
            latch.update(
                isPressed: shortcut.matchesPhysicalState(
                    keyIsPressed: true,
                    activeModifiers: UInt32(optionKey | controlKey)
                )
            )
        )
    }

    func testOptionPreviewDetectionAllowsOtherModifierFlags() {
        XCTAssertTrue(
            ModifierKeyMonitor.optionIsPressed(in: [.option, .capsLock])
        )
        XCTAssertFalse(
            ModifierKeyMonitor.optionIsPressed(in: [.command, .shift])
        )
    }

    func testMonitorCapturesPlainTextAndSourceMetadata() throws {
        let pasteboard = NSPasteboard(name: .init("ClipletTests.capture.\(UUID().uuidString)"))
        let monitor = ClipboardMonitor(pasteboard: pasteboard)
        var received: ClipboardCapture?
        monitor.onCapture = { received = $0 }

        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString("captured text", forType: .string))
        monitor.pollNow()

        guard case let .text(text, archive) = try XCTUnwrap(received).content else {
            return XCTFail("Expected text capture")
        }
        XCTAssertEqual(text, "captured text")
        XCTAssertNil(archive, "Pure text should keep the legacy lightweight storage path")
    }

    func testMonitorPrefersImageWhenScreenshotAlsoProvidesText() throws {
        let pasteboard = NSPasteboard(
            name: .init("ClipletTests.screenshot-with-text.\(UUID().uuidString)")
        )
        let monitor = ClipboardMonitor(pasteboard: pasteboard)
        var received: ClipboardCapture?
        monitor.onCapture = { received = $0 }

        let pngData = try XCTUnwrap(
            Data(
                base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
            )
        )
        let sourceItem = NSPasteboardItem()
        XCTAssertTrue(sourceItem.setString("Screenshot", forType: .string))
        XCTAssertTrue(sourceItem.setData(pngData, forType: .png))
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([sourceItem]))

        monitor.pollNow()

        guard case let .image(data, typeIdentifier, archive) = try XCTUnwrap(received).content else {
            return XCTFail("Expected screenshot image capture")
        }
        XCTAssertEqual(data, pngData)
        XCTAssertEqual(typeIdentifier, NSPasteboard.PasteboardType.png.rawValue)
        XCTAssertNil(archive, "Image history stores only the selected original representation")
    }

    func testMonitorKeepsPrimaryScreenshotWhenAuxiliaryRepresentationsAreTooLarge() throws {
        let pasteboard = NSPasteboard(
            name: .init("ClipletTests.large-screenshot-archive.\(UUID().uuidString)")
        )
        let monitor = ClipboardMonitor(pasteboard: pasteboard)
        var received: ClipboardCapture?
        monitor.onCapture = { received = $0 }

        let pngData = try XCTUnwrap(
            Data(
                base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
            )
        )
        let sourceItem = NSPasteboardItem()
        XCTAssertTrue(sourceItem.setData(pngData, forType: .png))
        XCTAssertTrue(
            sourceItem.setData(
                Data(count: ClipboardPasteboardArchive.maximumTotalDataBytes),
                forType: .init("com.nimclip.tests.oversized-screenshot-metadata")
            )
        )
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([sourceItem]))

        monitor.pollNow()

        let capture = try XCTUnwrap(received)
        XCTAssertFalse(capture.didOmitRepresentations)
        guard case let .image(data, _, archive) = capture.content else {
            return XCTFail("Expected the complete primary screenshot to remain available")
        }
        XCTAssertEqual(data, pngData)
        XCTAssertNil(archive, "An incomplete auxiliary archive must not be persisted")
    }

    func testMonitorCapturesRichTextRepresentationsWithoutChangingBytes() throws {
        let pasteboard = NSPasteboard(
            name: .init("ClipletTests.rich-capture.\(UUID().uuidString)")
        )
        let monitor = ClipboardMonitor(pasteboard: pasteboard)
        var received: ClipboardCapture?
        monitor.onCapture = { received = $0 }

        let htmlData = Data(
            #"<meta charset="utf-8"><p style="color:#c00"><b>Nimclip</b></p>"#.utf8
        )
        let rtfData = Data(
            #"{\rtf1\ansi\deff0 {\fonttbl {\f0 Helvetica;}}\f0\b Nimclip\b0}"#.utf8
        )
        let sourceItem = NSPasteboardItem()
        XCTAssertTrue(sourceItem.setString("Nimclip", forType: .string))
        XCTAssertTrue(sourceItem.setData(htmlData, forType: .html))
        XCTAssertTrue(sourceItem.setData(rtfData, forType: .rtf))
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([sourceItem]))

        monitor.pollNow()

        guard case let .text(text, capturedArchive) = try XCTUnwrap(received).content else {
            return XCTFail("Expected text capture")
        }
        XCTAssertEqual(text, "Nimclip")
        let archive = try XCTUnwrap(capturedArchive)
        XCTAssertEqual(archive.items.count, 1)
        let archivedItem = try XCTUnwrap(archive.items.first)
        let committedItem = try XCTUnwrap(pasteboard.pasteboardItems?.first)

        for type in [
            NSPasteboard.PasteboardType.string,
            NSPasteboard.PasteboardType.html,
            NSPasteboard.PasteboardType.rtf
        ] {
            let representation = try XCTUnwrap(
                archivedItem.representations.first {
                    $0.typeIdentifier == type.rawValue
                }
            )
            XCTAssertEqual(representation.data, committedItem.data(forType: type))
        }
        XCTAssertEqual(committedItem.data(forType: .html), htmlData)
        XCTAssertEqual(committedItem.data(forType: .rtf), rtfData)
    }

    func testMonitorDerivesSearchTextWhenSourceOnlyProvidesRTF() throws {
        let pasteboard = NSPasteboard(
            name: .init("ClipletTests.rtf-only.\(UUID().uuidString)")
        )
        let monitor = ClipboardMonitor(pasteboard: pasteboard)
        var received: ClipboardCapture?
        monitor.onCapture = { received = $0 }

        let rtfData = Data(
            #"{\rtf1\ansi\deff0 {\fonttbl {\f0 Helvetica;}}\f0\b Only Rich\b0}"#.utf8
        )
        let sourceItem = NSPasteboardItem()
        XCTAssertTrue(sourceItem.setData(rtfData, forType: .rtf))
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([sourceItem]))

        monitor.pollNow()

        guard case let .text(displayText, archive) = try XCTUnwrap(received).content else {
            return XCTFail("Expected RTF-only content to be captured as searchable text")
        }
        XCTAssertTrue(displayText.contains("Only Rich"))
        let representation = try XCTUnwrap(
            archive?.items.first?.representations.first {
                $0.typeIdentifier == NSPasteboard.PasteboardType.rtf.rawValue
            }
        )
        XCTAssertEqual(representation.data, rtfData)
    }

    func testMonitorReportsWhenSomeRepresentationsExceedArchiveLimits() throws {
        let pasteboard = NSPasteboard(
            name: .init("ClipletTests.archive-limit.\(UUID().uuidString)")
        )
        let monitor = ClipboardMonitor(pasteboard: pasteboard)
        var received: ClipboardCapture?
        monitor.onCapture = { received = $0 }

        let sourceItem = NSPasteboardItem()
        XCTAssertTrue(sourceItem.setString("Still available", forType: .string))
        for index in 0..<ClipboardPasteboardArchive.maximumRepresentationCountPerItem {
            XCTAssertTrue(
                sourceItem.setData(
                    Data([UInt8(index)]),
                    forType: .init("com.nimclip.tests.format-\(index)")
                )
            )
        }
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([sourceItem]))

        monitor.pollNow()

        let capture = try XCTUnwrap(received)
        XCTAssertTrue(capture.didOmitRepresentations)
        guard case let .text(text, archive) = capture.content else {
            return XCTFail("Expected the usable text representation to remain available")
        }
        XCTAssertEqual(text, "Still available")
        XCTAssertNil(archive, "Incomplete archives must never be persisted or deduplicated")
    }

    func testPasteCoordinatorRestoresRichTextRepresentationsByteForByte() throws {
        let pasteboard = NSPasteboard(
            name: .init("ClipletTests.rich-paste.\(UUID().uuidString)")
        )
        let token = PasteboardSuppressionToken(rawValue: "rich-paste-test")
        let coordinator = PasteCoordinator(
            pasteboard: pasteboard,
            suppressionToken: token
        )
        let plainData = Data("Nimclip".utf8)
        let htmlData = Data("<p><strong>Nimclip</strong></p>".utf8)
        let rtfData = Data(#"{\rtf1\ansi\b Nimclip\b0}"#.utf8)
        let archive = ClipboardPasteboardArchive(
            items: [
                .init(
                    representations: [
                        .init(
                            typeIdentifier: NSPasteboard.PasteboardType.string.rawValue,
                            data: plainData
                        ),
                        .init(
                            typeIdentifier: NSPasteboard.PasteboardType.html.rawValue,
                            data: htmlData
                        ),
                        .init(
                            typeIdentifier: NSPasteboard.PasteboardType.rtf.rawValue,
                            data: rtfData
                        )
                    ]
                )
            ]
        )

        try coordinator.copy(.archive(archive))

        let items = try XCTUnwrap(pasteboard.pasteboardItems)
        XCTAssertEqual(items.count, 1)
        let restoredItem = try XCTUnwrap(items.first)
        XCTAssertEqual(restoredItem.data(forType: .string), plainData)
        XCTAssertEqual(restoredItem.data(forType: .html), htmlData)
        XCTAssertEqual(restoredItem.data(forType: .rtf), rtfData)
        XCTAssertTrue(ClipletPasteboardMarker.isPresent(on: pasteboard, token: token))

        let restoredTypes = Set(
            restoredItem.types
                .filter { $0 != ClipletPasteboardMarker.pasteboardType }
                .map(\.rawValue)
        )
        let expectedTypes = Set([
            NSPasteboard.PasteboardType.string.rawValue,
            NSPasteboard.PasteboardType.html.rawValue,
            NSPasteboard.PasteboardType.rtf.rawValue
        ])
        XCTAssertTrue(
            expectedTypes.isSubset(of: restoredTypes),
            "Restoring an archive must not drop an original representation"
        )
    }

    func testRichTextRoundTripPreservesMultipleItemsAndTheirOrder() throws {
        let sourcePasteboard = NSPasteboard(
            name: .init("ClipletTests.multi-source.\(UUID().uuidString)")
        )
        let monitor = ClipboardMonitor(pasteboard: sourcePasteboard)
        var received: ClipboardCapture?
        monitor.onCapture = { received = $0 }

        let firstItem = NSPasteboardItem()
        let firstHTML = Data("<b>First</b>".utf8)
        XCTAssertTrue(firstItem.setString("First", forType: .string))
        XCTAssertTrue(firstItem.setData(firstHTML, forType: .html))

        let secondItem = NSPasteboardItem()
        let secondRTF = Data(#"{\rtf1\ansi\i Second\i0}"#.utf8)
        XCTAssertTrue(secondItem.setString("Second", forType: .string))
        XCTAssertTrue(secondItem.setData(secondRTF, forType: .rtf))

        sourcePasteboard.clearContents()
        XCTAssertTrue(sourcePasteboard.writeObjects([firstItem, secondItem]))
        monitor.pollNow()

        guard case let .text(_, capturedArchive) = try XCTUnwrap(received).content else {
            return XCTFail("Expected text capture")
        }
        let archive = try XCTUnwrap(capturedArchive)
        XCTAssertEqual(archive.items.count, 2)

        let targetPasteboard = NSPasteboard(
            name: .init("ClipletTests.multi-target.\(UUID().uuidString)")
        )
        let coordinator = PasteCoordinator(pasteboard: targetPasteboard)
        try coordinator.copy(.archive(archive))

        let sourceItems = try XCTUnwrap(sourcePasteboard.pasteboardItems)
        let targetItems = try XCTUnwrap(targetPasteboard.pasteboardItems)
        guard sourceItems.count == 2, targetItems.count == 2 else {
            return XCTFail("Expected exactly two source and target pasteboard items")
        }

        XCTAssertEqual(targetItems[0].data(forType: .string), sourceItems[0].data(forType: .string))
        XCTAssertEqual(targetItems[0].data(forType: .html), sourceItems[0].data(forType: .html))
        XCTAssertEqual(targetItems[1].data(forType: .string), sourceItems[1].data(forType: .string))
        XCTAssertEqual(targetItems[1].data(forType: .rtf), sourceItems[1].data(forType: .rtf))
        XCTAssertNil(targetItems[0].data(forType: .rtf))
        XCTAssertNil(targetItems[1].data(forType: .html))
    }

    func testPasteCoordinatorMarksItsOwnWrites() throws {
        let pasteboard = NSPasteboard(name: .init("ClipletTests.paste.\(UUID().uuidString)"))
        let coordinator = PasteCoordinator(pasteboard: pasteboard)

        try coordinator.copy(.text("copy me"))

        XCTAssertEqual(pasteboard.string(forType: .string), "copy me")
        XCTAssertTrue(ClipletPasteboardMarker.isPresent(on: pasteboard))
    }

    func testMonitorIgnoresMarkedWrites() throws {
        let pasteboard = NSPasteboard(name: .init("ClipletTests.suppression.\(UUID().uuidString)"))
        let monitor = ClipboardMonitor(pasteboard: pasteboard)
        let coordinator = PasteCoordinator(pasteboard: pasteboard)
        var captureCount = 0
        monitor.onCapture = { _ in captureCount += 1 }

        try coordinator.copy(.text("internal"))
        monitor.pollNow()

        XCTAssertEqual(captureCount, 0)
    }
}
