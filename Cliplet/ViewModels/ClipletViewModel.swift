import AppKit
import Carbon.HIToolbox
import Foundation
import ImageIO
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class ClipletViewModel {
    enum Section: String, CaseIterable, Identifiable {
        case history
        case favorites

        var id: Self { self }
    }

    var searchText = "" {
        didSet { rebuildVisibleItems() }
    }
    var selectedSection: Section = .history {
        didSet { rebuildVisibleItems() }
    }
    var selectedContentFilter: ClipboardContentFilter = .all {
        didSet { rebuildVisibleItems() }
    }
    var selectedTagID: UUID? {
        didSet { rebuildVisibleItems() }
    }
    var selectedItemID: UUID?
    private(set) var visibleItems: [ClipboardItem] = []
    private(set) var timestampReferenceDate = Date()
    private(set) var isPaused = false
    private(set) var toastMessage: String?
    private(set) var isRecordingHotKey = false
    private(set) var hotKeyErrorMessage: String?

    var onShowRequested: (() -> Void)?
    var onDismissRequested: (() -> Void)?
    var onOpenSettingsRequested: (() -> Void)?
    var onStatusChanged: ((Bool) -> Void)?

    private let store: ClipboardStore
    private let monitor: ClipboardMonitor
    private let pasteCoordinator: PasteCoordinator
    private let launchAtLoginManager: LaunchAtLoginManager
    private var hotKeyManager: GlobalHotKeyManager?
    private var hotKeyMonitor: Any?
    private var toastTask: Task<Void, Never>?
    private var revision = 0 {
        didSet { rebuildVisibleItems() }
    }
    @ObservationIgnored private var presentationKindCache: [String: ClipboardPresentationKind] = [:]

    init(
        store: ClipboardStore,
        monitor: ClipboardMonitor = ClipboardMonitor(),
        pasteCoordinator: PasteCoordinator = PasteCoordinator(),
        launchAtLoginManager: LaunchAtLoginManager = LaunchAtLoginManager()
    ) {
        self.store = store
        self.monitor = monitor
        self.pasteCoordinator = pasteCoordinator
        self.launchAtLoginManager = launchAtLoginManager
        rebuildVisibleItems()

        monitor.onCapture = { [weak self] capture in
            self?.ingest(capture)
        }
        monitor.start()

        configureHotKey(
            GlobalHotKeyShortcut(
                keyCode: store.settings.hotKeyKeyCode,
                modifiers: store.settings.hotKeyModifiers
            ),
            persist: false
        )
    }

    var items: [ClipboardItem] { visibleItems }

    var tags: [ClipTag] {
        _ = revision
        return store.tags
    }

    var settings: AppSettings {
        _ = revision
        return store.settings
    }

    var statusText: String {
        if isPaused { return "记录已暂停" }
        if items.isEmpty { return searchText.isEmpty ? "暂无记录" : "没有匹配结果" }
        return "\(items.count) 条记录"
    }

    var historyLimit: Int {
        get {
            _ = revision
            return store.settings.historyLimit
        }
        set {
            perform { try store.updateSettings(historyLimit: newValue) }
        }
    }

    var retentionDays: Int {
        get {
            _ = revision
            return store.settings.retentionDays
        }
        set {
            perform { try store.updateSettings(retentionDays: newValue) }
        }
    }

    var launchAtLogin: Bool {
        get {
            _ = revision
            return store.settings.launchAtLogin
        }
        set {
            do {
                try launchAtLoginManager.setEnabled(newValue)
                try store.updateSettings(launchAtLogin: newValue)
                revision += 1
                if launchAtLoginManager.status == .requiresApproval {
                    showToast("请在系统设置中允许 Nimclip 登录时启动")
                }
            } catch {
                showToast(error.localizedDescription)
                revision += 1
            }
        }
    }

    var hotKeyDisplay: String {
        hotKeyDisplayParts.joined()
    }

    var hotKeyDisplayParts: [String] {
        _ = revision
        let shortcut = hotKeyManager?.shortcut ?? GlobalHotKeyShortcut(
            keyCode: store.settings.hotKeyKeyCode,
            modifiers: store.settings.hotKeyModifiers
        )
        return Self.displayParts(for: shortcut)
    }

    var accessibilityStatusText: String {
        PasteCoordinator.isAccessibilityTrusted() ? "已允许直接粘贴" : "未授权时仅复制"
    }

    func thumbnailURL(for item: ClipboardItem) -> URL? {
        store.thumbnailURL(for: item)
    }

    func imageURL(for item: ClipboardItem) -> URL? {
        store.imageURL(for: item)
    }

    func togglePause() {
        isPaused.toggle()
        if isPaused {
            monitor.stop()
            showToast("已暂停记录剪贴板")
        } else {
            monitor.start()
            showToast("已恢复记录")
        }
        onStatusChanged?(isPaused)
    }

    func prepareToShow() {
        timestampReferenceDate = Date()
        pasteCoordinator.rememberFrontmostApplication()
        rebuildVisibleItems()
        ensureValidSelection()
    }

    func presentationKind(for item: ClipboardItem) -> ClipboardPresentationKind {
        if let cached = presentationKindCache[item.contentHash] {
            return cached
        }
        let kind = ClipboardPresentationKind.classify(kind: item.kind, text: item.text)
        presentationKindCache[item.contentHash] = kind
        return kind
    }

    func requestShow() {
        prepareToShow()
        onShowRequested?()
    }

    func dismiss() {
        onDismissRequested?()
    }

    func openSettings() {
        onOpenSettingsRequested?()
    }

    func openAccessibilitySettings() {
        PasteCoordinator.openAccessibilitySystemSettings()
    }

    func openLoginItemsSettings() {
        launchAtLoginManager.openSystemSettings()
    }

    func selectPrevious() {
        moveSelection(by: -1)
    }

    func selectNext() {
        moveSelection(by: 1)
    }

    func refreshSelection() {
        ensureValidSelection()
    }

    func pasteSelected() {
        guard let item = selectedItem ?? items.first else { return }
        paste(item)
    }

    func pasteSelectedItem() {
        pasteSelected()
    }

    func deleteSelectedItem() {
        guard let item = selectedItem else { return }
        delete(item)
    }

    func dismissToast() {
        toastTask?.cancel()
        toastMessage = nil
    }

    func paste(_ item: ClipboardItem) {
        guard let payload = payload(for: item) else {
            showToast("原始内容已不可用")
            return
        }

        paste(payload)
    }

    func pasteAsPlainText(_ item: ClipboardItem) {
        guard let text = item.text else {
            showToast("这条记录没有可用文本")
            return
        }
        paste(.text(text))
    }

    func copyAsPlainText(_ item: ClipboardItem) {
        guard let text = item.text else {
            showToast("这条记录没有可用文本")
            return
        }
        copy(.text(text), success: "已复制纯文本")
    }

    func openLink(_ item: ClipboardItem) {
        guard presentationKind(for: item) == .link,
              let text = item.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = resolvedURL(from: text),
              NSWorkspace.shared.open(url) else {
            showToast("无法打开这个链接")
            return
        }
        showToast("已打开链接")
    }

    func combinedText(for itemIDs: [UUID]) -> String? {
        let texts = itemIDs.compactMap { id -> String? in
            guard let text = store.items.first(where: { $0.id == id })?.text else {
                return nil
            }
            let value = text.trimmingCharacters(in: .newlines)
            return value.isEmpty ? nil : value
        }
        guard !texts.isEmpty else { return nil }
        return texts.joined(separator: "\n")
    }

    func copyCombined(_ itemIDs: [UUID]) {
        guard let text = combinedText(for: itemIDs) else {
            showToast("请先选择要拼贴的文本")
            return
        }
        copy(.text(text), success: "已复制 \(itemIDs.count) 条拼贴内容")
    }

    func pasteCombined(_ itemIDs: [UUID]) {
        guard let text = combinedText(for: itemIDs) else {
            showToast("请先选择要拼贴的文本")
            return
        }
        paste(.text(text))
    }

    func showNotice(_ message: String) {
        showToast(message)
    }

    private func paste(_ payload: ClipboardPastePayload) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let result = try await pasteCoordinator.paste(payload) { [weak self] in
                    self?.onDismissRequested?()
                }
                switch result {
                case .pasted:
                    showToast("已粘贴")
                case .copiedOnly:
                    showToast("已复制；允许辅助功能权限后可直接粘贴")
                }
            } catch {
                showToast(error.localizedDescription)
            }
        }
    }

    func copy(_ item: ClipboardItem) {
        guard let payload = payload(for: item) else {
            showToast("原始内容已不可用")
            return
        }
        copy(payload, success: "已复制到剪贴板")
    }

    func toggleFavorite(_ item: ClipboardItem) {
        perform(success: item.isFavorite ? "已取消收藏" : "已加入收藏") {
            try store.toggleFavorite(item)
        }
    }

    func delete(_ item: ClipboardItem) {
        let deletedID = item.id
        perform(success: "已删除") {
            try store.delete(item)
        }
        if selectedItemID == deletedID {
            selectedItemID = items.first?.id
        }
    }

    func toggleTag(_ tag: ClipTag, on item: ClipboardItem) {
        perform {
            try store.toggle(tag, on: item)
        }
    }

    func createTag(name: String, colorHex: String = "2F343A") {
        perform(success: "标签已创建") {
            try store.createTag(name: name, colorHex: colorHex)
        }
    }

    func renameTag(_ tag: ClipTag, to name: String) {
        perform {
            try store.renameTag(tag, to: name)
        }
    }

    func deleteTag(_ tag: ClipTag) {
        let deletedID = tag.id
        perform(success: "标签已删除") {
            try store.deleteTag(tag)
        }
        if selectedTagID == deletedID {
            selectedTagID = nil
        }
    }

    func clearHistory() {
        perform(success: "历史记录已清空") {
            try store.clearHistory(includingFavorites: false)
        }
        selectedItemID = items.first?.id
    }

    func beginHotKeyRecording() {
        guard hotKeyMonitor == nil else {
            cancelHotKeyRecording()
            return
        }
        isRecordingHotKey = true
        hotKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard let self else { return event }
            if event.keyCode == UInt16(kVK_Escape) {
                cancelHotKeyRecording()
                return nil
            }

            let modifiers = Self.carbonModifiers(from: event.modifierFlags)
            guard modifiers != 0 else {
                showToast("快捷键至少需要一个修饰键")
                return nil
            }

            let shortcut = GlobalHotKeyShortcut(
                keyCode: UInt32(event.keyCode),
                modifiers: modifiers
            )
            configureHotKey(shortcut, persist: true)
            cancelHotKeyRecording()
            return nil
        }
    }

    func cancelHotKeyRecording() {
        if let hotKeyMonitor {
            NSEvent.removeMonitor(hotKeyMonitor)
            self.hotKeyMonitor = nil
        }
        isRecordingHotKey = false
    }

    func terminateApplication() {
        NSApplication.shared.terminate(nil)
    }

    func shutdown() {
        monitor.stop()
        cancelHotKeyRecording()
    }

    private var selectedItem: ClipboardItem? {
        guard let selectedItemID else { return nil }
        return items.first { $0.id == selectedItemID }
    }

    private func ingest(_ capture: ClipboardCapture) {
        guard !capture.didOmitRepresentations else {
            showToast("原始格式过大或无法完整读取，本次未记录")
            return
        }

        do {
            switch capture.content {
            case let .text(text, archive):
                try store.ingestText(
                    text,
                    archive: archive,
                    sourceAppBundleIdentifier: capture.sourceApplication.bundleIdentifier,
                    sourceAppName: capture.sourceApplication.name
                )
            case let .image(data, typeIdentifier, archive):
                try store.ingestImage(
                    data,
                    typeIdentifier: typeIdentifier,
                    archive: archive,
                    sourceAppBundleIdentifier: capture.sourceApplication.bundleIdentifier,
                    sourceAppName: capture.sourceApplication.name
                )
            }
            revision += 1
            ensureValidSelection()
        } catch ClipboardStoreError.emptyText {
            // Empty clipboard strings are intentionally ignored.
        } catch {
            showToast(error.localizedDescription)
        }
    }

    private func payload(for item: ClipboardItem) -> ClipboardPastePayload? {
        if let archive = store.pasteboardArchive(for: item) {
            return .archive(archive)
        }

        switch item.kind {
        case .text:
            guard let text = item.text else { return nil }
            return .text(text)
        case .image:
            guard let data = store.imageData(for: item) else { return nil }
            let typeIdentifier: String
            if let storedType = item.imageTypeIdentifier {
                typeIdentifier = storedType
            } else if let source = CGImageSourceCreateWithData(data as CFData, nil),
               let type = CGImageSourceGetType(source) {
                typeIdentifier = type as String
            } else {
                typeIdentifier = UTType.png.identifier
            }
            return .image(data: data, typeIdentifier: typeIdentifier)
        }
    }

    private func copy(_ payload: ClipboardPastePayload, success: String) {
        do {
            try pasteCoordinator.copy(payload)
            showToast(success)
        } catch {
            showToast(error.localizedDescription)
        }
    }

    private func resolvedURL(from text: String) -> URL? {
        if text.lowercased().hasPrefix("www.") {
            return URL(string: "https://\(text)")
        }
        return URL(string: text)
    }

    private func moveSelection(by offset: Int) {
        guard !items.isEmpty else {
            selectedItemID = nil
            return
        }
        guard let selectedItemID,
              let index = items.firstIndex(where: { $0.id == selectedItemID }) else {
            self.selectedItemID = items.first?.id
            return
        }
        let nextIndex = min(max(index + offset, 0), items.count - 1)
        self.selectedItemID = items[nextIndex].id
    }

    private func ensureValidSelection() {
        if let selectedItemID, items.contains(where: { $0.id == selectedItemID }) {
            return
        }
        selectedItemID = items.first?.id
    }

    private func rebuildVisibleItems() {
        let selectedTag = store.tags.first { $0.id == selectedTagID }
        let filteredItems = store.filteredItems(
            searchText: searchText,
            favoritesOnly: selectedSection == .favorites,
            tag: selectedTag
        )
        if selectedContentFilter == .all {
            visibleItems = filteredItems
        } else {
            visibleItems = filteredItems.filter {
                selectedContentFilter.includes(presentationKind(for: $0))
            }
        }
    }

    private func configureHotKey(_ shortcut: GlobalHotKeyShortcut, persist: Bool) {
        do {
            if let hotKeyManager {
                try hotKeyManager.reconfigure(to: shortcut)
            } else {
                let manager = try GlobalHotKeyManager(shortcut: shortcut)
                manager.onTrigger = { [weak self] in
                    self?.requestShow()
                }
                hotKeyManager = manager
            }
            if persist {
                try store.updateSettings(
                    hotKeyKeyCode: shortcut.keyCode,
                    hotKeyModifiers: shortcut.modifiers
                )
                showToast("快捷键已更新")
            }
            hotKeyErrorMessage = nil
            revision += 1
        } catch {
            hotKeyErrorMessage = error.localizedDescription
            showToast(error.localizedDescription)
        }
    }

    private func perform(success: String? = nil, _ operation: () throws -> Void) {
        do {
            try operation()
            revision += 1
            ensureValidSelection()
            if let success { showToast(success) }
        } catch {
            showToast(error.localizedDescription)
        }
    }

    private func showToast(_ message: String) {
        toastTask?.cancel()
        toastMessage = message
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            self?.toastMessage = nil
        }
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var value: UInt32 = 0
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) { value |= UInt32(cmdKey) }
        if flags.contains(.shift) { value |= UInt32(shiftKey) }
        if flags.contains(.option) { value |= UInt32(optionKey) }
        if flags.contains(.control) { value |= UInt32(controlKey) }
        return value
    }

    private static func displayParts(for shortcut: GlobalHotKeyShortcut) -> [String] {
        var result: [String] = []
        if shortcut.modifiers & UInt32(controlKey) != 0 { result.append("⌃") }
        if shortcut.modifiers & UInt32(optionKey) != 0 { result.append("⌥") }
        if shortcut.modifiers & UInt32(shiftKey) != 0 { result.append("⇧") }
        if shortcut.modifiers & UInt32(cmdKey) != 0 { result.append("⌘") }
        result.append(keyName(for: shortcut.keyCode))
        return result
    }

    private static func keyName(for keyCode: UInt32) -> String {
        let names: [UInt32: String] = [
            UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B",
            UInt32(kVK_ANSI_C): "C", UInt32(kVK_ANSI_D): "D",
            UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
            UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H",
            UInt32(kVK_ANSI_I): "I", UInt32(kVK_ANSI_J): "J",
            UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
            UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N",
            UInt32(kVK_ANSI_O): "O", UInt32(kVK_ANSI_P): "P",
            UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
            UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T",
            UInt32(kVK_ANSI_U): "U", UInt32(kVK_ANSI_V): "V",
            UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
            UInt32(kVK_Space): "Space", UInt32(kVK_Return): "Return",
            UInt32(kVK_Tab): "Tab", UInt32(kVK_Delete): "Delete"
        ]
        return names[keyCode] ?? "Key \(keyCode)"
    }
}
