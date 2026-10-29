import Foundation

/// Port of date-fns `formatDistanceStrict(date, now)` as used by `RelativeTime` in the RN app,
/// e.g. "42 seconds", "1 hour", "3 days". No "ago" suffix.
enum RelativeTime {
    /// Posted once a minute so screens can refresh visible timestamps.
    static let tick = Notification.Name("RelativeTime.tick")

    static func string(from date: Date, now: Date = Date()) -> String {
        let seconds = abs(now.timeIntervalSince(date))
        let minutes = seconds / 60

        let (value, unit): (Double, String) = switch minutes {
        case ..<1: (seconds, "second")
        case ..<60: (minutes, "minute")
        case ..<(60 * 24): (minutes / 60, "hour")
        case ..<(60 * 24 * 30): (minutes / (60 * 24), "day")
        case ..<(60 * 24 * 365): (minutes / (60 * 24 * 30), "month")
        default: (minutes / (60 * 24 * 365), "year")
        }

        let count = Int(value.rounded())
        return count == 1 ? "1 \(unit)" : "\(count) \(unit)s"
    }
}
