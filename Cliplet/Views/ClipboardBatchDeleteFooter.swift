import SwiftUI

struct ClipboardBatchDeleteFooter: View {
    let selectedCount: Int
    let hasItems: Bool
    let areAllSelected: Bool
    let language: NimclipLanguage
    let onCancel: () -> Void
    let onSelectAll: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button("取消", action: onCancel)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

            Text(language.localizedFormat("已选 %d 条", selectedCount))
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Button(
                language.localized(areAllSelected ? "取消全选" : "全选"),
                action: onSelectAll
            )
            .disabled(!hasItems)
            .help("全选仅选择当前搜索和筛选结果")

            Button(role: .destructive, action: onDelete) {
                Label("删除所选", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(selectedCount == 0)
        }
        .font(.system(size: 11.5))
        .controlSize(.small)
        .padding(.horizontal, 12)
        .frame(height: 46)
        .background(Color.clipletSurface)
    }
}
