import AppKit
import ImageIO
import SwiftUI

@MainActor
final class ClipletPreviewPanelController {
    private(set) var panel: NSPanel?
    private var hostingController: NSHostingController<ClipboardItemExpandedPreview>?
    private let imageSizeCache: NSCache<NSURL, NSValue> = {
        let cache = NSCache<NSURL, NSValue>()
        cache.countLimit = 256
        return cache
    }()
    private var pendingHideTask: Task<Void, Never>?
    private var isPointerInsidePreview = false
    private let hideDelay: Duration

    init(hideDelay: Duration = .milliseconds(600)) {
        self.hideDelay = hideDelay
    }

    func show(
        item: ClipboardItem,
        imageURL: URL?,
        thumbnailURL: URL?,
        referenceDate: Date,
        language: NimclipLanguage = .defaultLanguage,
        relativeTo sourceWindow: NSWindow?
    ) {
        pendingHideTask?.cancel()
        pendingHideTask = nil
        let screen = sourceWindow?.screen ?? NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1_440, height: 900)
        let imageSize = cachedImagePixelSize(at: imageURL)
            ?? cachedImagePixelSize(at: thumbnailURL)
        let previewSize = Self.preferredSize(
            kind: item.kind,
            imageSize: imageSize,
            hasTags: !item.tags.isEmpty,
            visibleFrame: visibleFrame,
            text: item.text
        )

        let preview = ClipboardItemExpandedPreview(
            item: item,
            imageURL: imageURL,
            thumbnailURL: thumbnailURL,
            referenceDate: referenceDate,
            language: language,
            previewSize: previewSize,
            onHoverChange: { [weak self] isInside in
                self?.setPreviewPointerInside(isInside)
            }
        )
        let panel = panel ?? makePanel(size: previewSize)
        self.panel = panel

        if let hostingController {
            hostingController.rootView = preview
            if panel.contentViewController !== hostingController {
                panel.contentViewController = hostingController
            }
        } else {
            let controller = NSHostingController(rootView: preview)
            hostingController = controller
            panel.contentViewController = controller
        }

        panel.appearance = sourceWindow?.effectiveAppearance
        panel.setFrame(
            NSRect(
                origin: Self.preferredOrigin(
                    previewSize: previewSize,
                    sourceFrame: sourceWindow?.frame,
                    visibleFrame: visibleFrame
                ),
                size: previewSize
            ),
            display: true
        )
        panel.orderFrontRegardless()
    }

    func hide() {
        pendingHideTask?.cancel()
        pendingHideTask = nil
        isPointerInsidePreview = false
        performHide()
    }

    func applyAppearance(_ appearance: NSAppearance) {
        panel?.appearance = appearance
    }

    func requestHide() {
        guard !isPointerInsidePreview else { return }
        pendingHideTask?.cancel()
        let delay = hideDelay
        pendingHideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled,
                  let self,
                  !isPointerInsidePreview else {
                return
            }
            pendingHideTask = nil
            performHide()
        }
    }

    func setPreviewPointerInside(_ isInside: Bool) {
        isPointerInsidePreview = isInside
        if isInside {
            pendingHideTask?.cancel()
            pendingHideTask = nil
        } else {
            requestHide()
        }
    }

    static func preferredSize(
        kind: ClipboardContentKind,
        imageSize: CGSize?,
        hasTags _: Bool,
        visibleFrame: CGRect,
        text: String? = nil
    ) -> CGSize {
        let maxWidth = max(360, min(780, visibleFrame.width - 40))
        let maxHeight = max(220, min(680, visibleFrame.height - 40))

        guard kind == .image else {
            let value = text ?? ""
            let wrappedLineCount = value
                .split(separator: "\n", omittingEmptySubsequences: false)
                .reduce(into: 0) { count, line in
                    count += max(1, Int(ceil(Double(line.count) / 56.0)))
                }
            let lineCount = max(1, wrappedLineCount)
            let width = min(maxWidth, value.count > 180 || lineCount > 6 ? 600 : 480)
            let contentHeight = max(136, min(maxHeight - 39, CGFloat(lineCount * 20 + 32)))
            return CGSize(
                width: width,
                height: min(maxHeight, 39 + contentHeight)
            )
        }

        let sourceSize = imageSize.flatMap { size in
            size.width > 0 && size.height > 0 ? size : nil
        } ?? CGSize(width: 16, height: 10)
        let chromeHeight: CGFloat = 39
        let imagePadding: CGFloat = 24
        let availableImageSize = CGSize(
            width: max(1, maxWidth - imagePadding),
            height: max(1, maxHeight - chromeHeight - imagePadding)
        )
        let scale = min(
            1,
            min(
                availableImageSize.width / sourceSize.width,
                availableImageSize.height / sourceSize.height
            )
        )
        let fittedImageSize = CGSize(
            width: sourceSize.width * scale,
            height: sourceSize.height * scale
        )

        return CGSize(
            width: min(maxWidth, max(360, fittedImageSize.width + imagePadding)),
            height: min(maxHeight, max(260, fittedImageSize.height + chromeHeight + imagePadding))
        )
    }

    static func preferredOrigin(
        previewSize: CGSize,
        sourceFrame: CGRect?,
        visibleFrame: CGRect
    ) -> CGPoint {
        let margin: CGFloat = 16
        let gap: CGFloat = 12
        let minimumX = visibleFrame.minX + margin
        let maximumX = visibleFrame.maxX - margin - previewSize.width
        let minimumY = visibleFrame.minY + margin
        let maximumY = visibleFrame.maxY - margin - previewSize.height

        var x = visibleFrame.midX - previewSize.width / 2
        var y = visibleFrame.midY - previewSize.height / 2

        if let sourceFrame {
            let rightX = sourceFrame.maxX + gap
            let leftX = sourceFrame.minX - gap - previewSize.width
            if rightX <= maximumX {
                x = rightX
            } else if leftX >= minimumX {
                x = leftX
            }
            y = sourceFrame.maxY - previewSize.height
        }

        return CGPoint(
            x: min(max(x, minimumX), maximumX),
            y: min(max(y, minimumY), maximumY)
        )
    }

    private func makePanel(size: CGSize) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.becomesKeyOnlyIfNeeded = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = true
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.isExcludedFromWindowsMenu = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [
            .transient,
            .moveToActiveSpace,
            .fullScreenAuxiliary,
            .ignoresCycle
        ]
        return panel
    }

    private func performHide() {
        panel?.orderOut(nil)
        panel?.contentViewController = nil
        hostingController = nil
        ClipletPreviewImageCache.removeAll()
    }

    private func cachedImagePixelSize(at url: URL?) -> CGSize? {
        guard let url else { return nil }
        let key = url as NSURL
        if let cached = imageSizeCache.object(forKey: key) {
            return cached.sizeValue
        }
        guard let size = imagePixelSize(at: url) else { return nil }
        imageSizeCache.setObject(NSValue(size: size), forKey: key)
        return size
    }

    private func imagePixelSize(at url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(
            url as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
            return nil
        }
        return CGSize(width: width.doubleValue, height: height.doubleValue)
    }
}
