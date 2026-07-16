import AppKit
import Foundation

@MainActor
final class ModifierKeyMonitor {
    static let optionKeyStateDidChange = Notification.Name(
        "com.nimclip.option-key-state-did-change"
    )
    static let isPressedUserInfoKey = "isPressed"

    private var localMonitor: Any?
    private var isOptionPressed = false

    func start() {
        guard localMonitor == nil else { return }
        updateOptionState(from: NSEvent.modifierFlags)
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .flagsChanged
        ) { [weak self] event in
            MainActor.assumeIsolated {
                self?.updateOptionState(from: event.modifierFlags)
            }
            return event
        }
    }

    func stop() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        isOptionPressed = false
    }

    static func optionIsPressed(
        in modifierFlags: NSEvent.ModifierFlags
    ) -> Bool {
        modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .contains(.option)
    }

    private func updateOptionState(
        from modifierFlags: NSEvent.ModifierFlags
    ) {
        let newValue = Self.optionIsPressed(in: modifierFlags)
        guard newValue != isOptionPressed else { return }
        isOptionPressed = newValue
        NotificationCenter.default.post(
            name: Self.optionKeyStateDidChange,
            object: self,
            userInfo: [Self.isPressedUserInfoKey: newValue]
        )
    }
}
