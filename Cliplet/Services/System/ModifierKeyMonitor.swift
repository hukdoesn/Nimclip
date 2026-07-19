import AppKit
import CoreGraphics
import Foundation
import Observation

private final class ModifierKeyPhysicalStateMonitor: @unchecked Sendable {
    private let queue = DispatchQueue(
        label: "com.nimclip.modifier-key-state",
        qos: .userInteractive
    )
    private var timer: DispatchSourceTimer?
    private var lastIsOptionPressed: Bool?
    private let onStateChange: @Sendable (Bool) -> Void

    init(onStateChange: @escaping @Sendable (Bool) -> Void) {
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
                repeating: .milliseconds(30),
                leeway: .milliseconds(5)
            )
            timer.setEventHandler { [weak self] in
                self?.poll()
            }
            self.timer = timer
            timer.resume()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self, let timer else { return }
            timer.setEventHandler {}
            timer.cancel()
            self.timer = nil
            lastIsOptionPressed = nil
        }
    }

    private func poll() {
        let isPressed = Self.currentOptionIsPressed
        guard isPressed != lastIsOptionPressed else { return }
        lastIsOptionPressed = isPressed
        onStateChange(isPressed)
    }

    static var currentOptionIsPressed: Bool {
        CGEventSource.flagsState(.combinedSessionState)
            .contains(.maskAlternate)
    }
}

@MainActor
@Observable
final class ModifierKeyMonitor {
    static let optionKeyStateDidChange = Notification.Name(
        "com.nimclip.option-key-state-did-change"
    )
    static let isPressedUserInfoKey = "isPressed"

    @ObservationIgnored private var localMonitor: Any?
    @ObservationIgnored private var physicalStateMonitor: ModifierKeyPhysicalStateMonitor?
    private(set) var isOptionPressed = false

    func start() {
        guard localMonitor == nil, physicalStateMonitor == nil else { return }
        updateOptionState(
            ModifierKeyPhysicalStateMonitor.currentOptionIsPressed
        )
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .flagsChanged
        ) { [weak self] event in
            MainActor.assumeIsolated {
                self?.updateOptionState(
                    Self.optionIsPressed(in: event.modifierFlags)
                )
            }
            return event
        }
        let physicalStateMonitor = ModifierKeyPhysicalStateMonitor {
            [weak self] isPressed in
            Task { @MainActor [weak self] in
                self?.updateOptionState(isPressed)
            }
        }
        self.physicalStateMonitor = physicalStateMonitor
        physicalStateMonitor.start()
    }

    func stop() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        physicalStateMonitor?.stop()
        physicalStateMonitor = nil
        updateOptionState(false)
    }

    static func optionIsPressed(
        in modifierFlags: NSEvent.ModifierFlags
    ) -> Bool {
        modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .contains(.option)
    }

    static func optionIsPressed(
        in modifierFlags: NSEvent.ModifierFlags,
        physicalStateIsPressed: Bool
    ) -> Bool {
        optionIsPressed(in: modifierFlags) || physicalStateIsPressed
    }

    static var isOptionPhysicallyPressed: Bool {
        ModifierKeyPhysicalStateMonitor.currentOptionIsPressed
    }

    static var isOptionPressedNow: Bool {
        optionIsPressed(
            in: NSEvent.modifierFlags,
            physicalStateIsPressed: isOptionPhysicallyPressed
        )
    }

    private func updateOptionState(_ isPressed: Bool) {
        guard isPressed != isOptionPressed else { return }
        isOptionPressed = isPressed
        NotificationCenter.default.post(
            name: Self.optionKeyStateDidChange,
            object: self,
            userInfo: [Self.isPressedUserInfoKey: isPressed]
        )
    }
}
