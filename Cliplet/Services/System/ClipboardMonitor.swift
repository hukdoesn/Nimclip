import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
public final class ClipboardMonitor {
    public typealias CaptureHandler = @MainActor (ClipboardCapture) -> Void
    public typealias SuppressionHandler = @MainActor (NSPasteboard) -> Bool

    public var onCapture: CaptureHandler?
    public var shouldSuppressCapture: SuppressionHandler?

    public private(set) var isRunning = false

    private let pasteboard: NSPasteboard
    private let pollingInterval: Duration
    private let suppressionToken: PasteboardSuppressionToken
    private var lastChangeCount: Int
    private var pollingTask: Task<Void, Never>?

    public init(
        pasteboard: NSPasteboard = .general,
        pollingInterval: Duration = .milliseconds(500),
        suppressionToken: PasteboardSuppressionToken = .process
    ) {
        self.pasteboard = pasteboard
        self.pollingInterval = pollingInterval
        self.suppressionToken = suppressionToken
        lastChangeCount = pasteboard.changeCount
    }

    deinit {
        pollingTask?.cancel()
    }

    public func start() {
        guard !isRunning else { return }

        lastChangeCount = pasteboard.changeCount
        isRunning = true
        pollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                try? await Task.sleep(for: pollingInterval)
                guard !Task.isCancelled else { return }
                pollNow()
            }
        }
    }

    public func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        isRunning = false
    }

    public func pollNow() {
        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount

        if ClipletPasteboardMarker.isPresent(on: pasteboard, token: suppressionToken) {
            return
        }
        if shouldSuppressCapture?(pasteboard) == true {
            return
        }

        guard let result = readContent(),
              pasteboard.changeCount == currentChangeCount else {
            return
        }
        let source = ClipboardSourceApplication(
            application: NSWorkspace.shared.frontmostApplication
        )
        onCapture?(
            ClipboardCapture(
                content: result.content,
                sourceApplication: source,
                didOmitRepresentations: result.didOmitRepresentations
            )
        )
    }

    private func readContent() -> CapturedContentResult? {
        let archiveResult = readPasteboardArchive()

        if let text = preferredPlainText(), !text.isEmpty {
            return CapturedContentResult(
                content: .text(
                    text,
                    archive: archiveResult.archive.flatMap {
                        archiveRequiringStorage($0, fallbackText: text)
                    }
                ),
                didOmitRepresentations: archiveResult.didOmitRepresentations
            )
        }

        guard let imageType = preferredImageType(),
              let data = pasteboard.data(forType: imageType),
              !data.isEmpty else {
            return nil
        }

        return CapturedContentResult(
            content: .image(
                data: data,
                typeIdentifier: imageType.rawValue,
                archive: archiveResult.archive.flatMap {
                    archiveRequiringStorage(
                        $0,
                        fallbackImageData: data,
                        typeIdentifier: imageType.rawValue
                    )
                }
            ),
            didOmitRepresentations: archiveResult.didOmitRepresentations
        )
    }

    private func preferredPlainText() -> String? {
        guard let pasteboardItems = pasteboard.pasteboardItems,
              !pasteboardItems.isEmpty else {
            return pasteboard.string(forType: .string)
        }

        let strings = pasteboardItems.compactMap(displayText)
        guard !strings.isEmpty else {
            return pasteboard.string(forType: .string)
        }
        return strings.joined(separator: "\n")
    }

    private func displayText(for item: NSPasteboardItem) -> String? {
        for type in Self.directTextTypes {
            if let text = item.string(forType: type), !text.isEmpty {
                return text
            }
        }

        for richTextType in Self.richTextTypes {
            guard let data = item.data(forType: richTextType.pasteboardType),
                  let attributedString = try? NSAttributedString(
                    data: data,
                    options: [.documentType: richTextType.documentType],
                    documentAttributes: nil
                  ),
                  !attributedString.string.isEmpty else {
                continue
            }
            return attributedString.string
        }
        return nil
    }

    private func readPasteboardArchive() -> PasteboardArchiveReadResult {
        guard let pasteboardItems = pasteboard.pasteboardItems,
              !pasteboardItems.isEmpty else {
            return PasteboardArchiveReadResult()
        }
        guard pasteboardItems.count <= ClipboardPasteboardArchive.maximumItemCount else {
            return PasteboardArchiveReadResult(didOmitRepresentations: true)
        }

        var totalDataBytes = 0
        var archivedItems: [ClipboardPasteboardArchive.Item] = []
        archivedItems.reserveCapacity(pasteboardItems.count)

        for pasteboardItem in pasteboardItems {
            let types = pasteboardItem.types.filter(shouldArchive)
            guard !types.isEmpty else {
                return PasteboardArchiveReadResult()
            }
            guard types.count
                    <= ClipboardPasteboardArchive.maximumRepresentationCountPerItem else {
                return PasteboardArchiveReadResult(didOmitRepresentations: true)
            }

            var representations: [ClipboardPasteboardArchive.Representation] = []
            representations.reserveCapacity(types.count)
            for type in types {
                let typeIdentifier = type.rawValue
                guard typeIdentifier.lengthOfBytes(using: .utf8)
                        <= ClipboardPasteboardArchive.maximumTypeIdentifierBytes else {
                    return PasteboardArchiveReadResult(didOmitRepresentations: true)
                }
                guard let data = pasteboardItem.data(forType: type) else {
                    return PasteboardArchiveReadResult(didOmitRepresentations: true)
                }
                guard data.count <= ClipboardPasteboardArchive.maximumTotalDataBytes - totalDataBytes else {
                    return PasteboardArchiveReadResult(didOmitRepresentations: true)
                }

                totalDataBytes += data.count
                representations.append(
                    .init(typeIdentifier: typeIdentifier, data: data)
                )
            }

            guard !representations.isEmpty else {
                return PasteboardArchiveReadResult(didOmitRepresentations: true)
            }
            archivedItems.append(.init(representations: representations))
        }

        let archive = ClipboardPasteboardArchive(items: archivedItems)
        guard archive.isValid else {
            return PasteboardArchiveReadResult(didOmitRepresentations: true)
        }
        return PasteboardArchiveReadResult(
            archive: archive
        )
    }

    private func shouldArchive(_ type: NSPasteboard.PasteboardType) -> Bool {
        let identifier = type.rawValue
        if identifier == ClipletPasteboardMarker.pasteboardType.rawValue {
            return false
        }

        let normalizedIdentifier = identifier.lowercased()
        if normalizedIdentifier.contains("promise") {
            return false
        }

        return !Self.pasteboardMetadataTypes.contains(identifier)
    }

    private func archiveRequiringStorage(
        _ archive: ClipboardPasteboardArchive,
        fallbackText _: String
    ) -> ClipboardPasteboardArchive? {
        guard archive.items.count == 1,
              archive.items[0].representations.count == 1,
              let representation = archive.items[0].representations.first,
              representation.typeIdentifier == NSPasteboard.PasteboardType.string.rawValue else {
            return archive
        }
        return nil
    }

    private func archiveRequiringStorage(
        _ archive: ClipboardPasteboardArchive,
        fallbackImageData: Data,
        typeIdentifier: String
    ) -> ClipboardPasteboardArchive? {
        guard archive.items.count == 1,
              archive.items[0].representations.count == 1,
              let representation = archive.items[0].representations.first,
              representation.typeIdentifier == typeIdentifier,
              representation.data == fallbackImageData else {
            return archive
        }
        return nil
    }

    private func preferredImageType() -> NSPasteboard.PasteboardType? {
        let availableTypes = pasteboard.types ?? []
        let preferredIdentifiers = [UTType.png.identifier, UTType.tiff.identifier]

        for identifier in preferredIdentifiers {
            let type = NSPasteboard.PasteboardType(identifier)
            if availableTypes.contains(type) {
                return type
            }
        }

        return availableTypes.first { pasteboardType in
            UTType(pasteboardType.rawValue)?.conforms(to: .image) == true
        }
    }

    private static let pasteboardMetadataTypes: Set<String> = [
        "org.nspasteboard.TransientType",
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.AutoGeneratedType"
    ]

    private static let directTextTypes: [NSPasteboard.PasteboardType] = [
        .string,
        .tabularText,
        .URL,
        .fileURL
    ]

    private static let richTextTypes: [(
        pasteboardType: NSPasteboard.PasteboardType,
        documentType: NSAttributedString.DocumentType
    )] = [
        (.rtfd, .rtfd),
        (NSPasteboard.PasteboardType("com.apple.flat-rtfd"), .rtfd),
        (.rtf, .rtf),
        (.html, .html)
    ]

    private struct CapturedContentResult {
        let content: ClipboardCapturedContent
        let didOmitRepresentations: Bool
    }

    private struct PasteboardArchiveReadResult {
        let archive: ClipboardPasteboardArchive?
        let didOmitRepresentations: Bool

        init(
            archive: ClipboardPasteboardArchive? = nil,
            didOmitRepresentations: Bool = false
        ) {
            self.archive = archive
            self.didOmitRepresentations = didOmitRepresentations
        }
    }
}
