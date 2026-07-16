import AppKit
import QuartzCore
import SwiftUI

@main
enum ClipletApplication {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = ClipletAppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}

@MainActor
final class ClipletAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let previewPanelController = ClipletPreviewPanelController()
    private let settingsNavigation = NimclipSettingsNavigation()
    private let updateChecker = NimclipUpdateChecker()
    private var settingsWindow: NSWindow?
    private var viewModel: ClipletViewModel?
    private var automaticUpdateTask: Task<Void, Never>?
    private var isCheckingForUpdates = false
    #if DEBUG
    private var debugPreviewWindow: NSWindow?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            NSApplication.shared.applicationIconImage = NSImage(named: "NimclipAppIcon")
            let store = try ClipboardStore()
            let viewModel = ClipletViewModel(store: store)
            self.viewModel = viewModel
            configureMainMenu()
            applyAppearance(viewModel.appearanceMode, animated: false)
            configureStatusItem()
            configurePopover(with: viewModel)

            viewModel.onShowRequested = { [weak self] in self?.showPopover() }
            viewModel.onDismissRequested = { [weak self] in self?.closePopover() }
            viewModel.onOpenSettingsRequested = { [weak self] in self?.showSettings() }
            viewModel.onStatusChanged = { [weak self] isPaused in
                self?.updateStatusItem(isPaused: isPaused)
            }
            viewModel.onAppearanceChanged = { [weak self] mode in
                self?.applyAppearance(mode, animated: true)
            }
            viewModel.onLanguageChanged = { [weak self] language in
                self?.applyLanguage(language)
            }

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(checkForUpdatesRequested),
                name: .nimclipCheckForUpdatesRequested,
                object: nil
            )
            scheduleAutomaticUpdateChecks()

            #if DEBUG
            if ProcessInfo.processInfo.environment["CLIPLET_PREVIEW_WINDOW"] == "1" {
                DispatchQueue.main.async { [weak self] in
                    self?.showDebugPreview(with: viewModel)
                }
            } else if ProcessInfo.processInfo.environment["CLIPLET_SHOW_ON_LAUNCH"] == "1" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                    self?.showPopover()
                }
            }
            #endif
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = NimclipLanguage.defaultLanguage.localized("Nimclip 无法启动")
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: NimclipLanguage.defaultLanguage.localized("退出"))
            alert.runModal()
            NSApplication.shared.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        automaticUpdateTask?.cancel()
        NotificationCenter.default.removeObserver(self)
        previewPanelController.hide()
        viewModel?.shutdown()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === settingsWindow else { return }
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()

        let applicationMenuItem = NSMenuItem()
        mainMenu.addItem(applicationMenuItem)
        let applicationMenu = NSMenu(title: "Nimclip")
        applicationMenuItem.submenu = applicationMenu

        let aboutItem = NSMenuItem(
            title: localized("关于 Nimclip"),
            action: #selector(showAboutFromMenu),
            keyEquivalent: ""
        )
        aboutItem.target = self
        applicationMenu.addItem(aboutItem)

        let updateItem = NSMenuItem(
            title: localized("检查更新…"),
            action: #selector(checkForUpdatesFromMenu),
            keyEquivalent: ""
        )
        updateItem.target = self
        applicationMenu.addItem(updateItem)

        let settingsItem = NSMenuItem(
            title: localized("设置…"),
            action: #selector(showSettingsFromMenu),
            keyEquivalent: ","
        )
        settingsItem.target = self
        applicationMenu.addItem(settingsItem)
        applicationMenu.addItem(.separator())

        let servicesItem = NSMenuItem(title: localized("服务"), action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: localized("服务"))
        servicesItem.submenu = servicesMenu
        applicationMenu.addItem(servicesItem)
        NSApplication.shared.servicesMenu = servicesMenu
        applicationMenu.addItem(.separator())

        applicationMenu.addItem(
            withTitle: localized("隐藏 Nimclip"),
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        let hideOthersItem = applicationMenu.addItem(
            withTitle: localized("隐藏其他应用"),
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        applicationMenu.addItem(
            withTitle: localized("全部显示"),
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(
            withTitle: localized("退出 Nimclip"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: localized("编辑"))
        editMenuItem.submenu = editMenu
        editMenu.addItem(
            withTitle: localized("撤销"),
            action: Selector(("undo:")),
            keyEquivalent: "z"
        )
        let redoItem = editMenu.addItem(
            withTitle: localized("重做"),
            action: Selector(("redo:")),
            keyEquivalent: "z"
        )
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: localized("剪切"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: localized("复制"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: localized("粘贴"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: localized("全选"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: localized("窗口"))
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(
            withTitle: localized("最小化"),
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        windowMenu.addItem(
            withTitle: localized("缩放"),
            action: #selector(NSWindow.performZoom(_:)),
            keyEquivalent: ""
        )
        windowMenu.addItem(.separator())
        windowMenu.addItem(
            withTitle: localized("前置全部窗口"),
            action: #selector(NSApplication.arrangeInFront(_:)),
            keyEquivalent: ""
        )
        NSApplication.shared.windowsMenu = windowMenu
        NSApplication.shared.mainMenu = mainMenu
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = makeStatusImage()
            button.target = self
            button.action = #selector(togglePopover)
            button.toolTip = "Nimclip · ⌘⇧V"
        }
        statusItem = item
    }

    private func configurePopover(with viewModel: ClipletViewModel) {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 440, height: 600)
        popover.contentViewController = NSHostingController(
            rootView: makeMenuRootView(with: viewModel)
        )
    }

    @objc
    private func togglePopover() {
        if popover.isShown {
            closePopover()
        } else {
            viewModel?.prepareToShow()
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem?.button else { return }
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func closePopover() {
        previewPanelController.hide()
        popover.performClose(nil)
    }

    private func applyAppearance(
        _ mode: NimclipAppearanceMode,
        animated: Bool
    ) {
        let appearance = mode.appearance
        var views = [
            popover.contentViewController?.view,
            settingsWindow?.contentView,
            previewPanelController.panel?.contentView
        ].compactMap { $0 }
        #if DEBUG
        if let debugView = debugPreviewWindow?.contentView {
            views.append(debugView)
        }
        #endif

        if animated {
            for view in views {
                view.wantsLayer = true
                let transition = CATransition()
                transition.type = .fade
                transition.duration = 0.18
                transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                view.layer?.add(transition, forKey: "nimclip.appearance")
            }
        }

        NSApplication.shared.appearance = appearance
        popover.contentViewController?.view.appearance = appearance
        popover.contentViewController?.view.window?.appearance = appearance
        settingsWindow?.appearance = appearance
        previewPanelController.applyAppearance(appearance)
        #if DEBUG
        debugPreviewWindow?.appearance = appearance
        #endif
    }

    private func makeMenuRootView(with viewModel: ClipletViewModel) -> MenuBarRootView {
        MenuBarRootView(viewModel: viewModel) { [weak self] item in
            guard let self else { return }
            guard let item else {
                previewPanelController.requestHide()
                return
            }

            previewPanelController.show(
                item: item,
                imageURL: viewModel.imageURL(for: item),
                thumbnailURL: viewModel.thumbnailURL(for: item),
                referenceDate: viewModel.timestampReferenceDate,
                language: viewModel.language,
                relativeTo: popover.contentViewController?.view.window
            )
        }
    }

    @objc
    private func showSettingsFromMenu() {
        showSettings(pane: .settings)
    }

    @objc
    private func showAboutFromMenu() {
        showSettings(pane: .about)
    }

    @objc
    private func checkForUpdatesFromMenu() {
        requestUpdateCheck(manual: true)
    }

    @objc
    private func checkForUpdatesRequested(_ notification: Notification) {
        requestUpdateCheck(manual: true)
    }

    private func requestUpdateCheck(manual: Bool) {
        Task { @MainActor [weak self] in
            await self?.checkForUpdates(manual: manual)
        }
    }

    private func scheduleAutomaticUpdateChecks() {
        automaticUpdateTask?.cancel()
        automaticUpdateTask = Task { @MainActor [weak self] in
            try? await Task.sleep(
                for: NimclipAutomaticUpdateSchedule.initialDelay
            )
            guard !Task.isCancelled else { return }

            while !Task.isCancelled {
                await self?.checkForUpdates(manual: false)
                try? await Task.sleep(
                    for: NimclipAutomaticUpdateSchedule.checkInterval
                )
            }
        }
    }

    private func checkForUpdates(manual: Bool) async {
        guard !isCheckingForUpdates else { return }
        isCheckingForUpdates = true
        defer { isCheckingForUpdates = false }

        do {
            if let update = try await updateChecker.check() {
                guard manual || shouldShowAutomaticReminder(for: update.version) else {
                    return
                }
                showUpdateAlert(update)
            } else if manual {
                showInformationAlert(
                    title: localized("已经是最新版本"),
                    message: localizedFormat(
                        "当前版本为 Nimclip %@。",
                        NimclipBuildInfo.version
                    )
                )
            }
        } catch {
            guard manual else { return }
            showInformationAlert(
                title: localized("暂时无法检查更新"),
                message: localizedDescription(for: error)
            )
        }
    }

    private func shouldShowAutomaticReminder(for version: String) -> Bool {
        let defaults = UserDefaults.standard
        let savedVersion = defaults.string(forKey: Self.remindedVersionKey)
        let savedDate = defaults.object(forKey: Self.remindedDateKey) as? Date
        let canRemindAgain = savedDate.map {
            Date().timeIntervalSince($0) >= Self.reminderCooldown
        } ?? true

        guard savedVersion != version || canRemindAgain else { return false }
        defaults.set(version, forKey: Self.remindedVersionKey)
        defaults.set(Date(), forKey: Self.remindedDateKey)
        return true
    }

    private func showUpdateAlert(_ update: NimclipAvailableUpdate) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = localizedFormat("Nimclip %@ 可用", update.version)
        alert.informativeText = localizedFormat(
            "当前版本为 %@。升级不会清除保存在这台 Mac 上的历史记录。",
            NimclipBuildInfo.version
        )
        alert.addButton(withTitle: localized("前往下载"))
        alert.addButton(withTitle: localized("稍后提醒"))
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(update.releaseURL)
        }
    }

    private func showInformationAlert(title: String, message: String) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: localized("好"))
        alert.runModal()
    }

    private static let remindedVersionKey = "NimclipLastRemindedUpdateVersion"
    private static let remindedDateKey = "NimclipLastRemindedUpdateDate"
    private static let reminderCooldown: TimeInterval = 24 * 60 * 60

    private func showSettings(pane: NimclipSettingsPane = .settings) {
        closePopover()
        guard let viewModel else { return }

        settingsNavigation.selectedPane = pane
        NSApplication.shared.setActivationPolicy(.regular)

        if settingsWindow == nil {
            let controller = NSHostingController(
                rootView: SettingsView(
                    viewModel: viewModel,
                    navigation: settingsNavigation
                )
            )
            let window = NSWindow(contentViewController: controller)
            window.title = "Nimclip"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setContentSize(NSSize(width: 660, height: 520))
            window.titlebarSeparatorStyle = .none
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            settingsWindow = window
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func updateStatusItem(isPaused: Bool) {
        statusItem?.button?.image = makeStatusImage()
        statusItem?.button?.alphaValue = isPaused ? 0.45 : 1
        statusItem?.button?.toolTip = isPaused
            ? localized("Nimclip 已暂停")
            : "Nimclip · ⌘⇧V"
    }

    private func makeStatusImage() -> NSImage? {
        guard let source = NSImage(named: NSImage.Name("NimclipMenuBar")),
              let image = source.copy() as? NSImage else {
            return nil
        }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        image.accessibilityDescription = localized("打开 Nimclip")
        return image
    }

    private var language: NimclipLanguage {
        viewModel?.language ?? .defaultLanguage
    }

    private func localized(_ key: String) -> String {
        language.localized(key)
    }

    private func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
        String(
            format: language.localized(key),
            locale: language.locale,
            arguments: arguments
        )
    }

    private func localizedDescription(for error: Error) -> String {
        if let error = error as? NimclipUpdateCheckError {
            return error.errorDescription(in: language)
        }
        return error.localizedDescription
    }

    private func applyLanguage(_ language: NimclipLanguage) {
        configureMainMenu()
        updateStatusItem(isPaused: viewModel?.isPaused ?? false)
        previewPanelController.hide()
    }

    #if DEBUG
    private func showDebugPreview(with viewModel: ClipletViewModel) {
        let controller = NSHostingController(rootView: makeMenuRootView(with: viewModel))
        let window = NSWindow(contentViewController: controller)
        window.title = "Nimclip Preview"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 440, height: 600))
        window.isReleasedWhenClosed = false
        window.center()
        debugPreviewWindow = window
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
    #endif
}
