import Combine
import Foundation

@MainActor
public final class DraftStore: ObservableObject {
    public enum StoreError: LocalizedError {
        case unsupportedBackupVersion(Int)
        case labelNameTooLong
        case duplicateLabelName(String)

        public var errorDescription: String? {
            switch self {
            case let .unsupportedBackupVersion(version):
                return "这份备份来自更新版本的草稿本（数据版本 \(version)），当前版本无法安全恢复。"
            case .labelNameTooLong:
                return "标签名称最多 12 个字。"
            case let .duplicateLabelName(name):
                return "“\(name)”已用于其他标签，请换一个名称。"
            }
        }
    }

    private struct Snapshot: Codable {
        static let currentSchemaVersion = 5

        var schemaVersion: Int
        var composer: String
        var drafts: [Draft]
        var labelNames: [String: String]

        init(composer: String, drafts: [Draft], labelNames: [String: String]) {
            schemaVersion = Self.currentSchemaVersion
            self.composer = composer
            self.drafts = drafts
            self.labelNames = labelNames
        }

        private enum CodingKeys: String, CodingKey {
            case schemaVersion
            case composer
            case drafts
            case labelNames
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
            composer = try container.decodeIfPresent(String.self, forKey: .composer) ?? ""
            drafts = try container.decodeIfPresent([Draft].self, forKey: .drafts) ?? []
            labelNames = try container.decodeIfPresent([String: String].self, forKey: .labelNames) ?? [:]
        }
    }

    @Published public var composer: String = "" {
        didSet { scheduleSave() }
    }

    @Published public private(set) var drafts: [Draft] = []
    @Published public private(set) var labelNames: [String: String] = [:]
    @Published public private(set) var lastSaveError: String?
    @Published public private(set) var deleteNoticeID: UUID?
    @Published public private(set) var canUndoLastDelete = false

    private let fileURL: URL
    public let dataDirectoryURL: URL
    public let backupDirectoryURL: URL
    @Published public private(set) var defaultReviewDays: Int
    @Published public private(set) var automaticBackupsEnabled: Bool
    @Published public private(set) var backupRetentionCount: Int
    private var pendingSave: Task<Void, Never>?
    private var isLoading = false
    private var lastDeletedDraftID: UUID?
    private var lastDeletedDraftSnapshot: Draft?

    public init(
        dataDirectory: URL? = nil,
        defaultReviewDays: Int = 7,
        automaticBackupsEnabled: Bool = true,
        backupRetentionCount: Int = 14
    ) {
        let directory = dataDirectory ?? Self.defaultDataDirectory()
        dataDirectoryURL = directory
        fileURL = directory.appendingPathComponent("drafts.json", isDirectory: false)
        backupDirectoryURL = directory.appendingPathComponent("Backups", isDirectory: true)
        self.defaultReviewDays = Self.validReviewDays(defaultReviewDays)
        self.automaticBackupsEnabled = automaticBackupsEnabled
        self.backupRetentionCount = Self.validBackupRetention(backupRetentionCount)
        if self.automaticBackupsEnabled {
            pruneBackups(keeping: self.backupRetentionCount)
        }
        load()
    }

    public func configure(
        defaultReviewDays: Int,
        automaticBackupsEnabled: Bool,
        backupRetentionCount: Int
    ) {
        self.defaultReviewDays = Self.validReviewDays(defaultReviewDays)
        self.automaticBackupsEnabled = automaticBackupsEnabled
        self.backupRetentionCount = Self.validBackupRetention(backupRetentionCount)
        if self.automaticBackupsEnabled {
            pruneBackups(keeping: self.backupRetentionCount)
        }
    }

    public var orderedDrafts: [Draft] {
        drafts.filter { $0.state == .active }.sorted { lhs, rhs in
            if lhs.pinned != rhs.pinned {
                return lhs.pinned && !rhs.pinned
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    public var trashedDrafts: [Draft] {
        drafts.filter { $0.state == .trash }.sorted {
            ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast)
        }
    }

    public var archivedDrafts: [Draft] {
        drafts.filter { $0.state == .archived }.sorted {
            ($0.archivedAt ?? $0.updatedAt) > ($1.archivedAt ?? $1.updatedAt)
        }
    }

    public var hasSampleDrafts: Bool {
        drafts.contains(where: \.isSample)
    }

    public func dueDrafts(
        referenceDate: Date = Date(),
        matching query: String = "",
        color: DraftColor? = nil
    ) -> [Draft] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return orderedDrafts.filter { draft in
            guard !draft.pinned, let reviewAt = draft.reviewAt, reviewAt <= referenceDate else {
                return false
            }
            let matchesQuery = normalizedQuery.isEmpty || matches(draft, query: normalizedQuery)
            let matchesColor = color == nil || draft.color == color
            return matchesQuery && matchesColor
        }
    }

    public func drafts(
        in state: DraftState,
        matching query: String,
        color: DraftColor? = nil
    ) -> [Draft] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let source: [Draft]
        switch state {
        case .active:
            source = orderedDrafts
        case .archived:
            source = archivedDrafts
        case .trash:
            source = trashedDrafts
        }
        return source.filter { draft in
            let matchesQuery = normalizedQuery.isEmpty || matches(draft, query: normalizedQuery)
            let matchesColor = color == nil || draft.color == color
            return matchesQuery && matchesColor
        }
    }

    @discardableResult
    public func sealComposer(now: Date = Date()) -> Draft? {
        guard !composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let draft = Draft(
            content: composer,
            createdAt: now,
            updatedAt: now,
            reviewIntervalDays: defaultReviewDays
        )
        drafts.insert(draft, at: 0)
        composer = ""
        saveNow()
        return draft
    }

    public func draft(withID id: UUID) -> Draft? {
        drafts.first(where: { $0.id == id })
    }

    public func updateContent(id: UUID, content: String, now: Date = Date()) {
        mutate(id: id) { draft in
            draft.content = content
            draft.updatedAt = now
            if draft.state == .active,
               !draft.pinned,
               let days = draft.reviewIntervalDays {
                draft.reviewAt = Calendar.current.date(byAdding: .day, value: days, to: now)
            }
        }
    }

    public func toggleMarkdown(id: UUID) {
        mutate(id: id) { draft in
            draft.markdownEnabled.toggle()
        }
    }

    public func setColor(id: UUID, color: DraftColor) {
        mutate(id: id) { draft in
            draft.color = color
        }
    }

    public func labelName(for color: DraftColor) -> String {
        guard color != .gray else { return color.defaultLabelName }
        return labelNames[color.rawValue] ?? color.defaultLabelName
    }

    /// Names belong to stable color slots, not individual drafts. Renaming a
    /// label therefore updates every view without resetting any cleanup date.
    public func setLabelNames(_ names: [DraftColor: String]) throws {
        var result: [String: String] = [:]
        var used = Set([DraftColor.gray.defaultLabelName])
        for color in DraftColor.allCases where color != .gray {
            let input = names[color]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let name = input.isEmpty ? color.defaultLabelName : input
            guard name.count <= 12 else { throw StoreError.labelNameTooLong }
            let key = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard used.insert(key).inserted else { throw StoreError.duplicateLabelName(name) }
            result[color.rawValue] = name
        }
        labelNames = result
        saveNow()
    }

    public func togglePinned(id: UUID, now: Date = Date()) {
        mutate(id: id) { draft in
            draft.pinned.toggle()
            if draft.pinned {
                draft.reviewIntervalDays = nil
                draft.reviewAt = nil
            } else {
                draft.reviewIntervalDays = defaultReviewDays
                draft.reviewAt = Calendar.current.date(byAdding: .day, value: defaultReviewDays, to: now)
            }
        }
    }

    public func markCopied(id: UUID, now: Date = Date()) {
        mutate(id: id) { draft in
            draft.lastCopiedAt = now
        }
    }

    public func moveToTrash(id: UUID, now: Date = Date()) {
        lastDeletedDraftSnapshot = draft(withID: id)
        mutate(id: id) { draft in
            draft.state = .trash
            draft.deletedAt = now
            draft.pinned = false
            draft.reviewAt = nil
        }
        lastDeletedDraftID = id
        deleteNoticeID = id
        canUndoLastDelete = true
        saveNow()
    }

    public func undoLastDelete() {
        guard let snapshot = lastDeletedDraftSnapshot,
              let index = drafts.firstIndex(where: { $0.id == snapshot.id }) else { return }
        drafts[index] = snapshot
        saveNow()
        clearDeleteUndo()
    }

    public func restoreFromTrash(id: UUID, now: Date = Date()) {
        mutate(id: id) { draft in
            draft.deletedAt = nil
            if draft.archivedAt != nil {
                draft.state = .archived
                draft.reviewAt = nil
            } else {
                draft.state = .active
                draft.updatedAt = now
                draft.reviewIntervalDays = defaultReviewDays
                draft.reviewAt = Calendar.current.date(byAdding: .day, value: defaultReviewDays, to: now)
            }
        }
        if lastDeletedDraftID == id {
            clearDeleteUndo()
        }
        saveNow()
    }

    public func deletePermanently(id: UUID) {
        drafts.removeAll(where: { $0.id == id && $0.state == .trash })
        if lastDeletedDraftID == id {
            clearDeleteUndo()
        }
        saveNow()
    }

    public func postpone(id: UUID, days: Int, now: Date = Date()) {
        guard days > 0 else { return }
        mutate(id: id) { draft in
            draft.state = .active
            draft.reviewIntervalDays = days
            draft.reviewAt = Calendar.current.date(byAdding: .day, value: days, to: now)
        }
        saveNow()
    }

    public func archive(id: UUID, title: String? = nil, color: DraftColor? = nil, now: Date = Date()) {
        mutate(id: id) { draft in
            let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            draft.title = trimmed.isEmpty ? draft.suggestedTitle : trimmed
            if let color { draft.color = color }
            draft.state = .archived
            draft.archivedAt = now
            draft.reviewAt = nil
            draft.pinned = false
        }
        saveNow()
    }

    public func renameArchivedDraft(id: UUID, title: String) {
        guard draft(withID: id)?.state == .archived else { return }
        mutate(id: id) { draft in
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            draft.title = trimmed.isEmpty ? draft.suggestedTitle : trimmed
        }
    }

    public func restoreFromArchive(id: UUID, now: Date = Date()) {
        mutate(id: id) { draft in
            draft.state = .active
            draft.archivedAt = nil
            draft.updatedAt = now
            draft.reviewIntervalDays = defaultReviewDays
            draft.reviewAt = Calendar.current.date(byAdding: .day, value: defaultReviewDays, to: now)
        }
        saveNow()
    }

    public func dismissDeleteNotice() {
        deleteNoticeID = nil
    }

    public func installSampleDrafts(now: Date = Date()) {
        drafts.removeAll(where: \.isSample)

        let day: TimeInterval = 86_400
        let samples = [
            Draft(
                content: "【示例：普通草稿】\n这是一条刚创建的蓝色草稿。最后修改 7 天后，它会进入清理台。",
                createdAt: now,
                updatedAt: now,
                color: .blue,
                reviewIntervalDays: 7,
                reviewAt: now.addingTimeInterval(7 * day),
                isSample: true
            ),
            Draft(
                content: "【示例：即将到期】\n这条黄色草稿会在 1 天后进入清理台，用来观察颜色逐渐变淡的效果。",
                createdAt: now.addingTimeInterval(-6 * day),
                updatedAt: now,
                color: .yellow,
                reviewIntervalDays: 1,
                reviewAt: now.addingTimeInterval(day),
                isSample: true
            ),
            Draft(
                content: "【示例：待处理草稿】\n这条红色草稿已经到期，因此同时出现在主页面和清理台。你可以让它延期、固定、存档或进入回收站。",
                createdAt: now.addingTimeInterval(-8 * day),
                updatedAt: now.addingTimeInterval(-8 * day),
                color: .red,
                reviewIntervalDays: 7,
                reviewAt: now.addingTimeInterval(-3_600),
                isSample: true
            ),
            Draft(
                content: "【示例：固定保留】\n这条紫色草稿不会进入清理台；标签仍会按照创建时间褪色。",
                createdAt: now.addingTimeInterval(-30 * day),
                updatedAt: now.addingTimeInterval(-30 * day),
                color: .purple,
                pinned: true,
                reviewIntervalDays: nil,
                reviewAt: nil,
                isSample: true
            ),
            Draft(
                content: "# 示例：Markdown\n\n- 划定后自动呈现 **Markdown**\n- 点击正文编辑源码，点击外部结束编辑\n- 复制整条保留原始语法\n\n> 随手写，稍后再整理。",
                createdAt: now.addingTimeInterval(-day),
                updatedAt: now.addingTimeInterval(-day),
                color: .green,
                markdownEnabled: true,
                reviewIntervalDays: 7,
                reviewAt: now.addingTimeInterval(6 * day),
                isSample: true
            ),
            Draft(
                content: "【示例：已存档】\n存档适合已经完成、但仍值得长期保留的文字。",
                createdAt: now.addingTimeInterval(-20 * day),
                updatedAt: now.addingTimeInterval(-10 * day),
                color: .blue,
                state: .archived,
                archivedAt: now.addingTimeInterval(-day),
                title: "一条已完成的示例存档",
                reviewIntervalDays: nil,
                reviewAt: nil,
                isSample: true
            ),
            Draft(
                content: "【示例：回收站】\n删除不是立即消失：可以恢复，也可以确认后永久删除。",
                createdAt: now.addingTimeInterval(-12 * day),
                updatedAt: now.addingTimeInterval(-12 * day),
                color: .gray,
                state: .trash,
                deletedAt: now.addingTimeInterval(-3_600),
                reviewIntervalDays: nil,
                reviewAt: nil,
                isSample: true
            )
        ]

        drafts.append(contentsOf: samples)
        saveNow()
    }

    public func removeSampleDrafts() {
        drafts.removeAll(where: \.isSample)
        saveNow()
    }

    public func exportPlainText() -> String {
        exportableDrafts.map(\.content).joined(separator: "\n\n---\n\n")
    }

    public func exportMarkdown() -> String {
        exportableDrafts.map { draft in
            let date = Self.exportDateFormatter.string(from: draft.createdAt)
            return "<!-- \(date) -->\n\n\(draft.content)"
        }.joined(separator: "\n\n---\n\n")
    }

    public func fullBackupData() throws -> Data {
        let snapshot = Snapshot(composer: composer, drafts: drafts, labelNames: labelNames)
        return try JSONEncoder.draftBook.encode(snapshot)
    }

    public func restoreFullBackupData(_ data: Data, now: Date = Date()) throws {
        let snapshot = try JSONDecoder.draftBook.decode(Snapshot.self, from: data)
        guard snapshot.schemaVersion <= Snapshot.currentSchemaVersion else {
            throw StoreError.unsupportedBackupVersion(snapshot.schemaVersion)
        }

        try FileManager.default.createDirectory(
            at: backupDirectoryURL,
            withIntermediateDirectories: true
        )

        if FileManager.default.fileExists(atPath: fileURL.path) {
            let currentData = try Data(contentsOf: fileURL)
            let filename = "BeforeRestore-\(Self.restoreDateFormatter.string(from: now)).json"
            let destination = backupDirectoryURL.appendingPathComponent(filename)
            try currentData.write(to: destination, options: [.atomic])
        }

        pendingSave?.cancel()
        isLoading = true
        composer = snapshot.composer
        drafts = snapshot.drafts
        labelNames = snapshot.labelNames
        isLoading = false
        saveNow()
    }

    public func flush() {
        pendingSave?.cancel()
        saveNow()
    }

    private func mutate(id: UUID, mutation: (inout Draft) -> Void) {
        guard let index = drafts.firstIndex(where: { $0.id == id }) else { return }
        mutation(&drafts[index])
        scheduleSave()
    }

    private func load() {
        isLoading = true
        defer { isLoading = false }

        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        do {
            let data = try Data(contentsOf: fileURL)
            let snapshot = try JSONDecoder.draftBook.decode(Snapshot.self, from: data)
            composer = snapshot.composer
            drafts = snapshot.drafts
            labelNames = snapshot.labelNames
            if snapshot.schemaVersion < 3 {
                migrateLifecycleFromEarlierVersion(referenceDate: Date())
            }
            lastSaveError = nil
            createDailyBackupIfNeeded(data: data)
        } catch {
            if restoreLatestBackup() {
                lastSaveError = "主数据文件异常，已从最近的自动备份恢复。"
            } else {
                lastSaveError = "无法读取本地草稿：\(error.localizedDescription)"
            }
        }
    }

    private func scheduleSave() {
        guard !isLoading else { return }
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    private func saveNow() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let snapshot = Snapshot(composer: composer, drafts: drafts, labelNames: labelNames)
            let data = try JSONEncoder.draftBook.encode(snapshot)
            try data.write(to: fileURL, options: [.atomic])
            lastSaveError = nil
            createDailyBackupIfNeeded(data: data)
        } catch {
            lastSaveError = "自动保存失败：\(error.localizedDescription)"
        }
    }

    private var exportableDrafts: [Draft] {
        drafts.filter { $0.state != .trash && !$0.isSample }.sorted {
            $0.createdAt > $1.createdAt
        }
    }

    private func matches(_ draft: Draft, query: String) -> Bool {
        draft.content.localizedCaseInsensitiveContains(query) ||
            draft.displayTitle.localizedCaseInsensitiveContains(query)
    }

    private func migrateLifecycleFromEarlierVersion(referenceDate: Date) {
        let reviewAt = Calendar.current.date(byAdding: .day, value: defaultReviewDays, to: referenceDate)
        for index in drafts.indices where drafts[index].state == .active {
            if drafts[index].pinned {
                drafts[index].reviewIntervalDays = nil
                drafts[index].reviewAt = nil
            } else {
                drafts[index].reviewIntervalDays = defaultReviewDays
                drafts[index].reviewAt = reviewAt
            }
        }
    }

    private func clearDeleteUndo() {
        lastDeletedDraftID = nil
        lastDeletedDraftSnapshot = nil
        deleteNoticeID = nil
        canUndoLastDelete = false
    }

    private func createDailyBackupIfNeeded(data: Data) {
        guard automaticBackupsEnabled else { return }

        do {
            try FileManager.default.createDirectory(
                at: backupDirectoryURL,
                withIntermediateDirectories: true
            )
            let name = "DraftBook-\(Self.backupDateFormatter.string(from: Date())).json"
            let destination = backupDirectoryURL.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: destination.path) {
                try data.write(to: destination, options: [.atomic])
                pruneBackups(keeping: backupRetentionCount)
            }
        } catch {
            if lastSaveError == nil {
                lastSaveError = "自动备份失败：\(error.localizedDescription)"
            }
        }
    }

    private func pruneBackups(keeping limit: Int) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: backupDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let sorted = files.sorted { lhs, rhs in
            let leftDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let rightDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return leftDate > rightDate
        }

        for file in sorted.dropFirst(limit) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func restoreLatestBackup() -> Bool {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: backupDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return false }

        let sorted = files.sorted { lhs, rhs in
            let leftDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let rightDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return leftDate > rightDate
        }

        for file in sorted {
            guard let data = try? Data(contentsOf: file),
                  let snapshot = try? JSONDecoder.draftBook.decode(Snapshot.self, from: data) else {
                continue
            }
            composer = snapshot.composer
            drafts = snapshot.drafts
            labelNames = snapshot.labelNames
            return true
        }
        return false
    }

    private static func defaultDataDirectory() -> URL {
        if let override = ProcessInfo.processInfo.environment["DRAFTBOOK_DATA_DIR"],
           !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }

        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return base.appendingPathComponent("com.yangyuxuan.DraftBook", isDirectory: true)
    }

    private static func validReviewDays(_ value: Int) -> Int {
        [1, 3, 7, 14, 30].contains(value) ? value : 7
    }

    private static func validBackupRetention(_ value: Int) -> Int {
        [7, 14, 30].contains(value) ? value : 14
    }

    private static let backupDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let restoreDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    private static let exportDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh-Hans")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private extension JSONEncoder {
    static var draftBook: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var draftBook: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
