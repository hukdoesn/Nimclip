import AppKit
import SwiftUI

struct MenuBarRootView: View {
    @Bindable var viewModel: ClipletViewModel
    let onPreviewChange: (ClipboardItem?) -> Void

    @FocusState private var isSearchFocused: Bool
    @State private var previewInteraction = ClipletPreviewInteractionState()
    @State private var isShowingTagManager = false
    @State private var isCollectionMode = false
    @State private var collectedItemIDs: [UUID] = []

    init(
        viewModel: ClipletViewModel,
        onPreviewChange: @escaping (ClipboardItem?) -> Void = { _ in }
    ) {
        self.viewModel = viewModel
        self.onPreviewChange = onPreviewChange
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            filters
            Divider()
            itemList
            Divider()
            if isCollectionMode {
                collectionFooter
            } else {
                footer
            }
        }
        .frame(width: 440, height: 600)
        .background(Color.clipletCanvas)
        .overlay(alignment: .bottom) {
            if let message = viewModel.toastMessage {
                ClipletToast(message: message)
                    .padding(.bottom, isCollectionMode ? 54 : 43)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: viewModel.toastMessage)
        .onChange(of: viewModel.searchText) { _, _ in
            viewModel.refreshSelection()
        }
        .onAppear {
            isSearchFocused = true
        }
        .onDisappear {
            resetTransientInteractionState()
            exitCollectionMode()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            resetTransientInteractionState()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            resetTransientInteractionState()
        }
        .onModifierKeysChanged(mask: .option) { _, modifiers in
            updateOptionState(modifiers.contains(.option))
        }
        .onKeyPress(.upArrow) {
            viewModel.selectPrevious()
            return .handled
        }
        .onKeyPress(.downArrow) {
            viewModel.selectNext()
            return .handled
        }
        .onKeyPress(.return) {
            if isCollectionMode {
                viewModel.pasteCombined(collectedItemIDs)
            } else {
                viewModel.pasteSelected()
            }
            return .handled
        }
        .onKeyPress(.delete) {
            deleteSelectedItem()
            return .handled
        }
        .onExitCommand {
            if isCollectionMode {
                exitCollectionMode()
            } else {
                viewModel.dismiss()
            }
        }
        .sheet(isPresented: $isShowingTagManager) {
            TagManagementView(viewModel: viewModel)
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image("NimclipMark")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.primary)
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)

                Text("Nimclip")
                    .font(.system(size: 14, weight: .semibold))

                Circle()
                    .fill(viewModel.isPaused ? Color.orange : Color.green)
                    .frame(width: 6, height: 6)

                Text(viewModel.isPaused ? "已暂停" : "记录中")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Button(action: toggleCollectionMode) {
                    Image(systemName: "rectangle.stack.badge.plus")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ClipletIconButtonStyle(isActive: isCollectionMode))
                .help("多条拼贴")
                .accessibilityLabel(isCollectionMode ? "退出多条拼贴" : "多条拼贴")

                Button(action: viewModel.togglePause) {
                    Image(systemName: viewModel.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ClipletIconButtonStyle(isActive: viewModel.isPaused))
                .help(viewModel.isPaused ? "继续记录" : "暂停记录")
                .accessibilityLabel(viewModel.isPaused ? "继续记录" : "暂停记录")

                Button(action: viewModel.openSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ClipletIconButtonStyle())
                .help("设置")
                .accessibilityLabel("打开设置")
            }

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSearchFocused ? Color.primary : Color.secondary)

                TextField("搜索", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isSearchFocused)
                    .onSubmit(viewModel.pasteSelected)

                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("清除搜索")
                    .accessibilityLabel("清除搜索")
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 32)
            .background(
                Color.primary.opacity(isSearchFocused ? 0.075 : 0.052),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(
                        isSearchFocused
                            ? Color.clipletSelection.opacity(0.62)
                            : Color.clipletBorder.opacity(0.48),
                        lineWidth: isSearchFocused ? 1 : 0.5
                    )
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 9)
        .padding(.bottom, 10)
        .background(Color.clipletSurface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.42))
                .frame(height: 0.5)
        }
    }

    private var filters: some View {
        HStack(spacing: 7) {
            HStack(spacing: 2) {
                sectionTab(.history, title: "历史")
                sectionTab(.favorites, title: "收藏")
            }

            Divider()
                .frame(height: 18)

            HStack(spacing: 2) {
                ForEach(ClipboardContentFilter.allCases) { filter in
                    contentFilterButton(filter)
                }
            }

            Spacer(minLength: 0)

            Menu {
                Button {
                    selectTag(nil)
                } label: {
                    Label("全部标签", systemImage: viewModel.selectedTagID == nil ? "checkmark" : "tag")
                }

                if !viewModel.tags.isEmpty {
                    Divider()
                    ForEach(viewModel.tags) { tag in
                        Button {
                            selectTag(tag.id)
                        } label: {
                            Label(
                                tag.name,
                                systemImage: viewModel.selectedTagID == tag.id ? "checkmark" : "tag"
                            )
                        }
                    }
                }

                Divider()
                Button {
                    isShowingTagManager = true
                } label: {
                    Label("管理标签…", systemImage: "slider.horizontal.3")
                }
            } label: {
                Image(systemName: viewModel.selectedTagID == nil ? "tag" : "tag.fill")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(ClipletIconButtonStyle())
            .menuIndicator(.hidden)
            .menuStyle(.borderlessButton)
            .help("按标签筛选")
            .accessibilityLabel("按标签筛选")
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
    }

    @ViewBuilder
    private var itemList: some View {
        let visibleItems = viewModel.items
        if visibleItems.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(visibleItems) { item in
                            ClipboardItemRow(
                                item: item,
                                tags: viewModel.tags,
                                thumbnailURL: viewModel.thumbnailURL(for: item),
                                presentationKind: viewModel.presentationKind(for: item),
                                referenceDate: viewModel.timestampReferenceDate,
                                isSelected: viewModel.selectedItemID == item.id,
                                isCollectionMode: isCollectionMode,
                                collectionIndex: collectionIndex(for: item.id),
                                onHoverChange: { hovering in
                                    updateHoveredItem(item.id, isHovered: hovering)
                                },
                                onPaste: { viewModel.paste(item) },
                                onPastePlainText: { viewModel.pasteAsPlainText(item) },
                                onCopy: { viewModel.copy(item) },
                                onCopyPlainText: { viewModel.copyAsPlainText(item) },
                                onOpenLink: { viewModel.openLink(item) },
                                onToggleCollection: { toggleCollectedItem(item) },
                                onToggleFavorite: { viewModel.toggleFavorite(item) },
                                onDelete: { viewModel.delete(item) },
                                onToggleTag: { tag in viewModel.toggleTag(tag, on: item) }
                            )
                            .id(item.id)
                        }
                    }
                    .padding(.vertical, 5)
                }
                .scrollIndicators(.automatic)
                .onChange(of: viewModel.selectedItemID) { _, itemID in
                    guard let itemID else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(itemID, anchor: .center)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                viewModel.searchText.isEmpty ? "暂无记录" : "没有匹配结果",
                systemImage: viewModel.selectedSection == .favorites ? "star" : "doc.on.clipboard"
            )
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var collectionFooter: some View {
        HStack(spacing: 8) {
            Button("取消", action: exitCollectionMode)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

            Divider()
                .frame(height: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text("多条拼贴")
                    .font(.system(size: 11.5, weight: .semibold))
                Text(collectedItemIDs.isEmpty ? "按顺序选择文本" : "已选 \(collectedItemIDs.count) 条")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                viewModel.copyCombined(collectedItemIDs)
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }
            .controlSize(.small)
            .disabled(collectedItemIDs.isEmpty)

            Button {
                viewModel.pasteCombined(collectedItemIDs)
            } label: {
                Label("粘贴", systemImage: "arrow.turn.down.left")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(collectedItemIDs.isEmpty)
        }
        .padding(.horizontal, 12)
        .frame(height: 46)
        .background(Color.clipletSurface)
    }

    private var footer: some View {
        HStack(spacing: 7) {
            Text("\(viewModel.items.count) 项")
                .foregroundStyle(.tertiary)
                .monospacedDigit()

            Spacer()

            Text("按住 ⌥ 预览")
                .foregroundStyle(.tertiary)

            Button(action: viewModel.terminateApplication) {
                Image(systemName: "power")
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("退出 Nimclip")
            .accessibilityLabel("退出 Nimclip")
        }
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(Color.clipletSurface)
    }

    private func contentFilterButton(_ filter: ClipboardContentFilter) -> some View {
        let isSelected = viewModel.selectedContentFilter == filter
        return Button {
            withAnimation(.easeOut(duration: 0.14)) {
                viewModel.selectedContentFilter = filter
                viewModel.prepareToShow()
            }
        } label: {
            Image(systemName: filter.systemImage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .frame(width: 28, height: 28)
                .background(
                    isSelected ? Color.primary.opacity(0.09) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(filter.title)
        .accessibilityLabel(filter.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func sectionTab(_ section: ClipletViewModel.Section, title: String) -> some View {
        let isSelected = viewModel.selectedSection == section
        let systemImage = section == .favorites
            ? (isSelected ? "star.fill" : "star")
            : "clock.arrow.circlepath"
        return NimclipNavigationTab(
            title: title,
            systemImage: systemImage,
            isSelected: isSelected,
            isFavorite: section == .favorites
        ) {
            withAnimation(.easeOut(duration: 0.14)) {
                viewModel.selectedSection = section
                viewModel.refreshSelection()
            }
        }
    }

    private func deleteSelectedItem() {
        guard !isCollectionMode else { return }
        guard let selectedItemID = viewModel.selectedItemID,
              let item = viewModel.items.first(where: { $0.id == selectedItemID }) else {
            return
        }
        viewModel.delete(item)
    }

    private func selectTag(_ tagID: UUID?) {
        withAnimation(.easeOut(duration: 0.14)) {
            viewModel.selectedTagID = tagID
            viewModel.prepareToShow()
        }
    }

    private func toggleCollectionMode() {
        withAnimation(.easeOut(duration: 0.16)) {
            if isCollectionMode {
                exitCollectionMode()
            } else {
                isCollectionMode = true
                collectedItemIDs = []
            }
        }
    }

    private func exitCollectionMode() {
        withAnimation(.easeOut(duration: 0.16)) {
            isCollectionMode = false
            collectedItemIDs = []
        }
    }

    private func toggleCollectedItem(_ item: ClipboardItem) {
        guard item.kind == .text else {
            viewModel.showNotice("多条拼贴目前支持文本记录")
            return
        }
        if !isCollectionMode {
            isCollectionMode = true
        }

        withAnimation(.easeOut(duration: 0.14)) {
            if let index = collectedItemIDs.firstIndex(of: item.id) {
                collectedItemIDs.remove(at: index)
            } else {
                collectedItemIDs.append(item.id)
            }
        }
    }

    private func collectionIndex(for itemID: UUID) -> Int? {
        guard let index = collectedItemIDs.firstIndex(of: itemID) else { return nil }
        return index + 1
    }

    private func updateHoveredItem(_ itemID: UUID, isHovered: Bool) {
        if isHovered {
            previewInteraction.hoveredItemID = itemID

            // Reading AppKit's current flags also covers holding Option before
            // the pointer enters the row.
            if NSEvent.modifierFlags.contains(.option) {
                previewInteraction.isOptionPressed = true
                previewInteraction.previewItemID = itemID
                notifyPreviewChange()
            }
        } else if previewInteraction.hoveredItemID == itemID {
            previewInteraction.hoveredItemID = nil
            if previewInteraction.previewItemID == itemID {
                previewInteraction.previewItemID = nil
                notifyPreviewChange()
            }
        }
    }

    private func updateOptionState(_ isPressed: Bool) {
        guard isPressed != previewInteraction.isOptionPressed else { return }
        previewInteraction.isOptionPressed = isPressed

        if isPressed {
            previewInteraction.previewItemID = previewInteraction.hoveredItemID
        } else {
            previewInteraction.previewItemID = nil
        }
        notifyPreviewChange()
    }

    private func resetTransientInteractionState() {
        previewInteraction.hoveredItemID = nil
        previewInteraction.previewItemID = nil
        previewInteraction.isOptionPressed = false
        onPreviewChange(nil)
    }

    private func notifyPreviewChange() {
        guard previewInteraction.isOptionPressed,
              let previewItemID = previewInteraction.previewItemID,
              let item = viewModel.items.first(where: { $0.id == previewItemID }) else {
            onPreviewChange(nil)
            return
        }
        onPreviewChange(item)
    }
}

private final class ClipletPreviewInteractionState {
    var hoveredItemID: UUID?
    var previewItemID: UUID?
    var isOptionPressed = false
}

private struct NimclipNavigationTab: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let isFavorite: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(
                        isFavorite && isSelected
                            ? Color.clipletFavorite
                            : (isSelected ? Color.primary : Color.secondary)
                    )
                Text(title)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            }
            .padding(.horizontal, 8)
            .frame(minWidth: 58, minHeight: 28)
            .background(
                isSelected
                    ? Color.clipletControlFill
                    : (isHovered ? Color.clipletHover : Color.clear),
                in: RoundedRectangle(cornerRadius: 6)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        isSelected ? Color.clipletBorder.opacity(0.72) : Color.clear,
                        lineWidth: 0.5
                    )
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct TagManagementView: View {
    @Bindable var viewModel: ClipletViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var newTagName = ""
    @State private var selectedColor = "2F343A"
    @State private var editingTagID: UUID?
    @State private var editedName = ""

    private let colors: [NimclipTagColor] = [
        .init(name: "石墨", hex: "2F343A"),
        .init(name: "岩灰", hex: "5F6872"),
        .init(name: "藏蓝", hex: "355C7D"),
        .init(name: "海蓝", hex: "3F6F9D"),
        .init(name: "青蓝", hex: "3B7A8D"),
        .init(name: "松青", hex: "3F786C"),
        .init(name: "橄榄", hex: "7E793C"),
        .init(name: "赭金", hex: "A67825"),
        .init(name: "琥珀", hex: "B96833"),
        .init(name: "珊瑚", hex: "B75642"),
        .init(name: "砖红", hex: "A94B50"),
        .init(name: "陶褐", hex: "8C5F52")
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image("NimclipMark")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.primary)
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)

                Text("管理标签")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button(action: dismiss.callAsFunction) {
                    Image(systemName: "xmark")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(ClipletIconButtonStyle())
                .help("关闭")
            }
            .padding(14)
            .background(Color.clipletSurface)

            Divider()

            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    TextField("新标签名称", text: $newTagName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addTag)

                    Button(action: addTag) {
                        Image(systemName: "plus")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(ClipletIconButtonStyle(isActive: true))
                    .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("添加标签")
                }

                Text("标签颜色")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    ForEach(colors) { color in
                        Button {
                            selectedColor = color.hex
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color(clipletHex: color.hex))
                                    .frame(width: 18, height: 18)
                                    .overlay {
                                        Circle()
                                            .stroke(Color.white.opacity(0.22), lineWidth: 0.5)
                                    }

                                if selectedColor == color.hex {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 8, weight: .black))
                                        .foregroundStyle(.white)
                                        .shadow(color: .black.opacity(0.42), radius: 0.5)
                                }
                            }
                            .frame(width: 24, height: 24)
                            .overlay {
                                if selectedColor == color.hex {
                                    Circle()
                                        .stroke(Color.primary.opacity(0.86), lineWidth: 1.5)
                                }
                            }
                            .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help(color.name)
                        .accessibilityLabel("标签颜色，\(color.name)")
                        .accessibilityAddTraits(
                            selectedColor == color.hex ? .isSelected : []
                        )
                    }
                }
            }
            .padding(14)

            Divider()

            if viewModel.tags.isEmpty {
                ContentUnavailableView("暂无标签", systemImage: "tag")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(viewModel.tags) { tag in
                            HStack(spacing: 9) {
                                Circle()
                                    .fill(Color(clipletHex: tag.colorHex))
                                    .frame(width: 9, height: 9)

                                if editingTagID == tag.id {
                                    TextField("标签名称", text: $editedName)
                                        .textFieldStyle(.plain)
                                        .onSubmit { finishEditing(tag) }
                                } else {
                                    Text(tag.name)
                                        .lineLimit(1)
                                }

                                Spacer()

                                Button {
                                    if editingTagID == tag.id {
                                        finishEditing(tag)
                                    } else {
                                        editingTagID = tag.id
                                        editedName = tag.name
                                    }
                                } label: {
                                    Image(systemName: editingTagID == tag.id ? "checkmark" : "pencil")
                                        .frame(width: 24, height: 24)
                                }
                                .buttonStyle(.plain)
                                .help(editingTagID == tag.id ? "完成" : "重命名")

                                Button(role: .destructive) {
                                    viewModel.deleteTag(tag)
                                } label: {
                                    Image(systemName: "trash")
                                        .frame(width: 24, height: 24)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                                .help("删除标签")
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 38)
                            .overlay(alignment: .bottom) {
                                Divider()
                            }
                        }
                    }
                    .padding(10)
                }
            }
        }
        .frame(width: 380, height: 360)
        .background(Color.clipletCanvas)
        .tint(Color.primary)
    }

    private func addTag() {
        let name = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        viewModel.createTag(name: name, colorHex: selectedColor)
        newTagName = ""
    }

    private func finishEditing(_ tag: ClipTag) {
        let name = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        viewModel.renameTag(tag, to: name)
        editingTagID = nil
    }
}

private struct NimclipTagColor: Identifiable {
    let name: String
    let hex: String

    var id: String { hex }
}
