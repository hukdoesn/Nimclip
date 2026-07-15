import Foundation

enum ClipletTimestampFormatter {
    static func string(
        for date: Date,
        relativeTo referenceDate: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent,
        language: NimclipLanguage = .defaultLanguage
    ) -> String {
        let interval = referenceDate.timeIntervalSince(date)
        guard interval >= 60 else { return language.localized("刚刚") }

        let minutes = Int(interval / 60)
        if minutes < 60 {
            if minutes == 1 { return language.localized("1 分钟前") }
            return language.localizedFormat("%d 分钟前", minutes)
        }

        let hours = Int(interval / 3_600)
        if hours < 24 {
            if hours == 1 { return language.localized("1 小时前") }
            return language.localizedFormat("%d 小时前", hours)
        }

        let startDate = calendar.startOfDay(for: date)
        let startReferenceDate = calendar.startOfDay(for: referenceDate)
        let days = max(
            1,
            calendar.dateComponents([.day], from: startDate, to: startReferenceDate).day ?? Int(interval / 86_400)
        )
        if days < 7 {
            if days == 1 { return language.localized("1 天前") }
            return language.localizedFormat("%d 天前", days)
        }

        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        if calendar.component(.year, from: referenceDate) == year {
            return language.localizedFormat("%d月%d日", month, day)
        }
        return language.localizedFormat("%d年%d月%d日", year, month, day)
    }
}
