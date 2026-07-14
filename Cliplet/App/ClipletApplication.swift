import AppKit
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
    private var settingsWindow: NSWindow?
    private var viewModel: ClipletViewModel?
    #if DEBUG
    private var debugPreviewWindow: NSWindow?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            configureMainMenu()
            NSApplication.shared.applicationIconImage = NSImage(named: "NimclipAppIcon")
            let store = try ClipboardStore()
            let viewModel = ClipletViewModel(store: store)
            self.viewModel = viewModel
            configureStatusItem()
            configurePopover(with: viewModel)

            viewModel.onShowRequested = { [weak self] in self?.showPopover() }
            viewModel.onDismissRequested = { [weak self] in self?.closePopover() }
            viewModel.onOpenSettingsRequested = { [weak self] in self?.showSettings() }
            viewModel.onStatusChanged = { [weak self] isPaused in
                self?.updateStatusItem(isPaused: isPaused)
            }

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
            alert.messageText = "Nimclip 无法启动"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "退出")
            alert.runModal()
            NSApplication.shared.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
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
            title: "关于 Nimclip",
            action: #selector(showAboutFromMenu),
            keyEquivalent: ""
        )
        aboutItem.target = self
        applicationMenu.addItem(aboutItem)

        let settingsItem = NSMenuItem(
            title: "设置…",
            action: #selector(showSettingsFromMenu),
            keyEquivalent: ","
        )
        settingsItem.target = self
        applicationMenu.addItem(settingsItem)
        applicationMenu.addItem(.separator())

        let servicesItem = NSMenuItem(title: "服务", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "服务")
        servicesItem.submenu = servicesMenu
        applicationMenu.addItem(servicesItem)
        NSApplication.shared.servicesMenu = servicesMenu
        applicationMenu.addItem(.separator())

        applicationMenu.addItem(
            withTitle: "隐藏 Nimclip",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        let hideOthersItem = applicationMenu.addItem(
            withTitle: "隐藏其他应用",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        applicationMenu.addItem(
            withTitle: "全部显示",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(
            withTitle: "退出 Nimclip",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "编辑")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = editMenu.addItem(
            withTitle: "重做",
            action: Selector(("redo:")),
            keyEquivalent: "z"
        )
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "窗口")
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(
            withTitle: "最小化",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        windowMenu.addItem(
            withTitle: "缩放",
            action: #selector(NSWindow.performZoom(_:)),
            keyEquivalent: ""
        )
        windowMenu.addItem(.separator())
        windowMenu.addItem(
            withTitle: "前置全部窗口",
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
        statusItem?.button?.toolTip = isPaused ? "Nimclip 已暂停" : "Nimclip · ⌘⇧V"
    }

    private func makeStatusImage() -> NSImage? {
        guard let source = NSImage(named: NSImage.Name("NimclipMenuBar")),
              let image = source.copy() as? NSImage else {
            return nil
        }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        image.accessibilityDescription = "打开 Nimclip"
        return image
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
