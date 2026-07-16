import Foundation
import SwiftData

@Model
final class ClipboardItem {
    @Attribute(.unique) var id: UUID
    var kindRawValue: String
    var text: String?
    var imageRelativePath: String?
    var thumbnailRelativePath: String?
    var imageTypeIdentifier: String?
    var imageRecognizedText: String?
    var imageTextIndexedAt: Date?
    @Attribute(.externalStorage) var pasteboardArchiveData: Data?
    @Attribute(.unique) var contentHash: String
    var sourceAppBundleIdentifier: String?
    var sourceAppName: String?
    var createdAt: Date
    var updatedAt: Date
    var isFavorite: Bool

    @Relationship(deleteRule: .nullify, inverse: \ClipTag.items)
    var tags: [ClipTag]

    var kind: ClipboardContentKind {
        get { ClipboardContentKind(rawValue: kindRawValue) ?? .text }
        set { kindRawValue = newValue.rawValue }
    }

    var presentationKind: ClipboardPresentationKind {
        ClipboardPresentationKind.classify(kind: kind, text: text)
    }

    init(
        id: UUID = UUID(),
        kind: ClipboardContentKind,
        text: String? = nil,
        imageRelativePath: String? = nil,
        thumbnailRelativePath: String? = nil,
        imageTypeIdentifier: String? = nil,
        imageRecognizedText: String? = nil,
        imageTextIndexedAt: Date? = nil,
        pasteboardArchiveData: Data? = nil,
        contentHash: String,
        sourceAppBundleIdentifier: String? = nil,
        sourceAppName: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isFavorite: Bool = false,
        tags: [ClipTag] = []
    ) {
        self.id = id
        self.kindRawValue = kind.rawValue
        self.text = text
        self.imageRelativePath = imageRelativePath
        self.thumbnailRelativePath = thumbnailRelativePath
        self.imageTypeIdentifier = imageTypeIdentifier
        self.imageRecognizedText = imageRecognizedText
        self.imageTextIndexedAt = imageTextIndexedAt
        self.pasteboardArchiveData = pasteboardArchiveData
        self.contentHash = contentHash
        self.sourceAppBundleIdentifier = sourceAppBundleIdentifier
        self.sourceAppName = sourceAppName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isFavorite = isFavorite
        self.tags = tags
    }
}
