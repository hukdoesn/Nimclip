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
    var listScrollPositionID: UUID?
    private(set) var visibleItems: [ClipboardItem] = []
    private(set) var timestampReferenceDate = Date()
    private(set) var isPaused = false
    private(set) var toastMessage: String?
    private(set) var isRecordingHotKey = false
    private(set) var hotKeyErrorMessage: String?
    private(set) var isIndexingImageText = false
    private(set) var imageTextIndexCompletedCount = 0
    private(set) var imageTextIndexTotalCount = 0
    private(set) var imageTextIndexFailureCount = 0
    private(set) var listPresentationGeneration = 0
    private(set) var selectionScrollGeneration = 0

    var onShowRequested: (() -> Void)?
    var onDismissRequested: (() -> Void)?
    var onOpenSettingsRequested: (() -> Void)?
    var onStatusChanged: ((Bool) -> Void)?
    var onAppearanceChanged: ((NimclipAppearanceMode) -> Void)?
    var onLanguageChanged: ((NimclipLanguage) -> Void)?

    private let store: ClipboardStore
    private let monitor: ClipboardMonitor
    private let pasteCoordinator: PasteCoordinator
    private let launchAtLoginManager: LaunchAtLoginManager
    private let imageTextRecognizer: any ClipboardImageTextRecognizing
    private var hotKeyManager: GlobalHotKeyManager?
    private var hotKeyMonitor: Any?
    private var toastTask: Task<Void, Never>?
    private var immediateClipboardRefreshTask: Task<Void, Never>?
    private var imageTextRecognitionTask: Task<Void, Never>?
    private var queuedImageTextItemIDs: [UUID] = []
    private var queuedImageTextItemIDSet: Set<UUID> = []
    private var imageTextRecognitionGeneration = 0
    private var shouldNotifyWhenImageTextIndexFinishes = false
    private var presentedNewestItemID: UUID?
    private var revision = 0
    @ObservationIgnored private var presentationKindCache: [String: ClipboardPresentationKind] = [:]
    @ObservationIgnored private var textPreviewCache: [String: String] = [:]

    init(
        store: ClipboardStore,
        monitor: ClipboardMonitor = ClipboardMonitor(),
        pasteCoordinator: PasteCoordinator = PasteCoordinator(),
        launchAtLoginManager: LaunchAtLoginManager = LaunchAtLoginManager(),
        imageTextRecognizer: any ClipboardImageTextRecognizing = ClipboardImageTextRecognizer()
    ) {
        self.store = store
        self.monitor = monitor
        self.pasteCoordinator = pasteCoordinator
        self.launchAtLoginManager = launchAtLoginManager
        self.imageTextRecognizer = imageTextRecognizer
        rebuildVisibleItems()
        selectedItemID = visibleItems.first?.id
        listScrollPositionID = selectedItemID
        presentedNewestItemID = selectedItemID

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
        if isPaused { return localized("记录已暂停") }
        if items.isEmpty {
            return localized(searchText.isEmpty ? "暂无记录" : "没有匹配结果")
        }
        return localizedFormat("%d 条记录", items.count)
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
                markStateChanged()
                if launchAtLoginManager.status == .requiresApproval {
                    showToast(localized("请在系统设置中允许 Nimclip 登录时启动"))
                }
            } catch {
                showToast(localizedDescription(for: error))
                markStateChanged()
            }
        }
    }

    var automaticImageTextRecognition: Bool {
        get {
            _ = revision
            return store.settings.automaticImageTextRecognition
        }
        set {
            guard newValue != automaticImageTextRecognition else { return }
            do {
                try store.updateSettings(automaticImageTextRecognition: newValue)
                markStateChanged()
                showToast(
                    localized(
                        newValue
                            ? "已开启自动识别图片文字"
                            : "已关闭自动识别图片文字"
                    )
                )
            } catch {
                showToast(localizedDescription(for: error))
            }
        }
    }

    var unindexedImageCount: Int {
        _ = revision
        return store.unindexedImageItems.count
    }

    var appearanceMode: NimclipAppearanceMode {
        get {
            _ = revision
            return NimclipAppearanceMode(
                rawValue: store.settings.appearanceModeRawValue
            ) ?? .defaultMode
        }
        set {
            guard newValue != appearanceMode else { return }
            do {
                try store.updateSettings(appearanceMode: newValue)
                markStateChanged()
                onAppearanceChanged?(newValue)
                showToast(
                    localizedFormat(
                        "已切换为%@外观",
                        newValue.title(in: language)
                    )
                )
            } catch {
                showToast(localizedDescription(for: error))
            }
        }
    }

    var language: NimclipLanguage {
        get {
            _ = revision
            return NimclipLanguage(
                rawValue: store.settings.languageRawValue
            ) ?? .defaultLanguage
        }
        set {
            guard newValue != language else { return }
            do {
                try store.updateSettings(language: newValue)
                markStateChanged()
                onLanguageChanged?(newValue)
                showToast(
                    newValue.localizedFormat(
                        "已切换为%@",
                        newValue.displayName
                    )
                )
            } catch {
                showToast(localizedDescription(for: error))
            }
        }
    }

    func toggleAppearance() {
        appearanceMode = appearanceMode.opposite
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
        return displayParts(for: shortcut)
    }

    var accessibilityStatusText: String {
        localized(
            PasteCoordinator.isAccessibilityTrusted()
                ? "已允许直接粘贴"
                : "未授权时仅复制"
        )
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
            showToast(localized("已暂停记录剪贴板"))
        } else {
            monitor.start()
            showToast(localized("已恢复记录"))
        }
        onStatusChanged?(isPaused)
    }

    func prepareToShow() {
        prepareForImmediateShow()
        rebuildVisibleItems()
        finishShowing()
    }

    func prepareForImmediateShow() {
        let sourceApplication = ClipboardSourceApplication(
            application: NSWorkspace.shared.frontmostApplication
        )
        pasteCoordinator.rememberFrontmostApplication()
        immediateClipboardRefreshTask?.cancel()
        immediateClipboardRefreshTask = nil
        if !isPaused {
            // A copy immediately followed by the global shortcut can arrive
            // before either its pasteboard change or its promised data is
            // available. Poll once synchronously, then retry in a short burst
            // instead of waiting for the regular 500 ms monitor interval.
            monitor.pollNow(sourceApplication: sourceApplication)
            scheduleImmediateClipboardRefresh(
                sourceApplication: sourceApplication
            )
        }
        resetPresentationToNewest()
    }

    func finishShowing() {
        let currentDate = Date()
        if currentDate.timeIntervalSince(timestampReferenceDate).magnitude >= 60 {
            timestampReferenceDate = currentDate
        }

        let newestItemID = items.first?.id
        if newestItemID != presentedNewestItemID {
            resetPresentationToNewest()
        } else {
            ensureValidSelection()
        }
    }

    func finishDismissing() {
        // Clearing the binding makes the next presentation's newest item a
        // real scroll-position change even when the reusable view is hidden.
        listScrollPositionID = nil
    }

    func presentationKind(for item: ClipboardItem) -> ClipboardPresentationKind {
        if let cached = presentationKindCache[item.contentHash] {
            return cached
        }
        let kind = ClipboardPresentationKind.classify(kind: item.kind, text: item.text)
        presentationKindCache[item.contentHash] = kind
        return kind
    }

    func textPreview(for item: ClipboardItem) -> String {
        let normalized: String
        if let cached = textPreviewCache[item.contentHash] {
            normalized = cached
        } else {
            normalized = String((item.text ?? "").prefix(800))
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            textPreviewCache[item.contentHash] = normalized
        }
        return normalized.isEmpty ? localized("空文本") : normalized
    }

    func requestShow() {
        prepareForImmediateShow()
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

    func indexExistingImageText() {
        let itemIDs = store.unindexedImageItems.map(\.id)
        guard !itemIDs.isEmpty else {
            showToast(localized("所有图片都已建立文字索引"))
            return
        }
        enqueueImageTextRecognition(for: itemIDs, notifyWhenFinished: true)
    }

    func cancelImageTextIndexing() {
        cancelImageTextIndexing(showNotice: true)
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
            showToast(localized("原始内容已不可用"))
            return
        }

        paste(payload)
    }

    func pasteAsPlainText(_ item: ClipboardItem) {
        guard let text = item.text else {
            showToast(localized("这条记录没有可用文本"))
            return
        }
        paste(.text(text))
    }

    func copyAsPlainText(_ item: ClipboardItem) {
        guard let text = item.text else {
            showToast(localized("这条记录没有可用文本"))
            return
        }
        copy(.text(text), success: localized("已复制纯文本"))
    }

    func openLink(_ item: ClipboardItem) {
        guard presentationKind(for: item) == .link,
              let text = item.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = resolvedURL(from: text),
              NSWorkspace.shared.open(url) else {
            showToast(localized("无法打开这个链接"))
            return
        }
        showToast(localized("已打开链接"))
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
            showToast(localized("请先选择要拼贴的文本"))
            return
        }
        copy(
            .text(text),
            success: localizedFormat("已复制 %d 条拼贴内容", itemIDs.count)
        )
    }

    func pasteCombined(_ itemIDs: [UUID]) {
        guard let text = combinedText(for: itemIDs) else {
            showToast(localized("请先选择要拼贴的文本"))
            return
        }
        paste(.text(text))
    }

    func showNotice(_ message: String) {
        showToast(localized(message))
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
                    showToast(localized("已粘贴"))
                case .copiedOnly:
                    showToast(localized("已复制；允许辅助功能权限后可直接粘贴"))
                }
            } catch {
                showToast(localizedDescription(for: error))
            }
        }
    }

    func copy(_ item: ClipboardItem) {
        guard let payload = payload(for: item) else {
            showToast(localized("原始内容已不可用"))
            return
        }
        copy(payload, success: localized("已复制到剪贴板"))
    }

    func toggleFavorite(_ item: ClipboardItem) {
        perform(success: localized(item.isFavorite ? "已取消收藏" : "已加入收藏")) {
            try store.toggleFavorite(item)
        }
    }

    @discardableResult
    func setNote(_ note: String?, for item: ClipboardItem) -> Bool {
        let isRemoving = note?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty != false
        do {
            try store.setNote(note, for: item)
            markStateChanged(rebuildItems: true)
            ensureValidSelection()
            showToast(localized(isRemoving ? "备注已删除" : "备注已保存"))
            return true
        } catch {
            showToast(localizedDescription(for: error))
            return false
        }
    }

    func delete(_ item: ClipboardItem) {
        let deletedID = item.id
        perform(success: localized("已删除")) {
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
        perform(success: localized("标签已创建")) {
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
        perform(success: localized("标签已删除")) {
            try store.deleteTag(tag)
        }
        if selectedTagID == deletedID {
            selectedTagID = nil
        }
    }

    func clearHistory() {
        perform(success: localized("历史记录已清空")) {
            try store.clearHistory()
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
                showToast(localized("快捷键至少需要一个修饰键"))
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
        immediateClipboardRefreshTask?.cancel()
        immediateClipboardRefreshTask = nil
        monitor.stop()
        cancelHotKeyRecording()
        cancelImageTextIndexing(showNotice: false)
    }

    private var selectedItem: ClipboardItem? {
        guard let selectedItemID else { return nil }
        return items.first { $0.id == selectedItemID }
    }

    private func ingest(_ capture: ClipboardCapture) {
        guard !capture.didOmitRepresentations else {
            showToast(localized("原始格式过大或无法完整读取，本次未记录"))
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
                let item = try store.ingestImage(
                    data,
                    typeIdentifier: typeIdentifier,
                    archive: archive,
                    sourceAppBundleIdentifier: capture.sourceApplication.bundleIdentifier,
                    sourceAppName: capture.sourceApplication.name
                )
                if automaticImageTextRecognition, item.imageTextIndexedAt == nil {
                    enqueueImageTextRecognition(
                        for: [item.id],
                        notifyWhenFinished: false
                    )
                }
            }
            markStateChanged(rebuildItems: true)
            ensureValidSelection()
        } catch ClipboardStoreError.emptyText {
            // Empty clipboard strings are intentionally ignored.
        } catch {
            showToast(localizedDescription(for: error))
        }
    }

    private func scheduleImmediateClipboardRefresh(
        sourceApplication: ClipboardSourceApplication
    ) {
        immediateClipboardRefreshTask = Task { @MainActor [weak self] in
            for delay in Self.immediateClipboardRefreshDelays {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, let self, !isPaused else { return }
                monitor.pollNow(sourceApplication: sourceApplication)
                finishShowing()
            }
            self?.immediateClipboardRefreshTask = nil
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
            showToast(localizedDescription(for: error))
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
            selectionScrollGeneration &+= 1
            return
        }
        let nextIndex = min(max(index + offset, 0), items.count - 1)
        self.selectedItemID = items[nextIndex].id
        selectionScrollGeneration &+= 1
    }

    private func ensureValidSelection() {
        if let selectedItemID, items.contains(where: { $0.id == selectedItemID }) {
            return
        }
        selectedItemID = items.first?.id
    }

    private func resetPresentationToNewest() {
        let newestItemID = items.first?.id
        selectedItemID = newestItemID
        listScrollPositionID = newestItemID
        presentedNewestItemID = newestItemID
        listPresentationGeneration &+= 1
    }

    private func rebuildVisibleItems() {
        prunePresentationKindCacheIfNeeded()
        let selectedTag = store.tags.first { $0.id == selectedTagID }
        let filteredItems = store.filteredItems(
            searchText: searchText,
            favoritesOnly: selectedSection == .favorites,
            tag: selectedTag
        )
        let nextItems: [ClipboardItem]
        if selectedContentFilter == .all {
            nextItems = filteredItems
        } else {
            nextItems = filteredItems.filter {
                selectedContentFilter.includes(presentationKind(for: $0))
            }
        }
        prewarmRowPresentationCaches(for: nextItems)
        guard !Self.haveSameItemOrder(visibleItems, nextItems) else { return }
        visibleItems = nextItems
    }

    private func prewarmRowPresentationCaches(for items: [ClipboardItem]) {
        for item in items {
            _ = presentationKind(for: item)
            _ = textPreview(for: item)
        }
    }

    private func prunePresentationKindCacheIfNeeded() {
        let maximumCachedCount = max(1_024, store.items.count * 2)
        guard presentationKindCache.count > maximumCachedCount else { return }
        let activeHashes = Set(store.items.lazy.map(\.contentHash))
        presentationKindCache = presentationKindCache.filter {
            activeHashes.contains($0.key)
        }
        textPreviewCache = textPreviewCache.filter {
            activeHashes.contains($0.key)
        }
    }

    private func enqueueImageTextRecognition(
        for itemIDs: [UUID],
        notifyWhenFinished: Bool
    ) {
        shouldNotifyWhenImageTextIndexFinishes =
            shouldNotifyWhenImageTextIndexFinishes || notifyWhenFinished

        let eligibleItemIDs = Set(store.unindexedImageItems.map(\.id))
        let newItemIDs = itemIDs.filter {
            !queuedImageTextItemIDSet.contains($0)
                && eligibleItemIDs.contains($0)
        }
        guard !newItemIDs.isEmpty else {
            if imageTextRecognitionTask == nil {
                shouldNotifyWhenImageTextIndexFinishes = false
            }
            return
        }

        queuedImageTextItemIDs.append(contentsOf: newItemIDs.reversed())
        queuedImageTextItemIDSet.formUnion(newItemIDs)

        if imageTextRecognitionTask == nil {
            imageTextIndexCompletedCount = 0
            imageTextIndexFailureCount = 0
            imageTextIndexTotalCount = newItemIDs.count
            isIndexingImageText = true
            imageTextRecognitionGeneration += 1
            let generation = imageTextRecognitionGeneration
            imageTextRecognitionTask = Task { @MainActor [weak self] in
                await self?.processImageTextRecognitionQueue(generation: generation)
            }
        } else {
            imageTextIndexTotalCount += newItemIDs.count
        }
    }

    private func processImageTextRecognitionQueue(generation: Int) async {
        while generation == imageTextRecognitionGeneration,
              !Task.isCancelled {
            guard let itemID = queuedImageTextItemIDs.popLast() else { break }

            guard let item = store.items.first(where: { $0.id == itemID }),
                  item.kind == .image,
                  item.imageTextIndexedAt == nil,
                  let imageURL = store.imageURL(for: item) else {
                queuedImageTextItemIDSet.remove(itemID)
                imageTextIndexCompletedCount += 1
                if hasActiveSearch {
                    rebuildVisibleItems()
                }
                continue
            }

            do {
                let recognizedText = try await imageTextRecognizer.recognizeText(
                    at: imageURL
                )
                guard generation == imageTextRecognitionGeneration,
                      !Task.isCancelled else {
                    return
                }
                try store.saveRecognizedImageText(recognizedText, for: itemID)
            } catch is CancellationError {
                return
            } catch {
                imageTextIndexFailureCount += 1
            }

            queuedImageTextItemIDSet.remove(itemID)
            imageTextIndexCompletedCount += 1
            if hasActiveSearch {
                rebuildVisibleItems()
            }
        }

        guard generation == imageTextRecognitionGeneration else { return }
        let shouldNotify = shouldNotifyWhenImageTextIndexFinishes
        let failureCount = imageTextIndexFailureCount

        imageTextRecognitionTask = nil
        isIndexingImageText = false
        queuedImageTextItemIDs.removeAll()
        queuedImageTextItemIDSet.removeAll()
        shouldNotifyWhenImageTextIndexFinishes = false

        if shouldNotify {
            if failureCount == 0 {
                showToast(localized("图片文字索引已完成"))
            } else {
                showToast(
                    localizedFormat(
                        "图片文字索引完成，%d 张识别失败",
                        failureCount
                    )
                )
            }
        }
    }

    private func cancelImageTextIndexing(showNotice: Bool) {
        guard imageTextRecognitionTask != nil || !queuedImageTextItemIDs.isEmpty else {
            return
        }

        imageTextRecognitionGeneration += 1
        imageTextRecognitionTask?.cancel()
        imageTextRecognitionTask = nil
        queuedImageTextItemIDs.removeAll()
        queuedImageTextItemIDSet.removeAll()
        isIndexingImageText = false
        shouldNotifyWhenImageTextIndexFinishes = false

        if showNotice {
            showToast(localized("已停止图片文字识别"))
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
                showToast(localized("快捷键已更新"))
            }
            hotKeyErrorMessage = nil
            markStateChanged()
        } catch {
            let message = localizedDescription(for: error)
            hotKeyErrorMessage = message
            showToast(message)
        }
    }

    private func perform(success: String? = nil, _ operation: () throws -> Void) {
        do {
            try operation()
            markStateChanged(rebuildItems: true)
            ensureValidSelection()
            if let success { showToast(success) }
        } catch {
            showToast(localizedDescription(for: error))
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

    private func markStateChanged(rebuildItems: Bool = false) {
        revision &+= 1
        if rebuildItems {
            rebuildVisibleItems()
        }
    }

    private var hasActiveSearch: Bool {
        !searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    private static func haveSameItemOrder(
        _ lhs: [ClipboardItem],
        _ rhs: [ClipboardItem]
    ) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy {
            $0.id == $1.id
        }
    }

    private static let immediateClipboardRefreshDelays: [Duration] = [
        .milliseconds(12),
        .milliseconds(28),
        .milliseconds(60),
        .milliseconds(125),
        .milliseconds(250)
    ]

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var value: UInt32 = 0
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) { value |= UInt32(cmdKey) }
        if flags.contains(.shift) { value |= UInt32(shiftKey) }
        if flags.contains(.option) { value |= UInt32(optionKey) }
        if flags.contains(.control) { value |= UInt32(controlKey) }
        return value
    }

    func localized(_ key: String) -> String {
        language.localized(key)
    }

    func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
        String(
            format: language.localized(key),
            locale: language.locale,
            arguments: arguments
        )
    }

    private func localizedDescription(for error: Error) -> String {
        if let error = error as? ClipboardStoreError {
            return error.errorDescription(in: language)
        }
        return error.localizedDescription
    }

    private func displayParts(for shortcut: GlobalHotKeyShortcut) -> [String] {
        var result: [String] = []
        if shortcut.modifiers & UInt32(controlKey) != 0 { result.append("⌃") }
        if shortcut.modifiers & UInt32(optionKey) != 0 { result.append("⌥") }
        if shortcut.modifiers & UInt32(shiftKey) != 0 { result.append("⇧") }
        if shortcut.modifiers & UInt32(cmdKey) != 0 { result.append("⌘") }
        result.append(keyName(for: shortcut.keyCode))
        return result
    }

    private func keyName(for keyCode: UInt32) -> String {
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
            UInt32(kVK_Space): localized("Space"),
            UInt32(kVK_Return): localized("Return"),
            UInt32(kVK_Tab): localized("Tab"),
            UInt32(kVK_Delete): localized("Delete")
        ]
        return names[keyCode] ?? localizedFormat("Key %d", keyCode)
    }
}
