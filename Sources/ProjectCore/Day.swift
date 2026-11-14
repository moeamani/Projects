import Foundation

/// A calendar day with no time zone or time-of-day (days since 1970-01-01).
/// Scheduling is done in whole working days, so this avoids every DST/time-zone pitfall.
public struct Day: Hashable, Comparable, Sendable {
    public var ordinal: Int

    public init(ordinal: Int) { self.ordinal = ordinal }

    public init(year: Int, month: Int, day: Int) {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = month > 2 ? month - 3 : month + 9
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        self.ordinal = era * 146097 + doe - 719468
    }

    public static func < (a: Day, b: Day) -> Bool { a.ordinal < b.ordinal }

    public var ymd: (year: Int, month: Int, day: Int) {
        let z = ordinal + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        let y = yoe + era * 400 + (m <= 2 ? 1 : 0)
        return (y, m, d)
    }

    /// 0 = Sunday … 6 = Saturday.
    public var weekday: Int { (floorDiv(ordinal, 7) * -7 + ordinal + 4) % 7 }

    public func adding(_ days: Int) -> Day { Day(ordinal: ordinal + days) }

    /// "yyyy-MM-dd"
    public var iso: String {
        let v = ymd
        return String(format: "%04d-%02d-%02d", v.year, v.month, v.day)
    }

    /// Parses the date part of "yyyy-MM-dd" or "yyyy-MM-ddTHH:mm:ss".
    public init?(iso: String) {
        let parts = iso.prefix(10).split(separator: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        self.init(year: y, month: m, day: d)
    }

    public static func today() -> Day { Day(date: Date()) }

    public init(date: Date) {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    /// Noon, local time (safe for date pickers).
    public var date: Date {
        let v = ymd
        var c = DateComponents()
        c.year = v.year; c.month = v.month; c.day = v.day; c.hour = 12
        return Calendar.current.date(from: c) ?? Date(timeIntervalSince1970: 0)
    }

}

func floorDiv(_ a: Int, _ b: Int) -> Int {
    let q = a / b
    return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q
}

/// Which weekdays are working days (0 = Sunday … 6 = Saturday).
public struct WorkWeek: Equatable, Sendable {
    public let days: [Int]

    public init(days: [Int]) {
        let d = Array(Set(days.filter { (0...6).contains($0) })).sorted()
        self.days = d.isEmpty ? [1, 2, 3, 4, 5] : d
    }

    public static let monFri = WorkWeek(days: [1, 2, 3, 4, 5])
    public static let everyDay = WorkWeek(days: [0, 1, 2, 3, 4, 5, 6])

    public func isWorking(_ day: Day) -> Bool { days.contains(day.weekday) }
}

extension Day {
    /// This day if it is a working day, otherwise the next one that is.
    public func nextWorkingDay(_ week: WorkWeek = .monFri) -> Day {
        var d = self
        while !week.isWorking(d) { d = d.adding(1) }
        return d
    }

    /// Position on a continuous number line that counts only working days (non-working days snap forward).
    public func workIndex(_ week: WorkWeek = .monFri) -> Int {
        let d = nextWorkingDay(week)
        let weekNumber = floorDiv(d.ordinal - d.weekday + 4, 7)       // weeks start on Sunday
        return weekNumber * week.days.count + (week.days.firstIndex(of: d.weekday) ?? 0)
    }

    public init(workIndex idx: Int, _ week: WorkWeek = .monFri) {
        let k = week.days.count
        let weekNumber = floorDiv(idx, k)
        self.init(ordinal: weekNumber * 7 - 4 + week.days[idx - weekNumber * k])
    }
}
