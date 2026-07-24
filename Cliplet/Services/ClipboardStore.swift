import AppKit
import Combine
import CryptoKit
import Foundation
import ImageIO
import SwiftData
import UniformTypeIdentifiers

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
        errorDescription(in: .defaultLanguage)
    }

    func errorDescription(in language: NimclipLanguage) -> String {
        switch self {
        case .emptyText:
            return language.localized("空白文本不会被记录。")
        case let .imageTooLarge(maximumBytes):
            return language.localizedFormat(
                "图片超过 %d MB，未加入历史记录。",
                maximumBytes / 1_048_576
            )
        case .invalidImageData:
            return language.localized("无法读取这张图片。")
        case let .formattedContentTooLarge(maximumBytes):
            return language.localizedFormat(
                "格式数据超过 %d MB，未加入历史记录。",
                maximumBytes / 1_048_576
            )
        case .invalidFormattedContent:
            return language.localized("无法保存这段内容的原始格式。")
        case .invalidTagName:
            return language.localized("标签名称不能为空。")
        case .duplicateTagName:
            return language.localized("已存在同名标签。")
        case .fileOperationFailed:
            return language.localized("无法保存剪贴板图片。")
        }
    }
}

@MainActor
final class ClipboardStore: ObservableObject {
    static let maximumImageBytes = 128 * 1_048_576
    static let maximumFormattedContentBytes = 12 * 1_048_576
    static let maximumRecognizedTextCharacters = 20_000
    static let maximumNoteCharacters = 1_000
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
               AppSettings.earlierDefaultRetentionDays.contains(
                   resolvedSettings.retentionDays
               ),
               resolvedSettings.updatedAt.timeIntervalSince(resolvedSettings.createdAt).magnitude < 1 {
                // Move untouched installs from earlier defaults to the new
                // default. A settings record that the user has edited keeps
                // its chosen value.
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
        try migrateRedundantImageArchives()
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
        archive _: ClipboardPasteboardArchive? = nil,
        sourceAppBundleIdentifier: String? = nil,
        sourceAppName: String? = nil
    ) throws -> ClipboardItem {
        guard data.count <= Self.maximumImageBytes else {
            throw report(
                ClipboardStoreError.imageTooLarge(maximumBytes: Self.maximumImageBytes)
            )
        }
        guard let imageSource = CGImageSourceCreateWithData(
            data as CFData,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ),
              CGImageSourceGetCount(imageSource) > 0 else {
            throw report(ClipboardStoreError.invalidImageData)
        }

        var hashInput = Data("image\0".utf8)
        hashInput.append(data)
        let contentHash = Self.sha256Hex(hashInput)
        if let existing = item(withHash: contentHash) {
            if let typeIdentifier {
                existing.imageTypeIdentifier = typeIdentifier
            }
            existing.pasteboardArchiveData = nil
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
            let thumbnail = try Self.thumbnailPNGData(from: imageSource)
            try data.write(to: imageURL, options: .atomic)
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
                pasteboardArchiveData: nil,
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
                || item.note?.localizedCaseInsensitiveContains(query) == true
                || item.imageRecognizedText?.localizedCaseInsensitiveContains(query) == true
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

    var unindexedImageItems: [ClipboardItem] {
        items.filter {
            $0.kind == .image
                && $0.imageTextIndexedAt == nil
                && $0.imageRelativePath != nil
        }
    }

    func saveRecognizedImageText(_ text: String, for itemID: UUID) throws {
        guard let item = items.first(where: { $0.id == itemID }),
              item.kind == .image else {
            return
        }

        item.imageRecognizedText = String(text.prefix(Self.maximumRecognizedTextCharacters))
        item.imageTextIndexedAt = now()
        do {
            try modelContext.save()
            errorMessage = nil
        } catch {
            throw report(error)
        }
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

    func setNote(_ note: String?, for item: ClipboardItem) throws {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.flatMap {
            $0.isEmpty ? nil : String($0.prefix(Self.maximumNoteCharacters))
        }
        guard normalized != item.note else { return }

        item.note = normalized
        item.noteUpdatedAt = normalized == nil ? nil : now()
        do {
            // Notes are metadata. In particular, do not change updatedAt:
            // editing a note must not reorder history or scroll the list.
            try modelContext.save()
            errorMessage = nil
        } catch {
            throw report(error)
        }
    }

    func delete(_ item: ClipboardItem) throws {
        removeFiles(for: item)
        modelContext.delete(item)
        try saveAndRefresh()
    }

    func clearHistory() throws {
        for item in itemsEligibleForHistoryCleanup {
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
        appearanceMode: NimclipAppearanceMode? = nil,
        language: NimclipLanguage? = nil,
        automaticImageTextRecognition: Bool? = nil,
        automaticUpdateChecksEnabled: Bool? = nil
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
        if let language {
            settings.languageRawValue = language.rawValue
        }
        if let automaticImageTextRecognition {
            settings.automaticImageTextRecognition = automaticImageTextRecognition
        }
        if let automaticUpdateChecksEnabled {
            settings.automaticUpdateChecksEnabled = automaticUpdateChecksEnabled
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

        let cleanupCandidates = itemsEligibleForHistoryCleanup
        let expired = cleanupCandidates.filter { $0.updatedAt < cutoffDate }
        let expiredIDs = Set(expired.map(\.id))
        let remainingNonFavorites = cleanupCandidates
            .filter { !expiredIDs.contains($0.id) }
            .sorted { $0.updatedAt > $1.updatedAt }
        let overflowCount = max(0, remainingNonFavorites.count - settings.historyLimit)
        let overflow = overflowCount > 0
            ? Array(remainingNonFavorites.suffix(overflowCount))
            : []
        let itemsToDelete = expired + overflow
        guard !itemsToDelete.isEmpty else {
            return
        }

        for item in itemsToDelete {
            removeFiles(for: item)
            modelContext.delete(item)
        }

        try saveAndRefresh()
    }

    /// Favorites are durable library entries, not disposable history.
    /// Retention days, the history limit, and "Clear History" must all use
    /// this same candidate set so none can accidentally remove a favorite.
    private var itemsEligibleForHistoryCleanup: [ClipboardItem] {
        items.filter { !$0.isFavorite }
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
            imageRecognizedText: nil,
            imageTextIndexedAt: nil,
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

    private func migrateRedundantImageArchives() throws {
        let imageItemsWithArchives = items.filter {
            $0.kind == .image && $0.pasteboardArchiveData != nil
        }
        guard !imageItemsWithArchives.isEmpty else { return }

        for item in imageItemsWithArchives {
            item.pasteboardArchiveData = nil
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

    private static func thumbnailPNGData(from imageSource: CGImageSource) throws -> Data {
        try autoreleasepool {
            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
                imageSource,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 320,
                    kCGImageSourceShouldCacheImmediately: true
                ] as CFDictionary
            ) else {
                throw ClipboardStoreError.invalidImageData
            }

            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(
                data,
                UTType.png.identifier as CFString,
                1,
                nil
            ) else {
                throw ClipboardStoreError.invalidImageData
            }
            CGImageDestinationAddImage(destination, thumbnail, nil)
            guard CGImageDestinationFinalize(destination) else {
                throw ClipboardStoreError.invalidImageData
            }
            return data as Data
        }
    }
}
