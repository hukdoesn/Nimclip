import AppKit
import ImageIO
import SwiftUI

struct ClipboardItemRow: View {
    let item: ClipboardItem
    let tags: [ClipTag]
    let textPreview: String
    let thumbnailURL: URL?
    let presentationKind: ClipboardPresentationKind
    let referenceDate: Date
    let language: NimclipLanguage
    let isSelected: Bool
    let isCollectionMode: Bool
    let collectionIndex: Int?
    let onHoverChange: (Bool) -> Void
    let onPaste: () -> Void
    let onPastePlainText: () -> Void
    let onCopy: () -> Void
    let onCopyPlainText: () -> Void
    let onOpenLink: () -> Void
    let onToggleCollection: () -> Void
    let onToggleFavorite: () -> Void
    let onDelete: () -> Void
    let onToggleTag: (ClipTag) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false
    @State private var sourceAppIcon: NSImage?

    private var sourceName: String {
        guard let sourceAppName = item.sourceAppName, !sourceAppName.isEmpty else {
            return language.localized("未知来源")
        }
        return sourceAppName
    }

    private var isCollected: Bool { collectionIndex != nil }

    private var favoriteColor: Color { .clipletFavorite }

    var body: some View {
        HStack(spacing: 10) {
            thumbnail

            VStack(alignment: .leading, spacing: 6) {
                Group {
                    if item.kind == .image {
                        Text("图片")
                    } else {
                        Text(textPreview)
                    }
                }
                .font(
                    .system(
                        size: 13,
                        weight: .medium,
                        design: presentationKind == .code ? .monospaced : .default
                    )
                )
                .foregroundStyle(Color.primary)
                .lineLimit(item.kind == .text ? 2 : 1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 6) {
                    Text(sourceName)
                        .lineLimit(1)
                    Text("·")
                    Text(
                        ClipletTimestampFormatter.string(
                            for: item.updatedAt,
                            relativeTo: referenceDate,
                            language: language
                        )
                    )
                        .monospacedDigit()

                    Label(
                        presentationKind.title(in: language),
                        systemImage: presentationKind.systemImage
                    )
                        .labelStyle(.titleAndIcon)

                    if !tags.isEmpty, let firstTag = item.tags.first {
                        Circle()
                            .fill(Color(clipletHex: firstTag.colorHex))
                            .frame(width: 6, height: 6)
                        Text(firstTag.name)
                            .lineLimit(1)
                    }
                }
                .font(.system(size: 10.5))
                .foregroundStyle(Color.secondary)
            }

            if isCollectionMode {
                ZStack {
                    Circle()
                        .fill(isCollected ? Color.clipletSelection : Color.clear)
                        .overlay {
                            Circle()
                                .stroke(
                                    isCollected ? Color.clipletSelection : Color.secondary.opacity(0.45),
                                    lineWidth: 1
                                )
                        }
                    if let collectionIndex {
                        Text("\(collectionIndex)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white)
                    }
                }
                .frame(width: 23, height: 23)
                .accessibilityLabel(
                    isCollected
                        ? language.localizedFormat("拼贴顺序 %d", collectionIndex ?? 0)
                        : language.localized("未加入拼贴")
                )
            } else {
                HStack(spacing: 1) {
                    if item.kind == .text {
                        Button(action: onPastePlainText) {
                            Image(systemName: "doc.plaintext")
                                .frame(width: 27, height: 27)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(ClipletQuietIconButtonStyle())
                        .opacity(isHovered || isSelected ? 1 : 0)
                        .allowsHitTesting(isHovered || isSelected)
                        .help("以纯文本粘贴")
                        .accessibilityLabel("以纯文本粘贴")
                    }

                    if presentationKind == .link {
                        Button(action: onOpenLink) {
                            Image(systemName: "arrow.up.right")
                                .frame(width: 27, height: 27)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(ClipletQuietIconButtonStyle())
                        .opacity(isHovered || isSelected ? 1 : 0)
                        .allowsHitTesting(isHovered || isSelected)
                        .help("打开链接")
                        .accessibilityLabel("打开链接")
                    }

                    Button(action: onToggleFavorite) {
                        Image(systemName: item.isFavorite ? "star.fill" : "star")
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(item.isFavorite ? favoriteColor : Color.secondary)
                            .frame(width: 27, height: 27)
                            .background(
                                item.isFavorite ? favoriteColor.opacity(0.12) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 6)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(ClipletQuietIconButtonStyle())
                    .opacity(item.isFavorite || isHovered || isSelected ? 1 : 0)
                    .help(language.localized(item.isFavorite ? "取消收藏" : "收藏"))
                    .accessibilityLabel(
                        language.localized(item.isFavorite ? "取消收藏" : "收藏")
                    )
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 64, maxHeight: 64, alignment: .leading)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(rowBorder, lineWidth: 0.75)
        }
        .overlay(alignment: .leading) {
            if isSelected && !isCollected {
                Capsule()
                    .fill(Color.clipletSelection)
                    .frame(width: 2.5, height: 30)
                    .padding(.leading, 7)
            }
        }
        .padding(.horizontal, 6)
        .opacity(isCollectionMode && item.kind != .text ? 0.44 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            if isCollectionMode {
                onToggleCollection()
            } else {
                onPaste()
            }
        }
        .onHover { hovering in
            isHovered = hovering
            onHoverChange(hovering)
        }
        .task(id: item.sourceAppBundleIdentifier) {
            await loadSourceAppIcon()
        }
        .onDisappear {
            sourceAppIcon = nil
        }
        .contextMenu { contextMenu }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityAddTraits(isSelected || isCollected ? .isSelected : [])
        .accessibilityAction(named: language.localized("粘贴"), onPaste)
        .accessibilityAction(
            named: language.localized(item.isFavorite ? "取消收藏" : "收藏"),
            onToggleFavorite
        )
    }

    @ViewBuilder
    private var thumbnail: some View {
        if item.kind == .image {
            ClipletImageThumbnail(url: thumbnailURL)
        } else {
            ZStack {
                if let sourceAppIcon {
                    Image(nsImage: sourceAppIcon)
                        .resizable()
                        .scaledToFit()
                        .padding(2)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.clipletControlFill)
                    Image(systemName: presentationKind.systemImage)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.secondary)
                }

                if sourceAppIcon != nil {
                    Image(systemName: presentationKind.systemImage)
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(Color.primary)
                        .frame(width: 15, height: 15)
                        .background(.regularMaterial, in: Circle())
                        .overlay {
                            Circle()
                                .stroke(Color.clipletBorder.opacity(0.72), lineWidth: 0.5)
                        }
                        .offset(x: 14, y: 14)
                }
            }
            .frame(width: 42, height: 42)
            .accessibilityHidden(true)
        }
    }

    private var rowBackground: Color {
        if isCollected {
            return Color.clipletSelection.opacity(colorScheme == .dark ? 0.18 : 0.10)
        }
        if isSelected {
            return Color.primary.opacity(colorScheme == .dark ? 0.095 : 0.055)
        }
        if isHovered {
            return .clipletHover
        }
        return .clear
    }

    private var rowBorder: Color {
        if isCollected { return Color.clipletSelection.opacity(0.54) }
        return .clear
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button(action: onPaste) {
            Label("粘贴", systemImage: "arrow.turn.down.left")
        }
        if item.kind == .text {
            Button(action: onPastePlainText) {
                Label("以纯文本粘贴", systemImage: "doc.plaintext")
            }
        }
        Button(action: onCopy) {
            Label("复制", systemImage: "doc.on.doc")
        }
        if item.kind == .text {
            Button(action: onCopyPlainText) {
                Label("复制纯文本", systemImage: "doc.plaintext")
            }
            Button(action: onToggleCollection) {
                Label(
                    language.localized(isCollected ? "从拼贴中移除" : "加入多条拼贴"),
                    systemImage: isCollected ? "minus.circle" : "rectangle.stack.badge.plus"
                )
            }
        }
        if presentationKind == .link {
            Button(action: onOpenLink) {
                Label("打开链接", systemImage: "arrow.up.right.square")
            }
        }
        Button(action: onToggleFavorite) {
            Label(
                language.localized(item.isFavorite ? "取消收藏" : "收藏"),
                systemImage: item.isFavorite ? "star.slash" : "star"
            )
        }

        if !tags.isEmpty {
            Menu {
                ForEach(tags) { tag in
                    Button {
                        onToggleTag(tag)
                    } label: {
                        Label(tag.name, systemImage: hasTag(tag) ? "checkmark" : "tag")
                    }
                }
            } label: {
                Label("标签", systemImage: "tag")
            }
        }

        Divider()
        Button(role: .destructive, action: onDelete) {
            Label("删除", systemImage: "trash")
        }
    }

    private var accessibilityDescription: String {
        let content = item.kind == .image ? language.localized("图片") : textPreview
        return language.localizedFormat("%@，来自 %@", content, sourceName)
    }

    private func hasTag(_ tag: ClipTag) -> Bool {
        item.tags.contains { $0.id == tag.id }
    }

    @MainActor
    private func loadSourceAppIcon() async {
        sourceAppIcon = nil
        guard item.kind == .text,
              let bundleIdentifier = item.sourceAppBundleIdentifier else {
            return
        }
        let cgImage = await ClipletSourceAppIconLoader.shared.icon(
            bundleIdentifier: bundleIdentifier
        )
        guard !Task.isCancelled, let cgImage else { return }
        sourceAppIcon = NSImage(cgImage: cgImage, size: .zero)
    }
}

private actor ClipletSourceAppIconLoader {
    static let shared = ClipletSourceAppIconLoader()

    private static let iconPixelSize = 76
    private let cache: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.countLimit = 64
        cache.totalCostLimit = 2 * 1_048_576
        return cache
    }()
    private var unavailableBundleIdentifiers = Set<String>()

    func icon(bundleIdentifier: String) async -> CGImage? {
        guard !bundleIdentifier.isEmpty, !Task.isCancelled else { return nil }
        let key = bundleIdentifier as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard !unavailableBundleIdentifiers.contains(bundleIdentifier) else { return nil }
        guard let applicationURL = await MainActor.run(body: {
            NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: bundleIdentifier
            )
        }), !Task.isCancelled,
        let iconURL = Self.iconURL(forApplicationAt: applicationURL),
        let source = CGImageSourceCreateWithURL(
            iconURL as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ),
        let icon = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: Self.iconPixelSize,
                kCGImageSourceShouldCacheImmediately: true
            ] as CFDictionary
        ) else {
            unavailableBundleIdentifiers.insert(bundleIdentifier)
            return nil
        }
        guard !Task.isCancelled else { return nil }
        cache.setObject(
            icon,
            forKey: key,
            cost: icon.bytesPerRow * icon.height
        )
        return icon
    }

    private static func iconURL(forApplicationAt applicationURL: URL) -> URL? {
        guard let bundle = Bundle(url: applicationURL),
              var iconName = bundle.object(
                  forInfoDictionaryKey: "CFBundleIconFile"
              ) as? String,
              !iconName.isEmpty,
              let resourcesURL = bundle.resourceURL else {
            return nil
        }
        if URL(fileURLWithPath: iconName).pathExtension.isEmpty {
            iconName += ".icns"
        }
        return resourcesURL.appendingPathComponent(iconName)
    }
}

private struct ClipletImageThumbnail: View {
    let url: URL?

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary.opacity(0.55))

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 42, height: 42)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
        }
        .task(id: url) {
            await loadImage()
        }
        .onDisappear {
            image = nil
        }
        .accessibilityHidden(true)
    }

    @MainActor
    private func loadImage() async {
        image = nil
        guard let url else { return }
        let cgImage = await ClipletThumbnailDecoder.shared.image(at: url)
        guard !Task.isCancelled, let cgImage else { return }
        image = NSImage(cgImage: cgImage, size: .zero)
    }
}

private actor ClipletThumbnailDecoder {
    static let shared = ClipletThumbnailDecoder()

    func image(at url: URL) -> CGImage? {
        guard !Task.isCancelled else { return nil }
        return ClipletThumbnailCache.image(at: url)
    }
}

private final class ClipletThumbnailCache: @unchecked Sendable {
    nonisolated(unsafe) private static let cache: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.countLimit = 160
        cache.totalCostLimit = 8 * 1_048_576
        return cache
    }()
    private static let unavailablePathsLock = NSLock()
    nonisolated(unsafe) private static var unavailablePaths = Set<String>()

    static func image(at url: URL) -> CGImage? {
        autoreleasepool {
            guard !Task.isCancelled else { return nil }
            let path = url.path
            let key = path as NSString
            if let cached = cache.object(forKey: key) { return cached }
            unavailablePathsLock.lock()
            let isUnavailable = unavailablePaths.contains(path)
            unavailablePathsLock.unlock()
            guard !isUnavailable else { return nil }
            guard let source = CGImageSourceCreateWithURL(
                url as CFURL,
                [kCGImageSourceShouldCache: false] as CFDictionary
            ) else {
                markUnavailable(path)
                return nil
            }
            guard !Task.isCancelled else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 96,
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                options as CFDictionary
            ) else {
                markUnavailable(path)
                return nil
            }
            guard !Task.isCancelled else { return nil }
            cache.setObject(
                cgImage,
                forKey: key,
                cost: cgImage.bytesPerRow * cgImage.height
            )
            return cgImage
        }
    }

    static func removeAll() {
        cache.removeAllObjects()
    }

    private static func markUnavailable(_ path: String) {
        unavailablePathsLock.lock()
        unavailablePaths.insert(path)
        unavailablePathsLock.unlock()
    }
}

struct ClipboardItemExpandedPreview: View {
    let item: ClipboardItem
    let imageURL: URL?
    let thumbnailURL: URL?
    let referenceDate: Date
    let language: NimclipLanguage
    let previewSize: CGSize
    let onHoverChange: (Bool) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var loadedPreviewImage: NSImage?
    @State private var sourceAppIcon: NSImage?

    init(
        item: ClipboardItem,
        imageURL: URL?,
        thumbnailURL: URL?,
        referenceDate: Date,
        language: NimclipLanguage = .defaultLanguage,
        previewSize: CGSize = CGSize(width: 372, height: 438),
        onHoverChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.item = item
        self.imageURL = imageURL
        self.thumbnailURL = thumbnailURL
        self.referenceDate = referenceDate
        self.language = language
        self.previewSize = previewSize
        self.onHoverChange = onHoverChange
    }

    private var sourceName: String {
        guard let sourceAppName = item.sourceAppName, !sourceAppName.isEmpty else {
            return language.localized("未知来源")
        }
        return sourceAppName
    }

    private var fullText: String {
        guard let text = item.text, !text.isEmpty else {
            return language.localized("空文本")
        }
        return text
    }

    private var presentationKind: ClipboardPresentationKind {
        item.presentationKind
    }

    var body: some View {
        VStack(spacing: 0) {
            previewBar
            Divider()
                .opacity(0.55)
            content
        }
        .frame(width: previewSize.width, height: previewSize.height)
        .environment(\.locale, language.locale)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color.clipletBorder.opacity(0.72), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.20), radius: 18, y: 8)
        .onHover(perform: onHoverChange)
        .task(id: previewImageTaskID) {
            await loadPreviewImage()
        }
        .task(id: item.sourceAppBundleIdentifier) {
            await loadSourceAppIcon()
        }
        .onDisappear {
            loadedPreviewImage = nil
            sourceAppIcon = nil
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            language.localized(item.kind == .image ? "图片完整预览" : "完整文本预览")
        )
    }

    private var previewBar: some View {
        HStack(spacing: 7) {
            if let sourceAppIcon {
                Image(nsImage: sourceAppIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: presentationKind.systemImage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
            }

            Text(sourceName)
                .font(.system(size: 11.5, weight: .medium))
                .lineLimit(1)

            Text("·")
                .foregroundStyle(.tertiary)

            Text(presentationKind.title(in: language))
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)

            if let firstTag = item.tags.first {
                Text("·")
                    .foregroundStyle(.tertiary)
                Circle()
                    .fill(Color(clipletHex: firstTag.colorHex))
                    .frame(width: 6, height: 6)
                Text(firstTag.name)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if item.tags.count > 1 {
                    Text("+\(item.tags.count - 1)")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 8)

            Text(
                ClipletTimestampFormatter.string(
                    for: item.updatedAt,
                    relativeTo: referenceDate,
                    language: language
                )
            )
            .font(.system(size: 10.5))
            .foregroundStyle(.tertiary)
            .monospacedDigit()
        }
        .padding(.horizontal, 11)
        .frame(height: 38)
        .background(Color.primary.opacity(0.018))
    }

    @ViewBuilder
    private var content: some View {
        if item.kind == .image {
            ZStack {
                Color.black.opacity(colorScheme == .dark ? 0.19 : 0.035)

                if let loadedPreviewImage {
                    Image(nsImage: loadedPreviewImage)
                        .resizable()
                        .scaledToFit()
                        .padding(10)
                } else {
                    ContentUnavailableView("图片不可用", systemImage: "photo.badge.exclamationmark")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                Text(fullText)
                    .font(
                        .system(
                            size: 13.5,
                            design: presentationKind == .code ? .monospaced : .default
                        )
                    )
                    .lineSpacing(presentationKind == .code ? 3 : 4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
            }
            .scrollIndicators(.automatic)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    private var maximumPreviewPixelSize: Int {
        let target = max(previewSize.width, previewSize.height) * 2
        return Int(min(1_800, max(960, target)))
    }

    private var previewImageTaskID: String {
        "\(imageURL?.path ?? "")|\(thumbnailURL?.path ?? "")|\(maximumPreviewPixelSize)"
    }

    @MainActor
    private func loadPreviewImage() async {
        loadedPreviewImage = nil
        let cgImage = await ClipletPreviewImageDecoder.shared.image(
            at: imageURL,
            fallbackURL: thumbnailURL,
            maximumPixelSize: maximumPreviewPixelSize
        )
        guard !Task.isCancelled, let cgImage else { return }
        loadedPreviewImage = NSImage(cgImage: cgImage, size: .zero)
    }

    @MainActor
    private func loadSourceAppIcon() async {
        sourceAppIcon = nil
        guard let bundleIdentifier = item.sourceAppBundleIdentifier else {
            return
        }
        let cgImage = await ClipletSourceAppIconLoader.shared.icon(
            bundleIdentifier: bundleIdentifier
        )
        guard !Task.isCancelled, let cgImage else { return }
        sourceAppIcon = NSImage(cgImage: cgImage, size: .zero)
    }
}

private actor ClipletPreviewImageDecoder {
    static let shared = ClipletPreviewImageDecoder()

    func image(
        at url: URL?,
        fallbackURL: URL?,
        maximumPixelSize: Int
    ) -> CGImage? {
        guard !Task.isCancelled else { return nil }
        if let image = ClipletPreviewImageCache.image(
            at: url,
            maximumPixelSize: maximumPixelSize
        ) {
            return image
        }
        guard !Task.isCancelled else { return nil }
        return ClipletPreviewImageCache.image(
            at: fallbackURL,
            maximumPixelSize: maximumPixelSize
        )
    }
}

final class ClipletPreviewImageCache: @unchecked Sendable {
    nonisolated(unsafe) private static let cache: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.countLimit = 1
        cache.totalCostLimit = 16 * 1_048_576
        return cache
    }()

    static func removeAll() {
        cache.removeAllObjects()
    }

    static func image(at url: URL?, maximumPixelSize: Int) -> CGImage? {
        autoreleasepool {
            guard !Task.isCancelled, let url else { return nil }
            let key = "\(url.path)#\(maximumPixelSize)" as NSString
            if let cached = cache.object(forKey: key) { return cached }
            guard let source = CGImageSourceCreateWithURL(
                url as CFURL,
                [kCGImageSourceShouldCache: false] as CFDictionary
            ) else {
                return nil
            }
            guard !Task.isCancelled else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                options as CFDictionary
            ) else {
                return nil
            }
            guard !Task.isCancelled else { return nil }
            cache.setObject(
                image,
                forKey: key,
                cost: image.bytesPerRow * image.height
            )
            return image
        }
    }
}

struct ClipletTagFilterBar: View {
    let tags: [ClipTag]
    @Binding var selection: UUID?
    var language: NimclipLanguage = .defaultLanguage

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 3) {
                ClipletTagFilterButton(
                    title: language.localized("全部"),
                    color: nil,
                    isSelected: selection == nil,
                    language: language
                ) {
                    selection = nil
                }

                ForEach(tags) { tag in
                    ClipletTagFilterButton(
                        title: tag.name,
                        color: Color(clipletHex: tag.colorHex),
                        isSelected: selection == tag.id,
                        language: language
                    ) {
                        selection = tag.id
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .frame(height: 28)
        .accessibilityLabel(language.localized("标签筛选"))
    }
}

private struct ClipletTagFilterButton: View {
    let title: String
    let color: Color?
    let isSelected: Bool
    let language: NimclipLanguage
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let color {
                    Circle()
                        .fill(color)
                        .frame(width: 7, height: 7)
                }

                Text(title)
                    .lineLimit(1)

                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .frame(width: 9)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
            .padding(.horizontal, 7)
            .frame(height: 26)
            .background(
                isSelected
                    ? Color.primary.opacity(colorScheme == .dark ? 0.15 : 0.08)
                    : (isHovered ? Color.clipletHover : Color.clear),
                in: RoundedRectangle(cornerRadius: 5)
            )
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
        .accessibilityLabel(language.localizedFormat("标签 %@", title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct ClipletToast: View {
    let message: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.primary)
            Text(message)
                .lineLimit(1)
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
        .accessibilityElement(children: .combine)
    }
}

struct ClipletIconButtonStyle: ButtonStyle {
    var isActive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isActive ? Color.clipletSelectionForeground : Color.secondary)
            .background(
                isActive
                    ? Color.clipletSelection
                    : Color.primary.opacity(configuration.isPressed ? 0.1 : 0),
                in: RoundedRectangle(cornerRadius: 7)
            )
    }
}

struct ClipletQuietIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.secondary)
            .background(
                Color.primary.opacity(configuration.isPressed ? 0.10 : 0),
                in: RoundedRectangle(cornerRadius: 6)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
