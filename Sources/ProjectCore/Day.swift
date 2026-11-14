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

    public var isWorkingDay: Bool { let w = weekday; return w != 0 && w != 6 }

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

    // MARK: Working-day arithmetic (Mon–Fri)

    /// This day if it is a working day, otherwise the following Monday.
    public func nextWorkingDay() -> Day {
        switch weekday {
        case 6: return adding(2)
        case 0: return adding(1)
        default: return self
        }
    }

    /// Index of this day on a continuous Mon–Fri-only number line (weekends snap forward).
    public var workIndex: Int {
        let d = nextWorkingDay()
        let wd = d.weekday               // 1...5
        let monday = d.ordinal - (wd - 1)
        return floorDiv(monday - 4, 7) * 5 + (wd - 1)
    }

    public init(workIndex idx: Int) {
        let week = floorDiv(idx, 5)
        self.init(ordinal: week * 7 + 4 + (idx - week * 5))
    }
}

func floorDiv(_ a: Int, _ b: Int) -> Int {
    let q = a / b
    return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q
}
