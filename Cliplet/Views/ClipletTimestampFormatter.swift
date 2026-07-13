import Foundation

enum ClipletTimestampFormatter {
    static func string(
        for date: Date,
        relativeTo referenceDate: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        let interval = referenceDate.timeIntervalSince(date)
        guard interval >= 60 else { return "刚刚" }

        let minutes = Int(interval / 60)
        if minutes < 60 {
            return "\(minutes) 分钟前"
        }

        let hours = Int(interval / 3_600)
        if hours < 24 {
            return "\(hours) 小时前"
        }

        let startDate = calendar.startOfDay(for: date)
        let startReferenceDate = calendar.startOfDay(for: referenceDate)
        let days = max(
            1,
            calendar.dateComponents([.day], from: startDate, to: startReferenceDate).day ?? Int(interval / 86_400)
        )
        if days < 7 {
            return "\(days) 天前"
        }

        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        if calendar.component(.year, from: referenceDate) == year {
            return "\(month)月\(day)日"
        }
        return "\(year)年\(month)月\(day)日"
    }
}
