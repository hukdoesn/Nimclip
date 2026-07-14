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
                            subtitle: "快捷键、历史记录与粘贴行为"
                        )
                        Divider()

                        ScrollView {
                            VStack(alignment: .leading, spacing: 18) {
                                shortcutSection
                                historySection
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
            Text("收藏内容会保留。")
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
                    Button {
                        withAnimation(.easeOut(duration: 0.12)) {
                            navigation.selectedPane = pane
                        }
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: pane.systemImage)
                                .font(.system(size: 12, weight: .medium))
                                .frame(width: 18)
                            Text(pane.title)
                                .font(.system(size: 13, weight: navigation.selectedPane == pane ? .medium : .regular))
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .foregroundStyle(navigation.selectedPane == pane ? Color.primary : Color.secondary)
                        .background(
                            navigation.selectedPane == pane ? Color.primary.opacity(0.09) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(navigation.selectedPane == pane ? .isSelected : [])
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

    private func pageHeader(title: String, subtitle: String) -> some View {
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

    private var shortcutSection: some View {
        ClipletSettingsSection(title: "快捷键") {
            ClipletSettingsRow("显示 Nimclip", systemImage: "keyboard") {
                NimclipShortcutRecorderButton(
                    keys: viewModel.hotKeyDisplayParts,
                    display: viewModel.hotKeyDisplay,
                    isRecording: viewModel.isRecordingHotKey,
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
                    unit: "条",
                    accessibilityName: "最多保留"
                )
            }

            ClipletSettingsDivider()

            ClipletSettingsRow("保留时间", systemImage: "calendar") {
                NimclipEditableStepper(
                    value: $viewModel.retentionDays,
                    range: ClipboardStore.minimumRetentionDays...ClipboardStore.maximumRetentionDays,
                    step: 1,
                    unit: "天",
                    accessibilityName: "保留时间"
                )
            }
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

private struct NimclipShortcutRecorderButton: View {
    let keys: [String]
    let display: String
    let isRecording: Bool
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
        .help(isRecording ? "按下新快捷键，按 Esc 取消" : "录制全局快捷键")
        .accessibilityLabel("录制全局快捷键，当前为 \(display)")
        .accessibilityValue(isRecording ? "正在录制" : display)
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

    var title: String {
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
    private let issuesURL = URL(string: "https://github.com/hukdoesn/Nimclip/issues")!

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

            Text("轻量、原生的 macOS 剪贴板历史")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            Text("版本 \(NimclipBuildInfo.version)（\(NimclipBuildInfo.build)）")
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
                NimclipAboutLink(
                    title: "反馈问题",
                    systemImage: "bubble.left",
                    destination: issuesURL
                )
            }
            .padding(.top, 18)

            Spacer(minLength: 24)

            Divider()

            HStack(spacing: 8) {
                Text("Apache License 2.0")
                Spacer()
                Text("© 2026 hukdoesn")
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

private struct NimclipAboutLink: View {
    let title: String
    let systemImage: String
    let destination: URL

    var body: some View {
        Link(destination: destination) {
            HStack(spacing: 5) {
                Text(title)
                Image(systemName: systemImage)
                    .font(.system(size: 9.5, weight: .semibold))
            }
        }
        .font(.system(size: 11.5, weight: .medium))
        .foregroundStyle(.primary)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Color.primary.opacity(0.065), in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.clipletBorder.opacity(0.55), lineWidth: 0.5)
        }
        .buttonStyle(.plain)
    }
}

private struct ClipletSettingsSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
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
    let title: String
    let systemImage: String
    let control: Control

    init(
        _ title: String,
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

private enum NimclipBuildInfo {
    static let version = Bundle.main.object(
        forInfoDictionaryKey: "CFBundleShortVersionString"
    ) as? String ?? "开发构建"

    static let build = Bundle.main.object(
        forInfoDictionaryKey: "CFBundleVersion"
    ) as? String ?? "-"
}
