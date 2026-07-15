import AppKit
import Combine
import CryptoKit
import Foundation
import SwiftData

enum ClipboardStoreError: LocalizedError {
    case emptyText
    case imageTooLarge(maximumBytes: Int)
    case invalidImageData
    case formattedContentTooLarge(maximumBytes: Int)
    case invalidFormattedContent
    case invalidTagName
    case duplicateTagName
    case fileOperationFailed

    var errorDescription: String? {
        switch self {
        case .emptyText:
            return "空白文本不会被记录。"
        case let .imageTooLarge(maximumBytes):
            return "图片超过 \(maximumBytes / 1_048_576) MB，未加入历史记录。"
        case .invalidImageData:
            return "无法读取这张图片。"
        case let .formattedContentTooLarge(maximumBytes):
            return "格式数据超过 \(maximumBytes / 1_048_576) MB，未加入历史记录。"
        case .invalidFormattedContent:
            return "无法保存这段内容的原始格式。"
        case .invalidTagName:
            return "标签名称不能为空。"
        case .duplicateTagName:
            return "已存在同名标签。"
        case .fileOperationFailed:
            return "无法保存剪贴板图片。"
        }
    }
}

@MainActor
final class ClipboardStore: ObservableObject {
    static let maximumImageBytes = 128 * 1_048_576
    static let maximumFormattedContentBytes = 12 * 1_048_576
    static let minimumHistoryLimit = 100
    static let maximumHistoryLimit = 5_000
    static let minimumRetentionDays = 1
    static let maximumRetentionDays = 365

    let modelContainer: ModelContainer
    let modelContext: ModelContext

    @Published private(set) var items: [ClipboardItem]
    @Published private(set) var tags: [ClipTag]
    @Published private(set) var settings: AppSettings
    @Published private(set) var errorMessage: String?

    private let fileManager: FileManager
    private let imagesDirectory: URL
    private let now: () -> Date

    init(
        modelContainer: ModelContainer? = nil,
        fileManager: FileManager = .default,
        imagesDirectory: URL? = nil,
        initialAppearanceMode: NimclipAppearanceMode = .currentSystemMode,
        now: @escaping () -> Date = Date.init
    ) throws {
        let container: ModelContainer
        if let modelContainer {
            container = modelContainer
        } else {
            let schema = Schema([
                ClipboardItem.self,
                ClipTag.self,
                AppSettings.self
            ])
            let configuration = ModelConfiguration("Cliplet", schema: schema)
            container = try ModelContainer(for: schema, configurations: configuration)
        }

        let context = ModelContext(container)
        context.autosaveEnabled = false

        let settingsDescriptor = FetchDescriptor<AppSettings>(
            sortBy: [SortDescriptor(\AppSettings.createdAt)]
        )
        let savedSettings = try context.fetch(settingsDescriptor).first
        let resolvedSettings = savedSettings
            ?? AppSettings(appearanceMode: initialAppearanceMode)
        if savedSettings == nil {
            context.insert(resolvedSettings)
            try context.save()
        } else {
            var shouldSaveSettings = false

            if !resolvedSettings.hasExplicitAppearanceSelection,
               resolvedSettings.appearanceModeRawValue != initialAppearanceMode.rawValue {
                resolvedSettings.appearanceModeRawValue = initialAppearanceMode.rawValue
                shouldSaveSettings = true
            }

            if resolvedSettings.historyLimit == AppSettings.defaultHistoryLimit,
               resolvedSettings.retentionDays == AppSettings.legacyDefaultRetentionDays,
               resolvedSettings.updatedAt.timeIntervalSince(resolvedSettings.createdAt).magnitude < 1 {
                // Move untouched installs from the former 30-day default to the new default.
                // A settings record that the user has edited keeps its chosen value.
                resolvedSettings.retentionDays = AppSettings.defaultRetentionDays
                shouldSaveSettings = true
            }

            if shouldSaveSettings {
                resolvedSettings.updatedAt = now()
                try context.save()
            }
        }

        let resolvedImagesDirectory: URL
        if let imagesDirectory {
            resolvedImagesDirectory = imagesDirectory
        } else {
            let applicationSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            resolvedImagesDirectory = applicationSupport
                .appendingPathComponent("Cliplet", isDirectory: true)
                .appendingPathComponent("ClipboardImages", isDirectory: true)
        }
        try fileManager.createDirectory(
            at: resolvedImagesDirectory,
            withIntermediateDirectories: true
        )

        self.modelContainer = container
        self.modelContext = context
        self.fileManager = fileManager
        self.imagesDirectory = resolvedImagesDirectory
        self.now = now
        self.items = []
        self.tags = []
        self.settings = resolvedSettings
        self.errorMessage = nil

        try refresh()
        try migrateLegacyTagColors()
    }

    @discardableResult
    func refresh() throws -> [ClipboardItem] {
        let itemDescriptor = FetchDescriptor<ClipboardItem>(
            sortBy: [SortDescriptor(\ClipboardItem.updatedAt, order: .reverse)]
        )
        let tagDescriptor = FetchDescriptor<ClipTag>(
            sortBy: [SortDescriptor(\ClipTag.name)]
        )
        items = try modelContext.fetch(itemDescriptor)
        tags = try modelContext.fetch(tagDescriptor)
        return items
    }

    func clearError() {
        errorMessage = nil
    }

    @discardableResult
    func ingestText(
        _ text: String,
        archive: ClipboardPasteboardArchive? = nil,
        sourceAppBundleIdentifier: String? = nil,
        sourceAppName: String? = nil
    ) throws -> ClipboardItem {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            throw report(ClipboardStoreError.emptyText)
        }

        let archiveData = try encodedArchiveData(for: archive)
        let contentHash: String
        if let archive {
            contentHash = Self.sha256Hex(for: archive)
        } else {
            contentHash = Self.sha256Hex(Data("text\0\(text)".utf8))
        }
        return try ingest(
            kind: .text,
            contentHash: contentHash,
            text: text,
            imageRelativePath: nil,
            thumbnailRelativePath: nil,
            imageTypeIdentifier: nil,
            pasteboardArchiveData: archiveData,
            sourceAppBundleIdentifier: sourceAppBundleIdentifier,
            sourceAppName: sourceAppName
        )
    }

    @discardableResult
    func ingestImage(
        _ data: Data,
        typeIdentifier: String? = nil,
        archive: ClipboardPasteboardArchive? = nil,
        sourceAppBundleIdentifier: String? = nil,
        sourceAppName: String? = nil
    ) throws -> ClipboardItem {
        guard data.count <= Self.maximumImageBytes else {
            throw report(
                ClipboardStoreError.imageTooLarge(maximumBytes: Self.maximumImageBytes)
            )
        }
        guard let image = NSImage(data: data) else {
            throw report(ClipboardStoreError.invalidImageData)
        }

        let archiveData = try encodedArchiveData(for: archive)
        let contentHash: String
        if let archive {
            contentHash = Self.sha256Hex(for: archive)
        } else {
            var hashInput = Data("image\0".utf8)
            hashInput.append(data)
            contentHash = Self.sha256Hex(hashInput)
        }
        if let existing = item(withHash: contentHash) {
            if let typeIdentifier {
                existing.imageTypeIdentifier = typeIdentifier
            }
            if let archiveData {
                existing.pasteboardArchiveData = archiveData
            }
            try updateDuplicate(
                existing,
                sourceAppBundleIdentifier: sourceAppBundleIdentifier,
                sourceAppName: sourceAppName
            )
            return existing
        }

        let identifier = UUID().uuidString.lowercased()
        let imageFileName = "\(identifier)-original"
        let thumbnailFileName = "\(identifier)-thumb.png"
        let imageURL = imagesDirectory.appendingPathComponent(imageFileName)
        let thumbnailURL = imagesDirectory.appendingPathComponent(thumbnailFileName)

        do {
            try data.write(to: imageURL, options: .atomic)
            let thumbnail = try Self.thumbnailPNGData(for: image)
            try thumbnail.write(to: thumbnailURL, options: .atomic)
        } catch {
            try? fileManager.removeItem(at: imageURL)
            try? fileManager.removeItem(at: thumbnailURL)
            throw report(ClipboardStoreError.fileOperationFailed)
        }

        do {
            return try ingest(
                kind: .image,
                contentHash: contentHash,
                text: nil,
                imageRelativePath: imageFileName,
                thumbnailRelativePath: thumbnailFileName,
                imageTypeIdentifier: typeIdentifier,
                pasteboardArchiveData: archiveData,
                sourceAppBundleIdentifier: sourceAppBundleIdentifier,
                sourceAppName: sourceAppName
            )
        } catch {
            try? fileManager.removeItem(at: imageURL)
            try? fileManager.removeItem(at: thumbnailURL)
            throw error
        }
    }

    func filteredItems(
        searchText: String = "",
        favoritesOnly: Bool = false,
        tag: ClipTag? = nil
    ) -> [ClipboardItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter { item in
            guard !favoritesOnly || item.isFavorite else { return false }
            guard tag == nil || item.tags.contains(where: { $0.id == tag?.id }) else {
                return false
            }
            guard !query.isEmpty else { return true }

            return item.text?.localizedCaseInsensitiveContains(query) == true
                || item.sourceAppName?.localizedCaseInsensitiveContains(query) == true
                || item.tags.contains(where: {
                    $0.name.localizedCaseInsensitiveContains(query)
                })
        }
    }

    func imageURL(for item: ClipboardItem) -> URL? {
        guard let path = item.imageRelativePath else { return nil }
        return imagesDirectory.appendingPathComponent(path)
    }

    func thumbnailURL(for item: ClipboardItem) -> URL? {
        guard let path = item.thumbnailRelativePath else { return nil }
        return imagesDirectory.appendingPathComponent(path)
    }

    func imageData(for item: ClipboardItem) -> Data? {
        guard let url = imageURL(for: item) else { return nil }
        return try? Data(contentsOf: url)
    }

    func pasteboardArchive(for item: ClipboardItem) -> ClipboardPasteboardArchive? {
        guard let data = item.pasteboardArchiveData else { return nil }
        return ClipboardPasteboardArchive.decode(data)
    }

    func toggleFavorite(_ item: ClipboardItem) throws {
        item.isFavorite.toggle()
        try saveAndRefresh()
    }

    func setFavorite(_ isFavorite: Bool, for item: ClipboardItem) throws {
        guard item.isFavorite != isFavorite else { return }
        item.isFavorite = isFavorite
        try saveAndRefresh()
    }

    func delete(_ item: ClipboardItem) throws {
        removeFiles(for: item)
        modelContext.delete(item)
        try saveAndRefresh()
    }

    func clearHistory(includingFavorites: Bool = false) throws {
        let itemsToDelete = items.filter { includingFavorites || !$0.isFavorite }
        for item in itemsToDelete {
            removeFiles(for: item)
            modelContext.delete(item)
        }
        try saveAndRefresh()
    }

    @discardableResult
    func createTag(name: String, colorHex: String = "2F343A") throws -> ClipTag {
        let normalizedName = try validatedTagName(name)
        guard !containsTag(named: normalizedName) else {
            throw report(ClipboardStoreError.duplicateTagName)
        }

        let tag = ClipTag(name: normalizedName, colorHex: Self.normalizedColorHex(colorHex))
        modelContext.insert(tag)
        try saveAndRefresh()
        return tag
    }

    func renameTag(_ tag: ClipTag, to name: String) throws {
        let normalizedName = try validatedTagName(name)
        guard !containsTag(named: normalizedName, excluding: tag) else {
            throw report(ClipboardStoreError.duplicateTagName)
        }
        tag.name = normalizedName
        try saveAndRefresh()
    }

    func updateTagColor(_ tag: ClipTag, colorHex: String) throws {
        tag.colorHex = Self.normalizedColorHex(colorHex)
        try saveAndRefresh()
    }

    func deleteTag(_ tag: ClipTag) throws {
        modelContext.delete(tag)
        try saveAndRefresh()
    }

    func assign(_ tag: ClipTag, to item: ClipboardItem) throws {
        guard !item.tags.contains(where: { $0.id == tag.id }) else { return }
        item.tags.append(tag)
        try saveAndRefresh()
    }

    func remove(_ tag: ClipTag, from item: ClipboardItem) throws {
        item.tags.removeAll { $0.id == tag.id }
        try saveAndRefresh()
    }

    func toggle(_ tag: ClipTag, on item: ClipboardItem) throws {
        if item.tags.contains(where: { $0.id == tag.id }) {
            try remove(tag, from: item)
        } else {
            try assign(tag, to: item)
        }
    }

    func updateSettings(
        historyLimit: Int? = nil,
        retentionDays: Int? = nil,
        hotKeyKeyCode: UInt32? = nil,
        hotKeyModifiers: UInt32? = nil,
        launchAtLogin: Bool? = nil,
        appearanceMode: NimclipAppearanceMode? = nil
    ) throws {
        let shouldEnforceRetention = historyLimit != nil || retentionDays != nil

        if let historyLimit {
            settings.historyLimit = min(
                max(historyLimit, Self.minimumHistoryLimit),
                Self.maximumHistoryLimit
            )
        }
        if let retentionDays {
            settings.retentionDays = min(
                max(retentionDays, Self.minimumRetentionDays),
                Self.maximumRetentionDays
            )
        }
        if let hotKeyKeyCode {
            settings.hotKeyKeyCode = hotKeyKeyCode
        }
        if let hotKeyModifiers {
            settings.hotKeyModifiers = hotKeyModifiers
        }
        if let launchAtLogin {
            settings.launchAtLogin = launchAtLogin
        }
        if let appearanceMode {
            settings.appearanceModeRawValue = appearanceMode.rawValue
            settings.hasExplicitAppearanceSelection = true
        }
        try saveSettings(enforcingRetention: shouldEnforceRetention)
    }

    func saveSettings(enforcingRetention: Bool = true) throws {
        settings.historyLimit = min(
            max(settings.historyLimit, Self.minimumHistoryLimit),
            Self.maximumHistoryLimit
        )
        settings.retentionDays = min(
            max(settings.retentionDays, Self.minimumRetentionDays),
            Self.maximumRetentionDays
        )
        settings.updatedAt = now()
        do {
            try modelContext.save()
            if enforcingRetention {
                try enforceRetention()
            }
        } catch {
            throw report(error)
        }
    }

    func enforceRetention() throws {
        let currentDate = now()
        let cutoffDate = Calendar.current.date(
            byAdding: .day,
            value: -settings.retentionDays,
            to: currentDate
        ) ?? currentDate

        let expired = items.filter { !$0.isFavorite && $0.updatedAt < cutoffDate }
        let expiredIDs = Set(expired.map(\.id))
        for item in expired {
            removeFiles(for: item)
            modelContext.delete(item)
        }

        let remainingNonFavorites = items
            .filter { !$0.isFavorite && !expiredIDs.contains($0.id) }
            .sorted { $0.updatedAt > $1.updatedAt }
        let overflowCount = max(0, remainingNonFavorites.count - settings.historyLimit)
        if overflowCount > 0 {
            for item in remainingNonFavorites.suffix(overflowCount) {
                removeFiles(for: item)
                modelContext.delete(item)
            }
        }

        try saveAndRefresh()
    }

    private func ingest(
        kind: ClipboardContentKind,
        contentHash: String,
        text: String?,
        imageRelativePath: String?,
        thumbnailRelativePath: String?,
        imageTypeIdentifier: String?,
        pasteboardArchiveData: Data?,
        sourceAppBundleIdentifier: String?,
        sourceAppName: String?
    ) throws -> ClipboardItem {
        if let existing = item(withHash: contentHash) {
            if let imageTypeIdentifier {
                existing.imageTypeIdentifier = imageTypeIdentifier
            }
            if let pasteboardArchiveData {
                existing.pasteboardArchiveData = pasteboardArchiveData
            }
            try updateDuplicate(
                existing,
                sourceAppBundleIdentifier: sourceAppBundleIdentifier,
                sourceAppName: sourceAppName
            )
            return existing
        }

        let timestamp = now()
        let item = ClipboardItem(
            kind: kind,
            text: text,
            imageRelativePath: imageRelativePath,
            thumbnailRelativePath: thumbnailRelativePath,
            imageTypeIdentifier: imageTypeIdentifier,
            pasteboardArchiveData: pasteboardArchiveData,
            contentHash: contentHash,
            sourceAppBundleIdentifier: sourceAppBundleIdentifier,
            sourceAppName: sourceAppName,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        modelContext.insert(item)
        try modelContext.save()
        try refresh()
        try enforceRetention()
        return item
    }

    private func updateDuplicate(
        _ item: ClipboardItem,
        sourceAppBundleIdentifier: String?,
        sourceAppName: String?
    ) throws {
        item.updatedAt = now()
        if let sourceAppBundleIdentifier {
            item.sourceAppBundleIdentifier = sourceAppBundleIdentifier
        }
        if let sourceAppName {
            item.sourceAppName = sourceAppName
        }
        try saveAndRefresh()
        try enforceRetention()
    }

    private func item(withHash hash: String) -> ClipboardItem? {
        items.first { $0.contentHash == hash }
    }

    private func encodedArchiveData(
        for archive: ClipboardPasteboardArchive?
    ) throws -> Data? {
        guard let archive else { return nil }
        guard archive.isValid else {
            throw report(ClipboardStoreError.invalidFormattedContent)
        }

        let data: Data
        do {
            data = try archive.encodedData()
        } catch {
            throw report(ClipboardStoreError.invalidFormattedContent)
        }
        guard data.count <= Self.maximumFormattedContentBytes else {
            throw report(
                ClipboardStoreError.formattedContentTooLarge(
                    maximumBytes: Self.maximumFormattedContentBytes
                )
            )
        }
        return data
    }

    private func saveAndRefresh() throws {
        do {
            try modelContext.save()
            try refresh()
            errorMessage = nil
        } catch {
            throw report(error)
        }
    }

    private func validatedTagName(_ name: String) throws -> String {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw report(ClipboardStoreError.invalidTagName)
        }
        return normalized
    }

    private func containsTag(named name: String, excluding tag: ClipTag? = nil) -> Bool {
        tags.contains {
            $0.id != tag?.id && $0.name.compare(name, options: [.caseInsensitive]) == .orderedSame
        }
    }

    private func removeFiles(for item: ClipboardItem) {
        for path in [item.imageRelativePath, item.thumbnailRelativePath].compactMap({ $0 }) {
            try? fileManager.removeItem(at: imagesDirectory.appendingPathComponent(path))
        }
    }

    private func migrateLegacyTagColors() throws {
        let legacyColors = Set(["159C91", "2AA198", "5965D8"])
        let legacyTags = tags.filter { legacyColors.contains($0.colorHex.uppercased()) }
        guard !legacyTags.isEmpty else { return }

        for tag in legacyTags {
            tag.colorHex = "2F343A"
        }
        try modelContext.save()
        try refresh()
    }

    @discardableResult
    private func report(_ error: Error) -> Error {
        errorMessage = error.localizedDescription
        return error
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func sha256Hex(for archive: ClipboardPasteboardArchive) -> String {
        var hasher = SHA256()
        hasher.update(data: Data("pasteboard\0".utf8))
        hasher.update(data: Data([archive.version]))
        updateHashLength(archive.items.count, hasher: &hasher)

        for item in archive.items {
            let representations = item.representations.sorted {
                $0.typeIdentifier < $1.typeIdentifier
            }
            updateHashLength(representations.count, hasher: &hasher)
            for representation in representations {
                let typeData = Data(representation.typeIdentifier.utf8)
                updateHashLength(typeData.count, hasher: &hasher)
                hasher.update(data: typeData)
                updateHashLength(representation.data.count, hasher: &hasher)
                hasher.update(data: representation.data)
            }
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func updateHashLength(_ value: Int, hasher: inout SHA256) {
        var bigEndianValue = UInt64(value).bigEndian
        let data = Swift.withUnsafeBytes(of: &bigEndianValue) { Data($0) }
        hasher.update(data: data)
    }

    private static func normalizedColorHex(_ value: String) -> String {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .uppercased()
        let hexadecimalCharacters = CharacterSet(charactersIn: "0123456789ABCDEF")
        let isValid = normalized.count == 6
            && normalized.unicodeScalars.allSatisfy(hexadecimalCharacters.contains)
        return isValid ? normalized : "2F343A"
    }

    private static func thumbnailPNGData(for image: NSImage) throws -> Data {
        let maximumDimension: CGFloat = 320
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else {
            throw ClipboardStoreError.invalidImageData
        }

        let scale = min(
            1,
            maximumDimension / max(imageSize.width, imageSize.height)
        )
        let targetSize = NSSize(
            width: max(1, imageSize.width * scale),
            height: max(1, imageSize.height * scale)
        )
        let thumbnail = NSImage(size: targetSize)
        thumbnail.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: imageSize),
            operation: .copy,
            fraction: 1
        )
        thumbnail.unlockFocus()

        guard
            let tiffData = thumbnail.tiffRepresentation,
            let representation = NSBitmapImageRep(data: tiffData),
            let pngData = representation.representation(using: .png, properties: [:])
        else {
            throw ClipboardStoreError.invalidImageData
        }
        return pngData
    }
}
