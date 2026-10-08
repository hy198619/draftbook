import AppKit
import DraftBookCore
import SwiftUI

struct ArchivedDraftView: View {
    @EnvironmentObject private var store: DraftStore
    @FocusState private var titleFocused: Bool
    @State private var isEditingTitle = false
    @State private var titleInput = ""
    @State private var isEditingContent = false
    @State private var editorFocused = false

    let draft: Draft

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Capsule()
                    .fill(draft.color.swiftUIColor)
                    .frame(width: 30, height: 9)

                Menu {
                    ForEach(DraftColor.allCases, id: \.self) { color in
                        Button {
                            store.setColor(id: draft.id, color: color)
                        } label: {
                            Label(
                                store.labelName(for: color),
                                systemImage: draft.color == color ? "checkmark.circle.fill" : "circle.fill"
                            )
                        }
                    }
                } label: {
                    Text(store.labelName(for: draft.color))
                        .font(.system(size: 10))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("更换存档标签")

                if isEditingTitle {
                    TextField("存档名称", text: $titleInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                        .focused($titleFocused)
                        .onSubmit(commitTitle)
                        .onChange(of: titleFocused) { _, focused in
                            if !focused { commitTitle() }
                        }
                } else {
                    Text(draft.displayTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    Button {
                        titleInput = draft.displayTitle
                        isEditingTitle = true
                        titleFocused = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("编辑存档名称")
                }

                Rectangle()
                    .fill(Color.secondary.opacity(0.18))
                    .frame(height: 1)
            }
            .frame(height: 24)

            if isEditingContent {
                GrowingTextEditor(
                    text: contentBinding,
                    isFocused: $editorFocused,
                    font: .systemFont(ofSize: 14),
                    minHeight: 48,
                    lineSpacing: 3,
                    onCommit: nil
                )
                .frame(minHeight: 48)
                .onChange(of: editorFocused) { _, focused in
                    if !focused { isEditingContent = false }
                }
            } else {
                MarkdownDraftPreview(source: draft.content) {
                    isEditingContent = true
                    editorFocused = true
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !NSEvent.modifierFlags.contains(.command) else { return }
                    isEditingContent = true
                    editorFocused = true
                }
                .help("单击编辑存档正文；⌘ 单击链接打开")
            }

            HStack(spacing: 14) {
                Button(isEditingContent ? "完成编辑" : "编辑正文") {
                    if isEditingContent {
                        editorFocused = false
                        isEditingContent = false
                    } else {
                        isEditingContent = true
                        editorFocused = true
                    }
                }

                Spacer(minLength: 0)

                Button("恢复到草稿") {
                    store.restoreFromArchive(id: draft.id)
                }

                Button("移到回收站", role: .destructive) {
                    store.moveToTrash(id: draft.id)
                }
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
        }
        .padding(.bottom, 16)
    }

    private var contentBinding: Binding<String> {
        Binding(
            get: { store.draft(withID: draft.id)?.content ?? "" },
            set: { store.updateContent(id: draft.id, content: $0) }
        )
    }

    private func commitTitle() {
        guard isEditingTitle else { return }
        store.renameArchivedDraft(id: draft.id, title: titleInput)
        isEditingTitle = false
    }
}
