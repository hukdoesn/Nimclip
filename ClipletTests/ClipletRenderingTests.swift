import AppKit
import Carbon.HIToolbox
import SwiftData
import SwiftUI
import XCTest
@testable import Cliplet

@MainActor
final class ClipletRenderingTests: XCTestCase {
    func testMenuBarViewRendersInLightAndDarkAppearances() throws {
        let fixture = try makeFixture()
        defer {
            fixture.viewModel.shutdown()
            try? FileManager.default.removeItem(at: fixture.directory)
        }

        try addPreviewContent(to: fixture.store)
        fixture.viewModel.prepareToShow()
        fixture.viewModel.dismissToast()

        for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
            fixture.viewModel.appearanceMode = appearanceName == .darkAqua ? .dark : .light
            fixture.viewModel.dismissToast()

            let menuData = try render(
                MenuBarRootView(viewModel: fixture.viewModel),
                size: NSSize(width: 440, height: 600),
                appearanceName: appearanceName,
                snapshotName: "menu-\(appearanceName.rawValue)"
            )
            XCTAssertGreaterThan(menuData.count, 20_000)

            let settingsData = try render(
                SettingsView(viewModel: fixture.viewModel),
                size: NSSize(width: 660, height: 520),
                appearanceName: appearanceName,
                snapshotName: "settings-\(appearanceName.rawValue)"
            )
            XCTAssertGreaterThan(settingsData.count, 20_000)
        }
    }

    func testExpandedTextImageAndAboutViewsRenderInLightAndDarkAppearances() throws {
        let fixture = try makeFixture()
        defer {
            fixture.viewModel.shutdown()
            try? FileManager.default.removeItem(at: fixture.directory)
        }

        let textItem = try fixture.store.ingestText(
            "完整内容预览保留换行。\n\n" + String(repeating: "Nimclip 会展示未截断的文本内容。\n", count: 18),
            sourceAppName: "备忘录"
        )
        try fixture.store.setFavorite(true, for: textItem)
        try fixture.store.setNote(
            "发布前再次核对这段收藏内容；备注不会进入粘贴结果。\n负责人：Nimclip 测试组",
            for: textItem
        )
        let imageItem = try fixture.store.ingestImage(
            try previewImageData(),
            sourceAppName: "预览"
        )
        fixture.viewModel.prepareToShow()

        for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
            let previewVisibleFrame = CGRect(x: 0, y: 0, width: 1_440, height: 900)
            let aboutData = try render(
                NimclipAboutView(),
                size: NSSize(width: 520, height: 443),
                appearanceName: appearanceName,
                snapshotName: "about-\(appearanceName.rawValue)"
            )
            XCTAssertGreaterThan(aboutData.count, 20_000)

            let contactData = try render(
                NimclipContactView(),
                size: NSSize(width: 320, height: 408),
                appearanceName: appearanceName,
                snapshotName: "contact-\(appearanceName.rawValue)"
            )
            XCTAssertGreaterThan(contactData.count, 30_000)

            let supportData = try render(
                NimclipSupportView(),
                size: NSSize(width: 470, height: 350),
                appearanceName: appearanceName,
                snapshotName: "support-\(appearanceName.rawValue)"
            )
            XCTAssertGreaterThan(supportData.count, 30_000)

            let textPreviewSize = ClipletPreviewPanelController.preferredSize(
                kind: .text,
                imageSize: nil,
                hasTags: false,
                visibleFrame: previewVisibleFrame,
                text: textItem.text,
                note: textItem.note
            )
            let textData = try render(
                ClipboardItemExpandedPreview(
                    item: textItem,
                    imageURL: nil,
                    thumbnailURL: nil,
                    referenceDate: fixture.viewModel.timestampReferenceDate,
                    previewSize: textPreviewSize
                ),
                size: textPreviewSize,
                appearanceName: appearanceName,
                snapshotName: "preview-text-\(appearanceName.rawValue)"
            )
            XCTAssertGreaterThan(textData.count, 20_000)

            let imagePreviewSize = ClipletPreviewPanelController.preferredSize(
                kind: .image,
                imageSize: CGSize(width: 480, height: 300),
                hasTags: false,
                visibleFrame: previewVisibleFrame
            )
            let imageData = try render(
                ClipboardItemExpandedPreview(
                    item: imageItem,
                    imageURL: fixture.store.imageURL(for: imageItem),
                    thumbnailURL: fixture.store.thumbnailURL(for: imageItem),
                    referenceDate: fixture.viewModel.timestampReferenceDate,
                    previewSize: imagePreviewSize
                ),
                size: imagePreviewSize,
                appearanceName: appearanceName,
                snapshotName: "preview-image-\(appearanceName.rawValue)"
            )
            XCTAssertGreaterThan(imageData.count, 20_000)

            let largePreviewSize = NSSize(width: 800, height: 600)
            let largeImageData = try render(
                ClipboardItemExpandedPreview(
                    item: imageItem,
                    imageURL: fixture.store.imageURL(for: imageItem),
                    thumbnailURL: fixture.store.thumbnailURL(for: imageItem),
                    referenceDate: fixture.viewModel.timestampReferenceDate,
                    previewSize: largePreviewSize
                ),
                size: largePreviewSize,
                appearanceName: appearanceName
            )
            XCTAssertGreaterThan(largeImageData.count, 40_000)
        }
    }

    func testImageTextSettingsRenderWithEnglishLocalization() throws {
        let fixture = try makeFixture()
        defer {
            fixture.viewModel.shutdown()
            try? FileManager.default.removeItem(at: fixture.directory)
        }

        _ = try fixture.store.ingestImage(try previewImageData())
        fixture.viewModel.language = .english
        fixture.viewModel.dismissToast()

        let settingsData = try render(
            NimclipImageTextSettingsSection(viewModel: fixture.viewModel)
                .environment(\.locale, fixture.viewModel.language.locale)
                .padding(20)
                .background(Color.clipletCanvas),
            size: NSSize(width: 560, height: 230),
            appearanceName: .aqua,
            snapshotName: "settings-image-text-english"
        )
        XCTAssertGreaterThan(settingsData.count, 20_000)
    }

    func testLargeHistoryListOnlyMaterializesReusableVisibleRows() throws {
        let schema = Schema([ClipboardItem.self, ClipTag.self, AppSettings.self])
        let configuration = ModelConfiguration(
            "ClipletLargeHistoryRenderingTests",
            schema: schema,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(for: schema, configurations: configuration)
        let seedContext = ModelContext(container)
        let referenceDate = Date(timeIntervalSince1970: 100_000)
        for index in 0..<500 {
            seedContext.insert(
                ClipboardItem(
                    kind: .text,
                    text: "历史记录 \(index)：用于验证大型列表滚动时的行复用。",
                    contentHash: "large-history-\(index)",
                    sourceAppBundleIdentifier: "com.apple.TextEdit",
                    sourceAppName: "TextEdit",
                    createdAt: referenceDate.addingTimeInterval(-Double(index)),
                    updatedAt: referenceDate.addingTimeInterval(-Double(index))
                )
            )
        }
        try seedContext.save()

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ClipletLargeHistoryRenderingTests-\(UUID().uuidString)",
                isDirectory: true
            )
        let store = try ClipboardStore(
            modelContainer: container,
            imagesDirectory: directory
        )
        let pasteboard = NSPasteboard(
            name: .init("ClipletLargeHistoryRenderingTests-\(UUID().uuidString)")
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
        var visibleRowIDs = Set<UUID>()
        var peakVisibleRowCount = 0
        let hostingView = NSHostingView(
            rootView: MenuBarRootView(
                viewModel: viewModel,
                onRowVisibilityChange: { itemID, isVisible in
                    if isVisible {
                        visibleRowIDs.insert(itemID)
                    } else {
                        visibleRowIDs.remove(itemID)
                    }
                    peakVisibleRowCount = max(
                        peakVisibleRowCount,
                        visibleRowIDs.count
                    )
                }
            )
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 440, height: 600)
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        let scrollView = try XCTUnwrap(
            firstSubview(of: NSScrollView.self, in: hostingView),
            "The history should be hosted in a native scroll view"
        )
        XCTAssertEqual(viewModel.items.count, 500)
        XCTAssertGreaterThan(visibleRowIDs.count, 0)
        XCTAssertLessThan(visibleRowIDs.count, 40)

        let viewportHeight = scrollView.contentView.bounds.height
        let contentHeight = scrollView.documentView?.bounds.height ?? viewportHeight
        let maximumOffset = max(0, contentHeight - viewportHeight)
        for fraction in stride(from: 0.1, through: 1.0, by: 0.1) {
            scrollView.contentView.scroll(
                to: NSPoint(x: 0, y: maximumOffset * fraction)
            )
            scrollView.reflectScrolledClipView(scrollView.contentView)
            hostingView.layoutSubtreeIfNeeded()
            hostingView.displayIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            XCTAssertLessThan(
                visibleRowIDs.count,
                40,
                "Only rows around the current viewport should stay visible"
            )
        }
        XCTAssertLessThan(
            peakVisibleRowCount,
            60,
            "Scrolling must not materialize the whole history at once"
        )
    }

    private func makeFixture() throws -> RenderingFixture {
        let schema = Schema([ClipboardItem.self, ClipTag.self, AppSettings.self])
        let configuration = ModelConfiguration(
            "ClipletRenderingTests",
            schema: schema,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(for: schema, configurations: configuration)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipletRenderingTests-\(UUID().uuidString)", isDirectory: true)
        let store = try ClipboardStore(modelContainer: container, imagesDirectory: directory)
        try store.updateSettings(
            hotKeyKeyCode: UInt32(kVK_ANSI_Q),
            hotKeyModifiers: UInt32(cmdKey | optionKey | controlKey)
        )
        let pasteboard = NSPasteboard(name: .init("ClipletRenderingTests-\(UUID().uuidString)"))
        let monitor = ClipboardMonitor(pasteboard: pasteboard, pollingInterval: .seconds(3_600))
        let viewModel = ClipletViewModel(store: store, monitor: monitor)
        return RenderingFixture(store: store, viewModel: viewModel, directory: directory)
    }

    private func addPreviewContent(to store: ClipboardStore) throws {
        let first = try store.ingestText(
            "设计稿已确认，准备整理本周发布内容与检查清单。",
            sourceAppName: "备忘录"
        )
        let work = try store.createTag(name: "工作", colorHex: "C96B4B")
        try store.assign(work, to: first)
        try store.setFavorite(true, for: first)

        _ = try store.ingestText(
            "https://developer.apple.com/design/human-interface-guidelines/",
            sourceAppName: "Safari"
        )
        _ = try store.ingestText("明天下午 3 点同步产品进度", sourceAppName: "信息")
        _ = try store.ingestText("npm run build", sourceAppName: "终端")
        _ = try store.ingestText("Nimclip 的列表时间不再显示秒数。", sourceAppName: "Xcode")
    }

    private func previewImageData() throws -> Data {
        let image = NSImage(size: NSSize(width: 480, height: 300))
        image.lockFocus()
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath.fill(NSRect(x: 0, y: 0, width: 480, height: 300))
        NSColor.labelColor.setFill()
        NSBezierPath(
            roundedRect: NSRect(x: 52, y: 48, width: 376, height: 204),
            xRadius: 24,
            yRadius: 24
        ).fill()
        image.unlockFocus()

        let tiffData = try XCTUnwrap(image.tiffRepresentation)
        let representation = try XCTUnwrap(NSBitmapImageRep(data: tiffData))
        return try XCTUnwrap(representation.representation(using: .png, properties: [:]))
    }

    private func render<Content: View>(
        _ view: Content,
        size: NSSize,
        appearanceName: NSAppearance.Name,
        snapshotName: String? = nil
    ) throws -> Data {
        let hostingView = NSHostingView(rootView: view)
        hostingView.appearance = NSAppearance(named: appearanceName)
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.layoutSubtreeIfNeeded()

        let bounds = hostingView.bounds
        let bitmap = try XCTUnwrap(hostingView.bitmapImageRepForCachingDisplay(in: bounds))
        hostingView.cacheDisplay(in: bounds, to: bitmap)
        XCTAssertEqual(bitmap.size.width, size.width)
        XCTAssertEqual(bitmap.size.height, size.height)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        if let snapshotName {
            let attachment = XCTAttachment(
                data: data,
                uniformTypeIdentifier: "public.png"
            )
            attachment.name = snapshotName
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        if let snapshotName,
           let outputPath = ProcessInfo.processInfo.environment["CLIPLET_RENDER_OUTPUT_DIR"] {
            let directory = URL(fileURLWithPath: outputPath, isDirectory: true)
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try data.write(
                to: directory.appendingPathComponent("\(snapshotName).png"),
                options: .atomic
            )
        }
        return data
    }

    private func firstSubview<ViewType: NSView>(
        of type: ViewType.Type,
        in root: NSView
    ) -> ViewType? {
        if let match = root as? ViewType {
            return match
        }
        for subview in root.subviews {
            if let match = firstSubview(of: type, in: subview) {
                return match
            }
        }
        return nil
    }

}

@MainActor
private struct RenderingFixture {
    let store: ClipboardStore
    let viewModel: ClipletViewModel
    let directory: URL
}
