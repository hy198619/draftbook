import AppKit
import DraftBookCore
import SwiftUI

struct DraftBlockView: View {
    @EnvironmentObject private var store: DraftStore

    let draftID: UUID

    @State private var isHovered = false
    @State private var isEditingMarkdown = false
    @State private var editorFocused = false
    @State private var showingColors = false
    @State private var showingArchiveSheet = false

    private var draft: Draft? {
        store.draft(withID: draftID)
    }

    var body: some View {
        if let draft {
            VStack(alignment: .leading, spacing: 0) {
                TimelineView(.periodic(from: .now, by: 300)) { context in
                    draftHeader(draft, referenceDate: context.date)
                }

                if !isEditingMarkdown {
                    markdownPreview(draft)
                } else {
                    GrowingTextEditor(
                        text: contentBinding,
                        isFocused: $editorFocused,
                        font: .systemFont(ofSize: 14),
                        minHeight: 48,
                        lineSpacing: 3,
                        onCommit: nil
                    )
                    .frame(minHeight: 48)
                    .padding(.vertical, 5)
                }
            }
            .padding(.bottom, 10)
            .onChange(of: editorFocused) { _, focused in
                if !focused { isEditingMarkdown = false }
            }
            .sheet(isPresented: $showingArchiveSheet) {
                ArchiveDraftSheet(draft: draft) { title in
                    store.archive(id: draft.id, title: title)
                }
            }
        }
    }

    private func draftHeader(_ draft: Draft, referenceDate: Date) -> some View {
        HStack(spacing: 8) {
            Button {
                showingColors.toggle()
            } label: {
                ZStack {
                    Color.clear
                    Capsule()
                        .fill(
                            tagBaseColor(for: draft)
                                .opacity(DraftTiming.tagOpacity(
                                    createdAt: draft.createdAt,
                                    referenceDate: referenceDate
                                ))
                        )
                        .saturation(DraftTiming.tagSaturation(
                            createdAt: draft.createdAt,
                            referenceDate: referenceDate
                        ))
                        .frame(width: 26, height: 8)
                        .overlay {
                            if draft.pinned {
                                Image(systemName: "pin.fill")
                                    .font(.system(size: 6, weight: .bold))
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.35), radius: 0.5)
                            }
                        }
                }
                .frame(width: 36, height: 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(tagHelpText(for: draft, referenceDate: referenceDate))
            .popover(isPresented: $showingColors, arrowEdge: .bottom) {
                colorPicker(draft)
            }

            Rectangle()
                .fill(Color.secondary.opacity(0.18))
                .frame(height: 1)

            if isHovered {
                actionButtons(draft)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                Text(statusText(for: draft, referenceDate: referenceDate))
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(
                        isDue(draft, referenceDate: referenceDate)
                            ? Color.orange
                            : Color.secondary.opacity(0.45)
                    )
                    .fixedSize()
            }
        }
        .frame(height: 28)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.16)) {
                isHovered = hovering
            }
        }
    }

    private func actionButtons(_ draft: Draft) -> some View {
        HStack(spacing: 8) {
            iconButton("doc.on.doc", help: "复制整条") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(draft.content, forType: .string)
                store.markCopied(id: draft.id)
            }

            iconButton(draft.pinned ? "pin.slash" : "pin", help: draft.pinned ? "取消固定" : "固定") {
                store.togglePinned(id: draft.id)
            }

            iconButton("archivebox", help: "存档") {
                showingArchiveSheet = true
            }

            iconButton("trash", help: "删除") {
                store.moveToTrash(id: draft.id)
            }
        }
        .padding(.leading, 2)
    }

    private func iconButton(
        _ systemName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func textButton(
        _ title: String,
        active: Bool,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(active ? Color.accentColor : .secondary)
                .frame(minWidth: 17)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func colorPicker(_ draft: Draft) -> some View {
        HStack(spacing: 10) {
            ForEach(DraftColor.allCases, id: \.self) { color in
                Button {
                    store.setColor(id: draft.id, color: color)
                    showingColors = false
                } label: {
                    Circle()
                        .fill(color.swiftUIColor)
                        .frame(width: 18, height: 18)
                        .overlay {
                            if draft.color == color {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                }
                .buttonStyle(.plain)
                .help(color.displayName)
            }
        }
        .padding(12)
    }

    private func markdownPreview(_ draft: Draft) -> some View {
        MarkdownDraftPreview(source: draft.content)
        .font(.system(size: 14))
        .lineSpacing(3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            isEditingMarkdown = true
            editorFocused = true
        }
        .help("点击编辑原文；复制整条会保留 Markdown 语法")
    }

    private var contentBinding: Binding<String> {
        Binding(
            get: { store.draft(withID: draftID)?.content ?? "" },
            set: { store.updateContent(id: draftID, content: $0) }
        )
    }

    private func tagBaseColor(for draft: Draft) -> Color {
        draft.color.swiftUIColor
    }

    private func isDue(_ draft: Draft, referenceDate: Date) -> Bool {
        guard !draft.pinned, let reviewAt = draft.reviewAt else { return false }
        return reviewAt <= referenceDate
    }

    private func statusText(for draft: Draft, referenceDate: Date) -> String {
        if isDue(draft, referenceDate: referenceDate) {
            return "待处理"
        }
        return relativeDate(draft.createdAt, referenceDate: referenceDate)
    }

    private func relativeDate(_ date: Date, referenceDate: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = Locale(identifier: "zh-Hans")
        return formatter.localizedString(for: date, relativeTo: referenceDate)
    }

    private func tagHelpText(for draft: Draft, referenceDate: Date) -> String {
        let created = formattedDate(draft.createdAt, referenceDate: referenceDate)
        let updated = formattedDate(draft.updatedAt, referenceDate: referenceDate)
        let elapsedText = DraftTiming.uneditedDescription(
            updatedAt: draft.updatedAt,
            referenceDate: referenceDate
        )
        let cleanupText = DraftTiming.cleanupDescription(
            reviewAt: draft.reviewAt,
            isPinned: draft.pinned,
            referenceDate: referenceDate
        )

        return "创建于 \(created) · 更新于 \(updated)\n\(elapsedText) · \(cleanupText)\n点击更换标签颜色"
    }

    private func formattedDate(_ date: Date, referenceDate: Date) -> String {
        let calendar = Calendar.current
        let format = calendar.component(.year, from: date) == calendar.component(.year, from: referenceDate)
            ? "M 月 d 日"
            : "yyyy 年 M 月 d 日"
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh-Hans")
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}

extension DraftColor {
    var swiftUIColor: Color {
        switch self {
        case .gray: .black
        case .yellow: Color(nsColor: .systemYellow)
        case .blue: Color(nsColor: .systemBlue)
        case .purple: Color(nsColor: .systemPurple)
        case .green: Color(nsColor: .systemGreen)
        case .red: Color(nsColor: .systemRed)
        }
    }
}
