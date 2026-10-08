import Foundation

public enum DraftTiming {
    public enum TagAgeStage: Equatable {
        case fresh
        case fiveDays
        case sevenDays
        case thirtyDays
    }

    public static func tagAgeStage(
        createdAt: Date,
        referenceDate: Date = Date()
    ) -> TagAgeStage {
        let age = max(0, referenceDate.timeIntervalSince(createdAt))
        switch age {
        case ..<(5 * 86_400): return .fresh
        case ..<(7 * 86_400): return .fiveDays
        case ..<(30 * 86_400): return .sevenDays
        default: return .thirtyDays
        }
    }

    public static func tagSaturation(
        createdAt: Date,
        referenceDate: Date = Date()
    ) -> Double {
        switch tagAgeStage(createdAt: createdAt, referenceDate: referenceDate) {
        case .fresh: 1
        case .fiveDays: 0.86
        case .sevenDays: 0.73
        case .thirtyDays: 0.60
        }
    }

    public static func wholeDaysSinceUpdate(
        updatedAt: Date,
        referenceDate: Date = Date()
    ) -> Int {
        max(0, Int(referenceDate.timeIntervalSince(updatedAt) / 86_400))
    }

    public static func uneditedDescription(
        updatedAt: Date,
        referenceDate: Date = Date()
    ) -> String {
        let days = wholeDaysSinceUpdate(updatedAt: updatedAt, referenceDate: referenceDate)
        return days == 0 ? "今天更新" : "已有 \(days) 天未编辑"
    }

    public static func cleanupDescription(
        reviewAt: Date?,
        isPinned: Bool,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        if isPinned {
            return "已固定，不进入清理台"
        }
        guard let reviewAt else {
            return "没有清理计划"
        }
        guard reviewAt > referenceDate else {
            return "已进入清理台"
        }

        let start = calendar.startOfDay(for: referenceDate)
        let end = calendar.startOfDay(for: reviewAt)
        let calendarDays = calendar.dateComponents([.day], from: start, to: end).day ?? 0

        return switch calendarDays {
        case ...0: "今天进入清理台"
        case 1: "明天进入清理台"
        default: "还有 \(calendarDays) 天进入清理台"
        }
    }
}
