import AppKit
import DraftBookCore
import SwiftUI

struct DraftBlockView: View {
    @EnvironmentObject private var store: DraftStore
    @Environment(\.openSettings) private var openSettings
    @AppStorage(AppPreferenceKeys.settingsSelectedTab) private var selectedSettingsTab = "general"

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
                ArchiveDraftSheet(draft: draft) { title, color in
                    store.archive(id: draft.id, title: title, color: color)
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
                        .fill(draft.color.agedSwiftUIColor(
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
        VStack(alignment: .leading, spacing: 4) {
            ForEach(DraftColor.allCases, id: \.self) { color in
                Button {
                    store.setColor(id: draft.id, color: color)
                    showingColors = false
                } label: {
                    HStack(spacing: 9) {
                        Capsule()
                            .fill(color.swiftUIColor)
                            .frame(width: 26, height: 8)
                        Text(store.labelName(for: color))
                            .font(.system(size: 12))
                        Spacer(minLength: 12)
                        if draft.color == color {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .semibold))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
            }

            Divider()

            Button("自定义分类名称…") {
                showingColors = false
                selectedSettingsTab = "labels"
                DispatchQueue.main.async {
                    openSettings()
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.top, 2)
        }
        .padding(12)
        .frame(width: 172)
    }

    private func markdownPreview(_ draft: Draft) -> some View {
        MarkdownDraftPreview(source: draft.content) {
            isEditingMarkdown = true
            editorFocused = true
        }
        .font(.system(size: 14))
        .lineSpacing(3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            // A Command-click is routed by DraftLinkTextField. Do not also
            // switch to source editing after opening a link.
            guard !NSEvent.modifierFlags.contains(.command) else { return }
            isEditingMarkdown = true
            editorFocused = true
        }
        .help("单击编辑原文；⌘ 单击链接打开；复制整条保留 Markdown 语法")
    }

    private var contentBinding: Binding<String> {
        Binding(
            get: { store.draft(withID: draftID)?.content ?? "" },
            set: { store.updateContent(id: draftID, content: $0) }
        )
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

        return "\(store.labelName(for: draft.color)) · 创建于 \(created) · 更新于 \(updated)\n\(elapsedText) · \(cleanupText)\n点击更换标签"
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
    private var nsColor: NSColor {
        switch self {
        case .gray: .black
        case .yellow: .systemYellow
        case .blue: .systemBlue
        case .purple: .systemPurple
        case .green: .systemGreen
        case .red: .systemRed
        }
    }

    var swiftUIColor: Color {
        Color(nsColor: nsColor)
    }

    func agedSwiftUIColor(createdAt: Date, referenceDate: Date) -> Color {
        Color(nsColor: agedNSColor(createdAt: createdAt, referenceDate: referenceDate))
    }

    func agedNSColor(createdAt: Date, referenceDate: Date) -> NSColor {
        let stage = DraftTiming.tagAgeStage(createdAt: createdAt, referenceDate: referenceDate)
        if self == .gray {
            let white: CGFloat = switch stage {
            case .fresh: 0
            case .fiveDays: 0.20
            case .sevenDays: 0.38
            case .thirtyDays: 0.58
            }
            return NSColor(white: white, alpha: 1)
        }

        guard let resolved = nsColor.usingColorSpace(.deviceRGB) else { return nsColor }
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        resolved.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return NSColor(
            deviceHue: hue,
            saturation: saturation * DraftTiming.tagSaturation(createdAt: createdAt, referenceDate: referenceDate),
            brightness: brightness,
            alpha: alpha
        )
    }
}
