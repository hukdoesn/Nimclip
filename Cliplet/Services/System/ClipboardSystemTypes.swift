import AppKit
import Foundation

public struct ClipboardSourceApplication: Equatable, Sendable {
    public let name: String?
    public let bundleIdentifier: String?
    public let processIdentifier: pid_t

    public init(name: String?, bundleIdentifier: String?, processIdentifier: pid_t) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
    }

    @MainActor
    init(application: NSRunningApplication?) {
        name = application?.localizedName
        bundleIdentifier = application?.bundleIdentifier
        processIdentifier = application?.processIdentifier ?? 0
    }
}

public struct ClipboardPasteboardArchive: Codable, Equatable, Sendable {
    public static let currentVersion: UInt8 = 1
    public static let maximumItemCount = 64
    public static let maximumRepresentationCountPerItem = 64
    public static let maximumTypeIdentifierBytes = 512
    public static let maximumTotalDataBytes = 10 * 1_048_576

    public struct Item: Codable, Equatable, Sendable {
        public let representations: [Representation]

        public init(representations: [Representation]) {
            self.representations = representations
        }
    }

    public struct Representation: Codable, Equatable, Sendable {
        public let typeIdentifier: String
        public let data: Data

        public init(typeIdentifier: String, data: Data) {
            self.typeIdentifier = typeIdentifier
            self.data = data
        }
    }

    public let version: UInt8
    public let items: [Item]

    public init(items: [Item]) {
        version = Self.currentVersion
        self.items = items
    }

    public var isValid: Bool {
        guard version == Self.currentVersion,
              !items.isEmpty,
              items.count <= Self.maximumItemCount else {
            return false
        }

        var totalDataBytes = 0
        for item in items {
            guard !item.representations.isEmpty,
                  item.representations.count <= Self.maximumRepresentationCountPerItem else {
                return false
            }

            var identifiers = Set<String>()
            for representation in item.representations {
                let typeIdentifierBytes = representation.typeIdentifier.lengthOfBytes(using: .utf8)
                guard !representation.typeIdentifier.isEmpty,
                      typeIdentifierBytes <= Self.maximumTypeIdentifierBytes,
                      identifiers.insert(representation.typeIdentifier).inserted else {
                    return false
                }

                totalDataBytes += representation.data.count
                guard totalDataBytes <= Self.maximumTotalDataBytes else {
                    return false
                }
            }
        }
        return true
    }

    public func encodedData() throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) -> Self? {
        guard let archive = try? PropertyListDecoder().decode(Self.self, from: data),
              archive.isValid else {
            return nil
        }
        return archive
    }
}

public enum ClipboardCapturedContent: Equatable, Sendable {
    case text(String, archive: ClipboardPasteboardArchive? = nil)
    case image(
        data: Data,
        typeIdentifier: String,
        archive: ClipboardPasteboardArchive? = nil
    )
}

public struct ClipboardCapture: Equatable, Sendable {
    public let content: ClipboardCapturedContent
    public let sourceApplication: ClipboardSourceApplication
    public let capturedAt: Date
    public let didOmitRepresentations: Bool

    public init(
        content: ClipboardCapturedContent,
        sourceApplication: ClipboardSourceApplication,
        capturedAt: Date = Date(),
        didOmitRepresentations: Bool = false
    ) {
        self.content = content
        self.sourceApplication = sourceApplication
        self.capturedAt = capturedAt
        self.didOmitRepresentations = didOmitRepresentations
    }
}

public enum ClipboardPastePayload: Equatable, Sendable {
    case text(String)
    case image(data: Data, typeIdentifier: String)
    case archive(ClipboardPasteboardArchive)
}

public struct PasteboardSuppressionToken: Hashable, Sendable {
    public static let process = PasteboardSuppressionToken(rawValue: UUID().uuidString)

    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public enum ClipletPasteboardMarker {
    public static let pasteboardType = NSPasteboard.PasteboardType(
        "com.cliplet.internal-pasteboard-write"
    )

    @MainActor
    public static func isPresent(
        on pasteboard: NSPasteboard,
        token: PasteboardSuppressionToken = .process
    ) -> Bool {
        pasteboard.string(forType: pasteboardType) == token.rawValue
    }

    @MainActor
    static func add(
        to item: NSPasteboardItem,
        token: PasteboardSuppressionToken
    ) {
        item.setString(token.rawValue, forType: pasteboardType)
    }
}
