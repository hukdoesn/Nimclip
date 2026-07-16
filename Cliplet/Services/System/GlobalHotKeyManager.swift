import Carbon.HIToolbox
import CoreGraphics
import Foundation

private final class GlobalHotKeyPhysicalStateMonitor: @unchecked Sendable {
    typealias StateChangeHandler = @Sendable (Bool) -> Void

    private let queue = DispatchQueue(
        label: "com.nimclip.hotkey-state",
        qos: .userInteractive
    )
    private var timer: DispatchSourceTimer?
    private var shortcut: GlobalHotKeyShortcut
    private var lastIsPressed = false
    private let onStateChange: StateChangeHandler

    init(
        shortcut: GlobalHotKeyShortcut,
        onStateChange: @escaping StateChangeHandler
    ) {
        self.shortcut = shortcut
        self.onStateChange = onStateChange
    }

    deinit {
        timer?.setEventHandler {}
        timer?.cancel()
    }

    func start() {
        queue.async { [weak self] in
            guard let self, timer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(
                deadline: .now(),
                repeating: .milliseconds(25),
                leeway: .milliseconds(5)
            )
            timer.setEventHandler { [weak self] in
                self?.poll()
            }
            self.timer = timer
            timer.resume()
        }
    }

    func update(shortcut: GlobalHotKeyShortcut) {
        queue.async { [weak self] in
            guard let self else { return }
            self.shortcut = shortcut
            if lastIsPressed {
                lastIsPressed = false
                onStateChange(false)
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self, let timer else { return }
            timer.setEventHandler {}
            timer.cancel()
            self.timer = nil
            lastIsPressed = false
        }
    }

    private func poll() {
        let keyIsPressed = CGEventSource.keyState(
            .combinedSessionState,
            key: CGKeyCode(shortcut.keyCode)
        )
        let activeModifiers = Self.carbonModifiers(
            from: CGEventSource.flagsState(.combinedSessionState)
        )
        let isPressed = shortcut.matchesPhysicalState(
            keyIsPressed: keyIsPressed,
            activeModifiers: activeModifiers
        )
        guard isPressed != lastIsPressed else { return }
        lastIsPressed = isPressed
        onStateChange(isPressed)
    }

    private static func carbonModifiers(from flags: CGEventFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.maskCommand) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.maskShift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.maskAlternate) { modifiers |= UInt32(optionKey) }
        if flags.contains(.maskControl) { modifiers |= UInt32(controlKey) }
        return modifiers
    }
}

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

    func matchesPhysicalState(
        keyIsPressed: Bool,
        activeModifiers: UInt32
    ) -> Bool {
        keyIsPressed && activeModifiers == modifiers
    }
}

struct GlobalHotKeyChordLatch {
    private(set) var isPressed = false

    mutating func update(isPressed: Bool) -> Bool {
        guard isPressed else {
            self.isPressed = false
            return false
        }
        guard !self.isPressed else { return false }
        self.isPressed = true
        return true
    }

    mutating func acceptRegisteredHotKeyEvent() -> Bool {
        guard !isPressed else { return false }
        isPressed = true
        return true
    }

    mutating func reset() {
        isPressed = false
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
    private var physicalStateMonitor: GlobalHotKeyPhysicalStateMonitor?
    private var chordLatch = GlobalHotKeyChordLatch()

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

        startPhysicalStateMonitor()
    }

    deinit {
        physicalStateMonitor?.stop()
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
            chordLatch.reset()
            physicalStateMonitor?.update(shortcut: newShortcut)
        } catch {
            hotKeyReference = try? register(previousShortcut)
            chordLatch.reset()
            throw error
        }
    }

    private func startPhysicalStateMonitor() {
        physicalStateMonitor?.stop()
        let monitor = GlobalHotKeyPhysicalStateMonitor(
            shortcut: shortcut
        ) { [weak self] isPressed in
            Task { @MainActor [weak self] in
                self?.handlePhysicalStateChange(isPressed)
            }
        }
        physicalStateMonitor = monitor
        monitor.start()
    }

    private func handlePhysicalStateChange(_ isPressed: Bool) {
        if chordLatch.update(isPressed: isPressed) {
            onTrigger?()
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
        guard chordLatch.acceptRegisteredHotKeyEvent() else { return }
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
