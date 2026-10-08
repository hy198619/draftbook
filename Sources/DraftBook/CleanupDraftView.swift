import DraftBookCore
import SwiftUI

struct CleanupDraftView: View {
    @EnvironmentObject private var store: DraftStore
    @State private var showingArchiveSheet = false

    let draft: Draft

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Capsule()
                    .fill(draft.color.swiftUIColor.opacity(0.44))
                    .frame(width: 26, height: 8)

                Text(store.labelName(for: draft.color))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Rectangle()
                    .fill(Color.orange.opacity(0.35))
                    .frame(height: 1)

                Text("待处理")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.orange)
                    .fixedSize()
            }
            .frame(height: 24)

            Text(draft.content)
                .font(.system(size: 14))
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                Button("再放 7 天") {
                    store.postpone(id: draft.id, days: 7)
                }

                Button("存档…") {
                    showingArchiveSheet = true
                }

                Menu {
                    Button("再放 1 天") {
                        store.postpone(id: draft.id, days: 1)
                    }
                    Button("再放 30 天") {
                        store.postpone(id: draft.id, days: 30)
                    }
                    Button("固定保留") {
                        store.togglePinned(id: draft.id)
                    }
                    Divider()
                    Button("移到回收站", role: .destructive) {
                        store.moveToTrash(id: draft.id)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.bottom, 16)
        .sheet(isPresented: $showingArchiveSheet) {
            ArchiveDraftSheet(draft: draft) { title, color in
                store.archive(id: draft.id, title: title, color: color)
            }
        }
    }
}
