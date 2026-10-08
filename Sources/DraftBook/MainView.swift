import AppKit
import Combine
import DraftBookCore
import SwiftUI

struct MainView: View {
    private enum Section: Equatable {
        case drafts
        case cleanup
        case archive
        case trash

        var title: String {
            switch self {
            case .drafts: "草稿区"
            case .cleanup: "清理台"
            case .archive: "存档区"
            case .trash: "回收站"
            }
        }
    }

    @EnvironmentObject private var store: DraftStore
    @AppStorage("keepWindowOnTop") private var keepWindowOnTop = true
    @State private var composerFocused = true
    @State private var section: Section = .drafts
    @State private var searchVisible = false
    @State private var searchQuery = ""
    @State private var selectedColor: DraftColor?
    @State private var showingSectionPicker = false
    @State private var showingFeatureGuide = false
    @State private var showingUpdateCheck = false
    @State private var now = Date()
    @FocusState private var searchFocused: Bool

    private let lifecycleTimer = Timer.publish(
        every: 60,
        on: .main,
        in: .common
    ).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header
            if searchVisible {
                searchBar
            }
            Divider()
            content
        }
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(alignment: .bottom) {
            VStack(spacing: 8) {
                if store.deleteNoticeID != nil {
                    deleteNotice
                }
                if let message = store.lastSaveError {
                    saveError(message)
                }
            }
            .padding(.bottom, 12)
        }
        .background(WindowConfigurator(floating: keepWindowOnTop))
        .onAppear {
            composerFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            store.flush()
        }
        .onDisappear {
            store.flush()
        }
        .onReceive(NotificationCenter.default.publisher(for: .draftBookShowSearch)) { _ in
            showSearch()
        }
        .onReceive(NotificationCenter.default.publisher(for: .draftBookShowDrafts)) { _ in
            selectSection(.drafts)
        }
        .onReceive(NotificationCenter.default.publisher(for: .draftBookShowCleanup)) { _ in
            selectSection(.cleanup)
        }
        .onReceive(NotificationCenter.default.publisher(for: .draftBookShowArchive)) { _ in
            selectSection(.archive)
        }
        .onReceive(NotificationCenter.default.publisher(for: .draftBookShowTrash)) { _ in
            selectSection(.trash)
        }
        .onReceive(NotificationCenter.default.publisher(for: .draftBookShowGuide)) { _ in
            showingFeatureGuide = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .draftBookCheckForUpdates)) { _ in
            showingUpdateCheck = true
        }
        .onReceive(lifecycleTimer) { date in
            now = date
        }
        .sheet(isPresented: $showingFeatureGuide) {
            FeatureGuideView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showingUpdateCheck) {
            UpdateCheckView()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            sectionMenu

            Spacer()

            if section == .drafts && !searchVisible {
                Text("写完一条，记得⌘+↵划定草稿")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            if section == .archive && !searchVisible {
                colorFilterMenu
            }

            Button(action: toggleSearch) {
                Image(systemName: searchVisible ? "xmark" : "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .help(searchVisible ? "关闭搜索" : "搜索草稿（⌘F）")

            exportMenu

            Button {
                keepWindowOnTop.toggle()
            } label: {
                Image(systemName: keepWindowOnTop ? "pin.fill" : "pin")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(keepWindowOnTop ? Color.accentColor : .secondary)
            .help(keepWindowOnTop ? "取消保持在最上方" : "保持在最上方")
        }
        .padding(.horizontal, 16)
        .frame(height: 42)
        .background(.bar)
    }

    private var sectionMenu: some View {
        Button {
            showingSectionPicker.toggle()
        } label: {
            HStack(spacing: 6) {
                Text(section.title)
                    .font(.system(size: 14, weight: .semibold))

                if !store.dueDrafts(referenceDate: now).isEmpty {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                } else if !store.trashedDrafts.isEmpty {
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 6, height: 6)
                }

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help("切换草稿区、清理台、存档区和回收站")
        .popover(isPresented: $showingSectionPicker, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                sectionChoice(.drafts, title: "草稿区")
                sectionChoice(.cleanup, title: cleanupMenuTitle)
                sectionChoice(.archive, title: "存档区")
                sectionChoice(.trash, title: trashMenuTitle)

                if store.canUndoLastDelete {
                    Divider().padding(.vertical, 3)
                    Button("撤销最近删除") {
                        store.undoLastDelete()
                        showingSectionPicker = false
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
            }
            .font(.system(size: 12))
            .padding(8)
            .frame(width: 172)
        }
    }

    private func sectionChoice(_ choice: Section, title: String) -> some View {
        Button {
            showingSectionPicker = false
            selectSection(choice)
        } label: {
            HStack {
                Text(title)
                Spacer()
                if section == choice {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(section == choice ? Color.accentColor.opacity(0.08) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }

    private var cleanupMenuTitle: String {
        let count = store.dueDrafts(referenceDate: now).count
        return count == 0 ? "清理台" : "清理台（\(count)）"
    }

    private var trashMenuTitle: String {
        let count = store.trashedDrafts.count
        return count == 0 ? "回收站" : "回收站（\(count)）"
    }

    private var content: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                switch section {
                case .drafts:
                    draftContent
                case .cleanup:
                    cleanupContent
                case .archive:
                    archiveContent
                case .trash:
                    trashContent
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 36)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var draftContent: some View {
        if !isFiltering {
            composer
        }

        ForEach(store.drafts(in: .active, matching: searchQuery, color: selectedColor)) { draft in
            DraftBlockView(draftID: draft.id)
                .environmentObject(store)
        }

        if !isFiltering && store.orderedDrafts.isEmpty && store.composer.isEmpty {
            emptyHint
        } else if isFiltering && store.drafts(in: .active, matching: searchQuery, color: selectedColor).isEmpty {
            noSearchResults
        }
    }

    @ViewBuilder
    private var cleanupContent: some View {
        ForEach(store.dueDrafts(referenceDate: now, matching: searchQuery, color: selectedColor)) { draft in
            CleanupDraftView(draft: draft)
                .environmentObject(store)
        }

        if store.dueDrafts(referenceDate: now).isEmpty {
            cleanupEmptyHint
        } else if isFiltering && store.dueDrafts(referenceDate: now, matching: searchQuery, color: selectedColor).isEmpty {
            noSearchResults
        }
    }

    @ViewBuilder
    private var archiveContent: some View {
        ForEach(store.drafts(in: .archived, matching: searchQuery, color: selectedColor)) { draft in
            ArchivedDraftView(draft: draft)
                .environmentObject(store)
        }

        if store.archivedDrafts.isEmpty {
            archiveEmptyHint
        } else if isFiltering && store.drafts(in: .archived, matching: searchQuery, color: selectedColor).isEmpty {
            noSearchResults
        }
    }

    @ViewBuilder
    private var trashContent: some View {
        ForEach(store.drafts(in: .trash, matching: searchQuery, color: selectedColor)) { draft in
            TrashDraftView(draft: draft)
                .environmentObject(store)
        }

        if store.trashedDrafts.isEmpty {
            trashEmptyHint
        } else if isFiltering && store.drafts(in: .trash, matching: searchQuery, color: selectedColor).isEmpty {
            noSearchResults
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            TextField(searchPlaceholder, text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("清除搜索")
            }

            colorFilterMenu
        }
        .padding(.horizontal, 16)
        .frame(height: 34)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
    }

    private var colorFilterMenu: some View {
        Menu {
            Button {
                selectedColor = nil
            } label: {
                Label("全部标签", systemImage: selectedColor == nil ? "checkmark" : "circle")
            }

            Divider()

            ForEach(DraftColor.allCases, id: \.self) { color in
                Button {
                    selectedColor = color
                } label: {
                    Label(
                        store.labelName(for: color),
                        systemImage: selectedColor == color ? "checkmark.circle.fill" : "circle.fill"
                    )
                }
            }
        } label: {
            Image(systemName: selectedColor == nil ? "tag" : "tag.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(selectedColor?.swiftUIColor ?? Color.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(selectedColor.map { "只看\(store.labelName(for: $0))" } ?? "按内容标签筛选")
    }

    private var isFiltering: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedColor != nil
    }

    private var searchPlaceholder: String {
        switch section {
        case .drafts: "搜索草稿正文"
        case .cleanup: "搜索待处理草稿"
        case .archive: "搜索存档名称和正文"
        case .trash: "搜索回收站"
        }
    }

    private var exportMenu: some View {
        Menu {
            Button("导出纯文本…") {
                ExportController.export(.plainText, from: store)
            }
            Button("导出 Markdown…") {
                ExportController.export(.markdown, from: store)
            }
            Button("导出完整备份…") {
                ExportController.export(.fullBackup, from: store)
            }

            Button("恢复完整备份…") {
                ExportController.importFullBackup(into: store)
            }

            Divider()

            Button("打开自动备份文件夹") {
                ExportController.openBackupFolder(for: store)
            }

            Button("打开数据文件夹") {
                ExportController.openDataFolder(for: store)
            }

            Divider()

            Button("使用说明与示例…") {
                showingFeatureGuide = true
            }

            if store.hasSampleDrafts {
                Button("移除全部示例草稿", role: .destructive) {
                    store.removeSampleDrafts()
                }
            } else {
                Button("添加示例草稿") {
                    store.installSampleDrafts()
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 12, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("导出与备份")
    }

    private var composer: some View {
        ZStack(alignment: .topLeading) {
            if store.composer.isEmpty && !composerFocused {
                Text("直接写下来……")
                    .font(.system(size: 15))
                    .foregroundStyle(.quaternary)
                    .padding(.top, 15)
                    .allowsHitTesting(false)
            }

            GrowingTextEditor(
                text: $store.composer,
                isFocused: $composerFocused,
                font: .systemFont(ofSize: 15),
                minHeight: 84,
                lineSpacing: 3,
                onCommit: sealComposer
            )
            .frame(minHeight: 84)
            .padding(.vertical, 7)
        }
    }

    private var emptyHint: some View {
        VStack(spacing: 7) {
            Image(systemName: "arrow.up")
                .foregroundStyle(.quaternary)
            Text("输入后按 ⌘↩︎，完成这一段，开始下一段")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 32)
    }

    private var cleanupEmptyHint: some View {
        sectionEmptyHint(
            icon: "checkmark.circle",
            title: "暂时没有需要处理的草稿",
            detail: "新草稿默认在最后修改 \(store.defaultReviewDays) 天后进入这里",
            color: .green.opacity(0.7)
        )
    }

    private var archiveEmptyHint: some View {
        sectionEmptyHint(
            icon: "archivebox",
            title: "存档区是空的",
            detail: "需要长期保留的草稿可以存放在这里",
            color: .secondary.opacity(0.5)
        )
    }

    private var trashEmptyHint: some View {
        sectionEmptyHint(
            icon: "trash",
            title: "回收站是空的",
            detail: "删除的草稿会先保存在这里",
            color: .secondary.opacity(0.5)
        )
    }

    private func sectionEmptyHint(
        icon: String,
        title: String,
        detail: String,
        color: Color
    ) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(.quaternary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 44)
    }

    private var noSearchResults: some View {
        Text("没有找到相关草稿")
            .font(.system(size: 12))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.top, 44)
    }

    private var deleteNotice: some View {
        HStack(spacing: 10) {
            Text("已移到回收站")
            Button("撤销") {
                store.undoLastDelete()
            }
            .buttonStyle(.plain)
            .fontWeight(.semibold)
        }
        .font(.system(size: 12))
        .foregroundStyle(.white)
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .background(.black.opacity(0.78), in: Capsule())
        .task(id: store.deleteNoticeID) {
            try? await Task.sleep(for: .seconds(5))
            store.dismissDeleteNotice()
        }
    }

    private func saveError(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 11))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.red.opacity(0.9), in: Capsule())
    }

    private func sealComposer() {
        if store.sealComposer() != nil {
            composerFocused = true
        }
    }

    private func selectSection(_ newSection: Section) {
        section = newSection
        searchQuery = ""
        selectedColor = nil
        if newSection == .drafts && !searchVisible {
            composerFocused = true
        } else {
            composerFocused = false
        }
    }

    private func toggleSearch() {
        if searchVisible {
            searchVisible = false
            searchQuery = ""
            selectedColor = nil
            searchFocused = false
            if section == .drafts {
                composerFocused = true
            }
        } else {
            showSearch()
        }
    }

    private func showSearch() {
        searchVisible = true
        composerFocused = false
        DispatchQueue.main.async {
            searchFocused = true
        }
    }
}
