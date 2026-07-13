import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation

public enum PasteResult: Equatable, Sendable {
    case pasted
    case copiedOnly
}

public enum PasteCoordinatorError: LocalizedError, Equatable {
    case pasteboardWriteFailed

    public var errorDescription: String? {
        switch self {
        case .pasteboardWriteFailed:
            return "The item could not be written to the system clipboard."
        }
    }
}

@MainActor
public final class PasteCoordinator {
    public typealias CloseHandler = @MainActor () -> Void

    private let pasteboard: NSPasteboard
    private let suppressionToken: PasteboardSuppressionToken
    private var previouslyFrontmostApplication: NSRunningApplication?
    private var hasRequestedAccessibilityAccess = false

    public init(
        pasteboard: NSPasteboard = .general,
        suppressionToken: PasteboardSuppressionToken = .process
    ) {
        self.pasteboard = pasteboard
        self.suppressionToken = suppressionToken
        rememberFrontmostApplication()
    }

    public func rememberFrontmostApplication() {
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return
        }
        previouslyFrontmostApplication = application
    }

    public func copy(_ payload: ClipboardPastePayload) throws {
        guard write(payload) else {
            throw PasteCoordinatorError.pasteboardWriteFailed
        }
    }

    public func paste(
        _ payload: ClipboardPastePayload,
        close: CloseHandler
    ) async throws -> PasteResult {
        let targetApplication = pasteTargetApplication()
        try copy(payload)
        close()

        guard hasAccessibilityAccessForPaste(),
              let targetApplication else {
            return .copiedOnly
        }

        try await Task.sleep(for: .milliseconds(80))
        guard targetApplication.activate(options: []) else {
            return .copiedOnly
        }
        try await Task.sleep(for: .milliseconds(120))

        guard postCommandV() else {
            return .copiedOnly
        }
        return .pasted
    }

    @discardableResult
    public static func requestAccessibilityAccess() -> Bool {
        isAccessibilityTrusted(prompt: true)
    }

    public static func isAccessibilityTrusted(prompt: Bool = false) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    public static func openAccessibilitySystemSettings() -> Bool {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else {
            return false
        }
        return NSWorkspace.shared.open(url)
    }

    private func pasteTargetApplication() -> NSRunningApplication? {
        if let previouslyFrontmostApplication,
           !previouslyFrontmostApplication.isTerminated {
            return previouslyFrontmostApplication
        }

        guard let frontmostApplication = NSWorkspace.shared.frontmostApplication,
              frontmostApplication.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return nil
        }
        return frontmostApplication
    }

    private func hasAccessibilityAccessForPaste() -> Bool {
        if Self.isAccessibilityTrusted(prompt: false) {
            return true
        }
        guard !hasRequestedAccessibilityAccess else { return false }

        hasRequestedAccessibilityAccess = true
        return Self.isAccessibilityTrusted(prompt: true)
    }

    private func write(_ payload: ClipboardPastePayload) -> Bool {
        let items: [NSPasteboardItem]

        switch payload {
        case let .text(text):
            let item = NSPasteboardItem()
            item.setString(text, forType: .string)
            items = [item]
        case let .image(data, typeIdentifier):
            guard !data.isEmpty, !typeIdentifier.isEmpty else { return false }
            let item = NSPasteboardItem()
            item.setData(data, forType: NSPasteboard.PasteboardType(typeIdentifier))
            items = [item]
        case let .archive(archive):
            guard let archivedItems = pasteboardItems(from: archive) else {
                return false
            }
            items = archivedItems
        }

        guard let firstItem = items.first else { return false }
        ClipletPasteboardMarker.add(to: firstItem, token: suppressionToken)

        pasteboard.clearContents()
        return pasteboard.writeObjects(items)
    }

    private func pasteboardItems(
        from archive: ClipboardPasteboardArchive
    ) -> [NSPasteboardItem]? {
        guard archive.isValid else { return nil }

        var pasteboardItems: [NSPasteboardItem] = []
        pasteboardItems.reserveCapacity(archive.items.count)
        for archivedItem in archive.items {
            let item = NSPasteboardItem()
            for representation in archivedItem.representations {
                let type = NSPasteboard.PasteboardType(representation.typeIdentifier)
                guard item.setData(representation.data, forType: type) else {
                    return nil
                }
            }
            pasteboardItems.append(item)
        }
        return pasteboardItems
    }

    private func postCommandV() -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_V),
                keyDown: true
              ),
              let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_V),
                keyDown: false
              ) else {
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}
