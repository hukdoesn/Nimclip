import AppKit
import Observation
import SwiftUI

@Observable
final class NimclipSettingsNavigation {
    var selectedPane: NimclipSettingsPane

    init(selectedPane: NimclipSettingsPane = .settings) {
        self.selectedPane = selectedPane
    }
}

struct SettingsView: View {
    @Bindable var viewModel: ClipletViewModel
    @Bindable var navigation: NimclipSettingsNavigation

    @State private var isShowingClearConfirmation = false

    init(
        viewModel: ClipletViewModel,
        navigation: NimclipSettingsNavigation = NimclipSettingsNavigation()
    ) {
        self.viewModel = viewModel
        self.navigation = navigation
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()

            Group {
                switch navigation.selectedPane {
                case .settings:
                    VStack(spacing: 0) {
                        pageHeader(
                            title: "通用",
                            subtitle: "外观、快捷键、历史记录、图片文字识别与粘贴行为"
                        )
                        Divider()

                        ScrollView {
                            VStack(alignment: .leading, spacing: 18) {
                                languageSection
                                appearanceSection
                                shortcutSection
                                historySection
                                NimclipImageTextSettingsSection(
                                    viewModel: viewModel
                                )
                                generalSection
                                pasteSection
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 20)
                        }
                    }
                case .about:
                    NimclipAboutView()
                }
            }
        }
        .frame(width: 660, height: 520)
        .environment(\.locale, viewModel.language.locale)
        .preferredColorScheme(viewModel.appearanceMode.colorScheme)
        .background(Color.clipletCanvas)
        .tint(Color.clipletSelection)
        .overlay(alignment: .bottom) {
            if let message = viewModel.toastMessage {
                ClipletToast(message: message)
                    .padding(.bottom, 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: viewModel.toastMessage)
        .confirmationDialog(
            "清空全部历史记录？",
            isPresented: $isShowingClearConfirmation
        ) {
            Button("清空历史", role: .destructive, action: viewModel.clearHistory)
            Button("取消", role: .cancel) {}
        } message: {
            Text("只会清空未收藏的记录，收藏内容会保留。")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image("NimclipMark")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.primary)
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Nimclip")
                        .font(.system(size: 15, weight: .semibold))
                    Text("版本 \(NimclipBuildInfo.version)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 15)
            .padding(.top, 18)
            .padding(.bottom, 22)

            VStack(spacing: 4) {
                ForEach(NimclipSettingsPane.allCases) { pane in
                    let isSelected = navigation.selectedPane == pane

                    Button {
                        guard !isSelected else { return }
                        navigation.selectedPane = pane
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: pane.systemImage)
                                .font(.system(size: 12, weight: .medium))
                                .frame(width: 18)
                            Text(pane.title)
                                .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                        .contentShape(Rectangle())
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .background(
                            Color.primary.opacity(isSelected ? 0.09 : 0),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                        .animation(.easeOut(duration: 0.1), value: isSelected)
                    }
                    .buttonStyle(NimclipSidebarButtonStyle())
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 8)

            Spacer()

            Label {
                Text("数据仅保存在这台 Mac")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "lock")
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 15)
            .padding(.bottom, 16)
        }
        .frame(width: 170)
        .background(Color.clipletSidebar)
    }

    private func pageHeader(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 19, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .padding(.horizontal, 24)
        .background(Color.clipletCanvas)
    }

    private var languageSection: some View {
        ClipletSettingsSection(title: "语言") {
            ClipletSettingsRow("应用语言", systemImage: "globe") {
                Picker("应用语言", selection: $viewModel.language) {
                    ForEach(NimclipLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 148)
                .accessibilityLabel("应用语言")
            }
        }
    }

    private var appearanceSection: some View {
        ClipletSettingsSection(title: "外观") {
            NimclipAppearancePicker(
                selection: viewModel.appearanceMode,
                language: viewModel.language,
                onSelect: { viewModel.appearanceMode = $0 }
            )
            .padding(.vertical, 11)
        }
    }

    private var shortcutSection: some View {
        ClipletSettingsSection(title: "快捷键") {
            ClipletSettingsRow("显示 Nimclip", systemImage: "keyboard") {
                NimclipShortcutRecorderButton(
                    keys: viewModel.hotKeyDisplayParts,
                    display: viewModel.hotKeyDisplay,
                    isRecording: viewModel.isRecordingHotKey,
                    language: viewModel.language,
                    action: viewModel.beginHotKeyRecording
                )
            }

            if let message = viewModel.hotKeyErrorMessage {
                Divider()
                    .padding(.leading, 32)
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.vertical, 8)
            }
        }
    }

    private var historySection: some View {
        ClipletSettingsSection(title: "历史记录") {
            ClipletSettingsRow("最多保留", systemImage: "list.number") {
                NimclipEditableStepper(
                    value: $viewModel.historyLimit,
                    range: ClipboardStore.minimumHistoryLimit...ClipboardStore.maximumHistoryLimit,
                    step: 100,
                    unit: viewModel.localized("条"),
                    accessibilityName: viewModel.localized("最多保留")
                )
            }

            ClipletSettingsDivider()

            ClipletSettingsRow("保留时间", systemImage: "calendar") {
                NimclipEditableStepper(
                    value: $viewModel.retentionDays,
                    range: ClipboardStore.minimumRetentionDays...ClipboardStore.maximumRetentionDays,
                    step: 1,
                    unit: viewModel.localized("天"),
                    accessibilityName: viewModel.localized("保留时间")
                )
            }

            ClipletSettingsDivider()

            Text("收藏内容不会被保留时间、数量上限或“清空历史”删除。")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 30)
                .padding(.vertical, 9)
        }
    }

    private var generalSection: some View {
        ClipletSettingsSection(title: "通用") {
            ClipletSettingsRow("登录时启动", systemImage: "power") {
                Toggle("登录时启动", isOn: $viewModel.launchAtLogin)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            ClipletSettingsDivider()

            ClipletSettingsRow("自动更新提醒", systemImage: "arrow.triangle.2.circlepath") {
                Toggle(
                    "自动更新提醒",
                    isOn: $viewModel.automaticUpdateChecksEnabled
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            ClipletSettingsDivider()

            ClipletSettingsRow("历史数据", systemImage: "externaldrive") {
                Button(role: .destructive) {
                    isShowingClearConfirmation = true
                } label: {
                    Label("清空历史", systemImage: "trash")
                }
                .accessibilityLabel("清空剪贴板历史")
            }
        }
    }

    private var pasteSection: some View {
        ClipletSettingsSection(title: "直接粘贴") {
            ClipletSettingsRow("辅助功能", systemImage: "hand.raised") {
                HStack(spacing: 10) {
                    Text(viewModel.accessibilityStatusText)
                        .foregroundStyle(.secondary)
                    Button(action: viewModel.openAccessibilitySettings) {
                        Label("系统设置", systemImage: "arrow.up.forward.app")
                    }
                }
            }
        }
    }
}

struct NimclipImageTextSettingsSection: View {
    @Bindable var viewModel: ClipletViewModel

    var body: some View {
        ClipletSettingsSection(title: "图片文字识别") {
            ClipletSettingsRow("自动识别新复制的图片", systemImage: "text.viewfinder") {
                Toggle(
                    "自动识别新复制的图片",
                    isOn: $viewModel.automaticImageTextRecognition
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            ClipletSettingsDivider()

            ClipletSettingsRow("补建历史图片索引", systemImage: "photo.stack") {
                HStack(spacing: 8) {
                    if viewModel.isIndexingImageText {
                        ProgressView(
                            value: Double(viewModel.imageTextIndexCompletedCount),
                            total: Double(max(viewModel.imageTextIndexTotalCount, 1))
                        )
                        .progressViewStyle(.linear)
                        .frame(width: 58)

                        Text(
                            "\(viewModel.imageTextIndexCompletedCount)/\(viewModel.imageTextIndexTotalCount)"
                        )
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)

                        Button("停止", action: viewModel.cancelImageTextIndexing)
                    } else {
                        Text(
                            viewModel.localizedFormat(
                                "%d 张历史图片待识别",
                                viewModel.unindexedImageCount
                            )
                        )
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)

                        Button("开始补建", action: viewModel.indexExistingImageText)
                            .disabled(viewModel.unindexedImageCount == 0)
                    }
                }
            }

            ClipletSettingsDivider()

            Label(
                "自动识别处理之后新复制的图片；历史图片只需手动补建一次。全程使用 macOS 系统 OCR，本地串行处理。",
                systemImage: "lock"
            )
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .padding(.vertical, 10)
        }
    }
}

private struct NimclipAppearancePicker: View {
    let selection: NimclipAppearanceMode
    let language: NimclipLanguage
    let onSelect: (NimclipAppearanceMode) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(NimclipAppearanceMode.allCases) { mode in
                NimclipAppearanceOption(
                    mode: mode,
                    isSelected: selection == mode,
                    language: language,
                    action: { onSelect(mode) }
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("界面外观")
    }
}

private struct NimclipAppearanceOption: View {
    let mode: NimclipAppearanceMode
    let isSelected: Bool
    let language: NimclipLanguage
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(previewBackground)
                    Image(systemName: mode.systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(previewForeground)
                }
                .frame(width: 34, height: 34)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(previewBorder, lineWidth: 0.7)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.title(in: language))
                        .font(.system(size: 12.5, weight: .medium))
                    Text(mode.detail(in: language))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary.opacity(0.45))
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                Color.primary.opacity(backgroundOpacity),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(
                        Color.primary.opacity(isSelected ? 0.26 : 0.09),
                        lineWidth: isSelected ? 1 : 0.6
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(NimclipAppearanceOptionButtonStyle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
        .help(
            language.localizedFormat(
                "始终使用%@外观",
                mode.title(in: language)
            )
        )
        .accessibilityLabel(
            language.localizedFormat("%@外观", mode.title(in: language))
        )
        .accessibilityValue(language.localized(isSelected ? "已选择" : "未选择"))
    }

    private var backgroundOpacity: Double {
        if isSelected { return 0.085 }
        return isHovered ? 0.05 : 0.025
    }

    private var previewBackground: Color {
        mode == .light
            ? Color(nsColor: NSColor(calibratedWhite: 0.97, alpha: 1))
            : Color(nsColor: NSColor(calibratedWhite: 0.13, alpha: 1))
    }

    private var previewForeground: Color {
        mode == .light
            ? Color(nsColor: NSColor(calibratedWhite: 0.30, alpha: 1))
            : Color(nsColor: NSColor(calibratedWhite: 0.86, alpha: 1))
    }

    private var previewBorder: Color {
        mode == .light
            ? Color.black.opacity(0.14)
            : Color.white.opacity(0.18)
    }
}

private struct NimclipAppearanceOptionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

private struct NimclipShortcutRecorderButton: View {
    let keys: [String]
    let display: String
    let isRecording: Bool
    let language: NimclipLanguage
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Group {
                if isRecording {
                    HStack(spacing: 8) {
                        Image(systemName: "keyboard.badge.ellipsis")
                            .font(.system(size: 12, weight: .semibold))
                        Text("请按下组合键")
                            .font(.system(size: 12, weight: .semibold))
                    }
                } else {
                    HStack(spacing: 4) {
                        ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                            NimclipShortcutKeycap(key: key)
                        }
                    }
                }
            }
            .frame(width: 176, height: 34)
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(
            NimclipShortcutButtonStyle(
                isRecording: isRecording,
                isHovered: isHovered
            )
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
        .help(
            language.localized(
                isRecording ? "按下新快捷键，按 Esc 取消" : "录制全局快捷键"
            )
        )
        .accessibilityLabel(
            language.localizedFormat("录制全局快捷键，当前为 %@", display)
        )
        .accessibilityValue(isRecording ? language.localized("正在录制") : display)
    }
}

private struct NimclipShortcutKeycap: View {
    let key: String

    var body: some View {
        Text(key)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .padding(.horizontal, key.count > 1 ? 7 : 0)
            .frame(minWidth: 23, minHeight: 22)
            .foregroundStyle(Color.primary)
            .background(Color.clipletKeycapFill, in: RoundedRectangle(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.clipletKeycapBorder, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.16), radius: 0.7, y: 1)
    }
}

private struct NimclipShortcutButtonStyle: ButtonStyle {
    let isRecording: Bool
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(
                isRecording ? Color.clipletSelectionForeground : Color.primary
            )
            .background(
                background(isPressed: configuration.isPressed),
                in: RoundedRectangle(cornerRadius: 7)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(
                        isRecording
                            ? Color.clipletSelectionForeground.opacity(0.52)
                            : Color.clipletControlBorder,
                        lineWidth: isRecording ? 1.5 : 1
                    )
            }
            .shadow(
                color: isRecording ? .clear : .black.opacity(0.12),
                radius: 1,
                y: configuration.isPressed ? 0 : 1
            )
            .offset(y: configuration.isPressed ? 1 : 0)
    }

    private func background(isPressed: Bool) -> Color {
        if isRecording {
            return .clipletSelection
        }
        if isPressed {
            return .clipletControlPressed
        }
        return isHovered ? .clipletControlHover : .clipletControlFill
    }
}

enum NimclipSettingsPane: String, CaseIterable, Identifiable {
    case settings
    case about

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .settings:
            return "设置"
        case .about:
            return "关于"
        }
    }

    var systemImage: String {
        switch self {
        case .settings:
            return "slider.horizontal.3"
        case .about:
            return "info.circle"
        }
    }
}

private struct NimclipEditableStepper: View {
    @Binding var value: Int

    let range: ClosedRange<Int>
    let step: Int
    let unit: String
    let accessibilityName: String

    @State private var draft = ""
    @State private var isEditing = false
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        Stepper(value: $value, in: range, step: step) {
            ZStack(alignment: .trailing) {
                Text("\(value) \(unit)")
                    .monospacedDigit()
                    .opacity(isEditing ? 0 : 1)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2, perform: beginEditing)
                    .help("双击输入精确数值")

                if isEditing {
                    HStack(spacing: 4) {
                        TextField("数值", text: $draft)
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .focused($isFieldFocused)
                            .onSubmit(commitEditing)
                            .onExitCommand(perform: cancelEditing)
                            .onChange(of: draft) { _, newValue in
                                let filtered = newValue.filter(\.isNumber)
                                if filtered != newValue {
                                    draft = filtered
                                }
                            }
                            .accessibilityLabel("\(accessibilityName)数值")

                        Text(unit)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 76, height: 24, alignment: .trailing)
        }
        .controlSize(.small)
        .accessibilityLabel("\(accessibilityName) \(value) \(unit)")
        .onChange(of: isFieldFocused) { wasFocused, isFocused in
            if isEditing, wasFocused, !isFocused {
                commitEditing()
            }
        }
    }

    private func beginEditing() {
        guard !isEditing else { return }
        draft = String(value)
        isEditing = true
        DispatchQueue.main.async {
            isFieldFocused = true
        }
    }

    private func commitEditing() {
        guard isEditing else { return }
        let parsedValue = Int(draft)
        isEditing = false
        isFieldFocused = false

        guard let parsedValue else { return }
        value = min(max(parsedValue, range.lowerBound), range.upperBound)
    }

    private func cancelEditing() {
        guard isEditing else { return }
        isEditing = false
        isFieldFocused = false
        draft = String(value)
    }
}

struct NimclipAboutView: View {
    private let repositoryURL = URL(string: "https://github.com/hukdoesn/Nimclip")!
    @State private var isShowingContact = false
    @State private var isShowingSupport = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 26)

            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.clipletSettingsSurface)
                Image("NimclipMark")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.primary)
                    .padding(18)
            }
            .frame(width: 76, height: 76)
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.clipletBorder.opacity(0.55), lineWidth: 0.5)
            }
            .accessibilityHidden(true)

            Text("Nimclip")
                .font(.system(size: 24, weight: .semibold))
                .padding(.top, 16)

            Text("轻量、原生、开源的 macOS 剪贴板历史")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            Text("版本 \(NimclipBuildInfo.version)")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .padding(.top, 5)

            HStack(spacing: 8) {
                NimclipAboutLink(
                    title: "项目主页",
                    systemImage: "arrow.up.right",
                    destination: repositoryURL
                )
                Button {
                    NotificationCenter.default.post(
                        name: .nimclipCheckForUpdatesRequested,
                        object: nil
                    )
                } label: {
                    HStack(spacing: 5) {
                        Text("检查更新")
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 9.5, weight: .semibold))
                    }
                }
                .buttonStyle(NimclipAboutControlStyle())
                Button {
                    isShowingSupport = false
                    isShowingContact.toggle()
                } label: {
                    HStack(spacing: 5) {
                        Text("联系作者")
                        Image(systemName: "bubble.left")
                            .font(.system(size: 9.5, weight: .semibold))
                    }
                }
                .buttonStyle(NimclipAboutControlStyle())
                .popover(isPresented: $isShowingContact, arrowEdge: .bottom) {
                    NimclipContactView()
                }
                Button {
                    isShowingContact = false
                    isShowingSupport.toggle()
                } label: {
                    HStack(spacing: 5) {
                        Text("赞赏支持")
                        Image(systemName: "heart")
                            .font(.system(size: 9.5, weight: .semibold))
                    }
                }
                .buttonStyle(NimclipAboutControlStyle())
                .popover(isPresented: $isShowingSupport, arrowEdge: .bottom) {
                    NimclipSupportView()
                }
            }
            .padding(.top, 18)

            Spacer(minLength: 24)

            Divider()

            HStack(spacing: 8) {
                Text("Apache License 2.0")
                Spacer()
                Text("© 2026 hukdoesn ｜ 胡图图不涂涂")
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 22)
            .frame(height: 46)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clipletCanvas)
        .tint(Color.clipletSelection)
    }
}

private struct NimclipSidebarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(.linear(duration: 0.06), value: configuration.isPressed)
    }
}

private struct NimclipAboutLink: View {
    let title: LocalizedStringKey
    let systemImage: String
    let destination: URL

    var body: some View {
        Button {
            NSWorkspace.shared.open(destination)
        } label: {
            HStack(spacing: 5) {
                Text(title)
                Image(systemName: systemImage)
                    .font(.system(size: 9.5, weight: .semibold))
            }
        }
        .buttonStyle(NimclipAboutControlStyle())
        .help("在默认浏览器中打开项目主页")
        .accessibilityHint("使用 macOS 默认浏览器打开")
    }
}

private struct NimclipAboutControlStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                Color.primary.opacity(configuration.isPressed ? 0.11 : 0.065),
                in: RoundedRectangle(cornerRadius: 6)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.clipletBorder.opacity(0.55), lineWidth: 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .animation(.linear(duration: 0.06), value: configuration.isPressed)
    }
}

struct NimclipContactView: View {
    @Environment(\.dismiss) private var dismiss

    private let issuesURL = URL(string: "https://github.com/hukdoesn/Nimclip/issues")!

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("联系作者")
                        .font(.system(size: 16, weight: .semibold))
                    Text("选择 GitHub 或微信联系")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("关闭")
            }

            Link(destination: issuesURL) {
                HStack(spacing: 7) {
                    Image(systemName: "ladybug")
                    Text("通过 GitHub 联系")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9.5, weight: .semibold))
                }
                .padding(.horizontal, 11)
                .frame(maxWidth: .infinity, minHeight: 34)
            }
            .buttonStyle(NimclipContactLinkStyle())
            .padding(.top, 14)

            HStack(spacing: 9) {
                Divider()
                Text("微信联系")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize()
                Divider()
            }
            .frame(height: 12)
            .padding(.top, 16)
            .padding(.bottom, 12)

            NimclipContactQRCodeImage()
                .frame(width: 182, height: 182)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.clipletBorder.opacity(0.6), lineWidth: 0.5)
                }
                .frame(maxWidth: .infinity)
                .accessibilityLabel("微信二维码，联系人胡图图不涂涂")

            Text("扫码添加「胡图图不涂涂」")
                .font(.system(size: 11.5, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.top, 10)

            Text("添加时请备注“Nimclip”，方便识别。")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 3)
        }
        .padding(18)
        .frame(width: 320, height: 408, alignment: .top)
        .background(Color.clipletCanvas)
        .tint(Color.clipletSelection)
    }
}

struct NimclipSupportView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("赞赏支持")
                        .font(.system(size: 16, weight: .semibold))
                    Text("如果 Nimclip 对你有帮助，可以请作者喝杯咖啡。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("关闭")
            }

            HStack(alignment: .top, spacing: 14) {
                NimclipPaymentCodeCard(
                    title: "微信支付",
                    assetName: "NimclipWeChatPayQR",
                    accent: Color(red: 0.03, green: 0.76, blue: 0.38),
                    accessibilityLabel: "微信支付收款码"
                )
                NimclipPaymentCodeCard(
                    title: "支付宝",
                    assetName: "NimclipAlipayQR",
                    accent: Color(red: 0.10, green: 0.47, blue: 0.95),
                    accessibilityLabel: "支付宝收款码"
                )
            }
            .padding(.top, 16)

            Text("使用微信或支付宝扫码赞赏")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
        }
        .padding(18)
        .frame(width: 470, height: 350, alignment: .top)
        .background(Color.clipletCanvas)
        .tint(Color.clipletSelection)
    }
}

private struct NimclipPaymentCodeCard: View {
    let title: LocalizedStringKey
    let assetName: String
    let accent: Color
    let accessibilityLabel: LocalizedStringKey

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "qrcode")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accent)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }

            Image(assetName)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .frame(width: 174, height: 174)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.clipletBorder.opacity(0.65), lineWidth: 0.5)
                }
                .accessibilityLabel(accessibilityLabel)
        }
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        .background(
            Color.clipletSettingsSurface,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.clipletBorder.opacity(0.55), lineWidth: 0.5)
        }
    }
}

private struct NimclipContactQRCodeImage: NSViewRepresentable {
    func makeNSView(context: Context) -> NimclipContactQRCodeNSView {
        NimclipContactQRCodeNSView()
    }

    func updateNSView(_ nsView: NimclipContactQRCodeNSView, context: Context) {}
}

private final class NimclipContactQRCodeNSView: NSView {
    // Precomputed from the WeChat contact URL so system appearance cannot recolor it.
    private static let rows = [
        "00000000000000000000000000000000000",
        "01111111001100100111010010011111110",
        "01000001001100111010010100010000010",
        "01011101011111101111111111010111010",
        "01011101010100011100110100010111010",
        "01011101011101101011000111010111010",
        "01000001010100101100011000010000010",
        "01111111010101010101010101011111110",
        "00000000010001001000001010000000000",
        "01011111001001111000000101011111000",
        "01111000010010001101101010011011010",
        "00010111100010001001010000000101100",
        "01100000111100011000011100000111000",
        "01101001101011000001100001100110100",
        "01011010111011111110011110000010110",
        "00101101101101010001101000111101100",
        "00100100101000010100111111111011000",
        "01000101011111100100100111101100010",
        "00010110110001101111110110111011000",
        "00111001100111001110011100101101100",
        "01011110001111001111111110111111100",
        "01010101111111010100110001100010010",
        "01111010111100111011001100000011010",
        "01001011111101001110011101100111100",
        "01010010010100011001001001100001000",
        "01001101100000011010000001111110000",
        "00000000011010000100111011000101110",
        "01111111000001111101010011010101000",
        "01000001011011010100101011000111100",
        "01011101010111110001001001111110110",
        "01011101011001001110010000000101110",
        "01011101010100110001100110011001000",
        "01000001000010100101111010100111000",
        "01111111010100100010100111011011100",
        "00000000000000000000000000000000000"
    ]

    private let modules: [Bool]
    private let moduleCount: Int

    override init(frame frameRect: NSRect) {
        moduleCount = Self.rows.count
        modules = Self.rows.flatMap { row in
            row.map { $0 == "1" }
        }

        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()

        guard moduleCount > 0 else { return }

        let quietZone = 4
        let totalModules = moduleCount + (quietZone * 2)
        let moduleSize = floor(
            min(bounds.width, bounds.height) / CGFloat(totalModules)
        )
        let qrCodeSize = moduleSize * CGFloat(totalModules)
        let origin = CGPoint(
            x: floor((bounds.width - qrCodeSize) / 2),
            y: floor((bounds.height - qrCodeSize) / 2)
        )

        NSColor.black.setFill()
        for row in 0..<moduleCount {
            for column in 0..<moduleCount where modules[(row * moduleCount) + column] {
                let rect = NSRect(
                    x: origin.x + CGFloat(column + quietZone) * moduleSize,
                    y: origin.y + CGFloat(moduleCount - 1 - row + quietZone) * moduleSize,
                    width: moduleSize,
                    height: moduleSize
                )
                rect.fill()
            }
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        if !bounds.isEmpty {
            needsDisplay = true
        }
    }
}

private struct NimclipContactLinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(.primary)
            .background(
                Color.primary.opacity(configuration.isPressed ? 0.11 : 0.065),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.clipletBorder.opacity(0.55), lineWidth: 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .animation(.linear(duration: 0.06), value: configuration.isPressed)
    }
}

private struct ClipletSettingsSection<Content: View>: View {
    let title: LocalizedStringKey
    let content: Content

    init(title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                content
            }
            .padding(.horizontal, 14)
            .background(Color.clipletSettingsSurface, in: RoundedRectangle(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(Color.clipletBorder.opacity(0.55), lineWidth: 0.5)
            }
        }
    }
}

private struct ClipletSettingsRow<Control: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    let control: Control

    init(
        _ title: LocalizedStringKey,
        systemImage: String,
        @ViewBuilder control: @escaping () -> Control
    ) {
        self.title = title
        self.systemImage = systemImage
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.secondary)
                .frame(width: 20, height: 24)

            Text(title)
                .font(.system(size: 13))

            Spacer(minLength: 16)
            control
        }
        .frame(minHeight: 47)
    }
}

private struct ClipletSettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 30)
    }
}
