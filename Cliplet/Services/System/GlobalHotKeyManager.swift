import Carbon.HIToolbox
import Foundation

public struct GlobalHotKeyShortcut: Equatable, Sendable {
    public static let defaultPaste = GlobalHotKeyShortcut(
        keyCode: UInt32(kVK_ANSI_V),
        modifiers: UInt32(cmdKey | shiftKey)
    )

    public let keyCode: UInt32
    public let modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

public enum GlobalHotKeyError: LocalizedError, Equatable {
    case conflict
    case eventHandlerInstallationFailed(OSStatus)
    case registrationFailed(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .conflict:
            return "The keyboard shortcut is already in use."
        case let .eventHandlerInstallationFailed(status):
            return "The hot key event handler could not be installed (OSStatus \(status))."
        case let .registrationFailed(status):
            return "The global hot key could not be registered (OSStatus \(status))."
        }
    }
}

@MainActor
public final class GlobalHotKeyManager {
    public typealias TriggerHandler = @MainActor () -> Void

    public var onTrigger: TriggerHandler?
    public private(set) var shortcut: GlobalHotKeyShortcut

    private static let signature: OSType = 0x434C5054 // "CLPT"
    private static let identifier: UInt32 = 1

    // Carbon owns these opaque registrations. Access is main-thread confined except
    // for synchronous teardown in this class's nonisolated deinitializer.
    nonisolated(unsafe) private var eventHandlerReference: EventHandlerRef?
    nonisolated(unsafe) private var hotKeyReference: EventHotKeyRef?

    public init(shortcut: GlobalHotKeyShortcut = .defaultPaste) throws {
        self.shortcut = shortcut
        try installEventHandler()

        do {
            hotKeyReference = try register(shortcut)
        } catch {
            if let eventHandlerReference {
                RemoveEventHandler(eventHandlerReference)
            }
            throw error
        }
    }

    deinit {
        if let hotKeyReference {
            UnregisterEventHotKey(hotKeyReference)
        }
        if let eventHandlerReference {
            RemoveEventHandler(eventHandlerReference)
        }
    }

    public func reconfigure(to newShortcut: GlobalHotKeyShortcut) throws {
        guard newShortcut != shortcut else { return }

        let previousShortcut = shortcut
        if let hotKeyReference {
            UnregisterEventHotKey(hotKeyReference)
            self.hotKeyReference = nil
        }

        do {
            hotKeyReference = try register(newShortcut)
            shortcut = newShortcut
        } catch {
            hotKeyReference = try? register(previousShortcut)
            throw error
        }
    }

    private func installEventHandler() throws {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.eventHandler,
            1,
            &eventType,
            context,
            &eventHandlerReference
        )

        guard status == noErr else {
            throw GlobalHotKeyError.eventHandlerInstallationFailed(status)
        }
    }

    private func register(_ shortcut: GlobalHotKeyShortcut) throws -> EventHotKeyRef {
        var reference: EventHotKeyRef?
        let identifier = EventHotKeyID(
            signature: Self.signature,
            id: Self.identifier
        )
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &reference
        )

        guard status == noErr, let reference else {
            if status == eventHotKeyExistsErr {
                throw GlobalHotKeyError.conflict
            }
            throw GlobalHotKeyError.registrationFailed(status)
        }
        return reference
    }

    private func handlePressedHotKey(_ identifier: EventHotKeyID) {
        guard identifier.signature == Self.signature,
              identifier.id == Self.identifier else {
            return
        }
        onTrigger?()
    }

    private nonisolated static let eventHandler: EventHandlerUPP = {
        _, event, context in
        guard let event, let context else { return OSStatus(eventNotHandledErr) }

        var identifier = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &identifier
        )
        guard status == noErr else { return status }

        let manager = Unmanaged<GlobalHotKeyManager>
            .fromOpaque(context)
            .takeUnretainedValue()
        MainActor.assumeIsolated {
            manager.handlePressedHotKey(identifier)
        }
        return noErr
    }
}
