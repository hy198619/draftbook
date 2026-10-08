import Foundation

public enum DraftColor: String, Codable, CaseIterable, Sendable {
    case gray
    case yellow
    case blue
    case purple
    case green
    case red

    public var displayName: String {
        switch self {
        case .gray: "未分类"
        case .yellow: "黄色"
        case .blue: "蓝色"
        case .purple: "紫色"
        case .green: "绿色"
        case .red: "红色"
        }
    }

    public var defaultLabelName: String {
        switch self {
        case .gray: "未分类"
        case .yellow: "分类1"
        case .blue: "分类2"
        case .purple: "分类3"
        case .green: "分类4"
        case .red: "分类5"
        }
    }
}

public enum DraftState: String, Codable, CaseIterable, Sendable {
    case active
    case archived
    case trash
}

public struct Draft: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var content: String
    public var createdAt: Date
    public var updatedAt: Date
    public var color: DraftColor
    public var markdownEnabled: Bool
    public var pinned: Bool
    public var lastCopiedAt: Date?
    public var state: DraftState
    public var archivedAt: Date?
    public var deletedAt: Date?
    public var title: String?
    public var reviewIntervalDays: Int?
    public var reviewAt: Date?
    public var isSample: Bool

    public init(
        id: UUID = UUID(),
        content: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        color: DraftColor = .gray,
        markdownEnabled: Bool = false,
        pinned: Bool = false,
        lastCopiedAt: Date? = nil,
        state: DraftState = .active,
        archivedAt: Date? = nil,
        deletedAt: Date? = nil,
        title: String? = nil,
        reviewIntervalDays: Int? = 7,
        reviewAt: Date? = nil,
        isSample: Bool = false
    ) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.color = color
        self.markdownEnabled = markdownEnabled
        self.pinned = pinned
        self.lastCopiedAt = lastCopiedAt
        self.state = state
        self.archivedAt = archivedAt
        self.deletedAt = deletedAt
        self.title = title
        self.reviewIntervalDays = reviewIntervalDays
        self.reviewAt = reviewAt ?? reviewIntervalDays.flatMap { days in
            Calendar.current.date(byAdding: .day, value: days, to: updatedAt)
        }
        self.isSample = isSample
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case content
        case createdAt
        case updatedAt
        case color
        case markdownEnabled
        case pinned
        case lastCopiedAt
        case state
        case archivedAt
        case deletedAt
        case title
        case reviewIntervalDays
        case reviewAt
        case isSample
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        content = try container.decode(String.self, forKey: .content)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        color = try container.decodeIfPresent(DraftColor.self, forKey: .color) ?? .gray
        markdownEnabled = try container.decodeIfPresent(Bool.self, forKey: .markdownEnabled) ?? false
        pinned = try container.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        lastCopiedAt = try container.decodeIfPresent(Date.self, forKey: .lastCopiedAt)
        state = try container.decodeIfPresent(DraftState.self, forKey: .state) ?? .active
        archivedAt = try container.decodeIfPresent(Date.self, forKey: .archivedAt)
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        reviewIntervalDays = try container.decodeIfPresent(Int.self, forKey: .reviewIntervalDays)
        reviewAt = try container.decodeIfPresent(Date.self, forKey: .reviewAt)
        isSample = try container.decodeIfPresent(Bool.self, forKey: .isSample) ?? false
    }

    public var suggestedTitle: String {
        let firstLine = content
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })?
            .trimmingCharacters(in: .whitespaces) ?? "未命名草稿"
        return String(firstLine.prefix(20))
    }

    public var displayTitle: String {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? suggestedTitle : trimmed
    }
}
