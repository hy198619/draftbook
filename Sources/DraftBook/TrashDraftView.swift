import DraftBookCore
import SwiftUI

struct TrashDraftView: View {
    @EnvironmentObject private var store: DraftStore
    @State private var confirmingPermanentDelete = false

    let draft: Draft

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Capsule()
                    .fill(draft.color.swiftUIColor.opacity(0.48))
                    .frame(width: 26, height: 8)

                Text(store.labelName(for: draft.color))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Rectangle()
                    .fill(Color.secondary.opacity(0.18))
                    .frame(height: 1)

                Text(deletedDescription)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .fixedSize()
            }
            .frame(height: 24)

            Text(draft.content)
                .font(.system(size: 14))
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 14) {
                Button("恢复") {
                    store.restoreFromTrash(id: draft.id)
                }

                Button("永久删除", role: .destructive) {
                    confirmingPermanentDelete = true
                }
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.top, 2)
        }
        .padding(.bottom, 16)
        .confirmationDialog(
            "永久删除这条草稿？",
            isPresented: $confirmingPermanentDelete,
            titleVisibility: .visible
        ) {
            Button("永久删除", role: .destructive) {
                store.deletePermanently(id: draft.id)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作无法撤销。")
        }
    }

    private var deletedDescription: String {
        guard let deletedAt = draft.deletedAt else { return "已删除" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh-Hans")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: deletedAt, relativeTo: Date())
    }
}
