import Foundation

public enum StatsPeriod: String, CaseIterable, Identifiable, Sendable {
    case week, month, quarter, year, all

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .week: return "7 g"
        case .month: return "30 g"
        case .quarter: return "90 g"
        case .year: return "1 anno"
        case .all: return "Tutto"
        }
    }

    public var days: Int? {
        switch self {
        case .week: return 7
        case .month: return 30
        case .quarter: return 90
        case .year: return 365
        case .all: return nil
        }
    }
}

public enum BucketUnit: String, Sendable {
    case day, week, month

    public var calendarComponent: Calendar.Component {
        switch self {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        }
    }
}

/// Commands sent in one time bucket.
public struct ActivityBucket: Equatable, Identifiable, Sendable {
    public var start: Date
    public var arms: Int
    public var disarms: Int
    public var status: Int
    public var id: Date { start }
    public var total: Int { arms + disarms + status }
}

public struct ZoneUsage: Equatable, Identifiable, Sendable {
    public var id: String
    public var houseID: UUID
    public var zoneID: UUID?
    public var name: String
    public var colorHex: String
    public var icon: String
    public var count: Int
    public var armedTime: TimeInterval
}

public struct SourceUsage: Equatable, Identifiable, Sendable {
    public var source: EventSource
    public var count: Int
    public var id: String { source.rawValue }
}

/// All the numbers shown in the Statistics page.
public struct AlarmStats: Equatable, Sendable {
    public var periodStart: Date
    public var periodEnd: Date
    public var sent: Int
    public var arms: Int
    public var disarms: Int
    public var statusRequests: Int
    public var cancelled: Int
    public var failed: Int
    public var protectedTime: TimeInterval
    /// Share of the period spent armed (0…1).
    public var protectedShare: Double
    public var averageArmDuration: TimeInterval?
    public var longestArmDuration: TimeInterval?
    public var zones: [ZoneUsage]
    public var sources: [SourceUsage]
    public var buckets: [ActivityBucket]
    public var bucketUnit: BucketUnit
    /// Arms per hour of the day (0…23).
    public var armsByHour: [Int]
    /// Disarms per hour of the day (0…23).
    public var disarmsByHour: [Int]
    /// Commands per weekday, Monday first (7 values).
    public var byWeekday: [Int]
    public var typicalArmHour: Int?
    public var typicalDisarmHour: Int?
    /// Consecutive days (up to today) with at least one arming.
    public var currentStreak: Int
    public var longestStreak: Int
    public var activeDays: Int

    public var isEmpty: Bool { sent == 0 && cancelled == 0 && failed == 0 && protectedTime == 0 }

    public var successRate: Double? {
        let attempts = sent + cancelled + failed
        return attempts == 0 ? nil : Double(sent) / Double(attempts)
    }

    public init(data: AlarmData, houseID: UUID? = nil, period: StatsPeriod, now: Date = Date(), calendar: Calendar = .current) {
        let scoped = data.events.filter { houseID == nil || $0.houseID == houseID }
        let todayStart = calendar.startOfDay(for: now)
        let start: Date
        if let days = period.days {
            start = calendar.date(byAdding: .day, value: -(days - 1), to: todayStart) ?? todayStart
        } else {
            let first = scoped.map(\.date).min() ?? now
            start = min(calendar.startOfDay(for: first), todayStart)
        }
        periodStart = start
        periodEnd = now

        let inPeriod = scoped.filter { $0.date >= start && $0.date <= now }
        let smsSent = inPeriod.filter(\.isSentSMS)
        sent = smsSent.count
        arms = smsSent.filter { $0.kind == .arm }.count
        disarms = smsSent.filter { $0.kind == .disarm }.count
        statusRequests = smsSent.filter { $0.kind == .status }.count
        cancelled = inPeriod.filter { $0.result == .cancelled }.count
        failed = inPeriod.filter { $0.result == .failed }.count

        // Armed time (intervals may start before the period).
        let intervals = data.armedIntervals(houseID: houseID, now: now)
        let clipped = intervals.compactMap { $0.clipped(from: start, to: now) }
        protectedTime = clipped.reduce(0) { $0 + $1.duration }
        let houseCount = Double(max(1, houseID == nil ? Set(intervals.map(\.houseID)).count : 1))
        let span = max(1, now.timeIntervalSince(start)) * houseCount
        protectedShare = min(1, protectedTime / span)
        let closedInPeriod = intervals.filter { !$0.isOpen && $0.start >= start }
        averageArmDuration = closedInPeriod.isEmpty ? nil : closedInPeriod.reduce(0) { $0 + $1.duration } / Double(closedInPeriod.count)
        longestArmDuration = clipped.map(\.duration).max()

        // Zones.
        var zoneMap: [String: ZoneUsage] = [:]
        func key(_ house: UUID, _ zone: UUID?, _ name: String?) -> String {
            "\(house.uuidString)|\(zone?.uuidString ?? name ?? "?")"
        }
        for e in smsSent where e.kind == .arm {
            let house = data.houses.first { $0.id == e.houseID }
            let zone = house?.zone(e.zoneID)
            let k = key(e.houseID, e.zoneID, e.zoneName)
            var u = zoneMap[k] ?? ZoneUsage(
                id: k, houseID: e.houseID, zoneID: e.zoneID,
                name: zone?.name ?? e.zoneName ?? "Zona eliminata",
                colorHex: zone?.colorHex ?? "#757575", icon: zone?.icon ?? "shield.fill",
                count: 0, armedTime: 0)
            u.count += 1
            zoneMap[k] = u
        }
        for i in clipped {
            let k = key(i.houseID, i.zoneID, i.zoneName)
            if var u = zoneMap[k] {
                u.armedTime += i.duration
                zoneMap[k] = u
            } else {
                let house = data.houses.first { $0.id == i.houseID }
                let zone = house?.zone(i.zoneID)
                zoneMap[k] = ZoneUsage(
                    id: k, houseID: i.houseID, zoneID: i.zoneID,
                    name: zone?.name ?? i.zoneName ?? "Zona eliminata",
                    colorHex: zone?.colorHex ?? "#757575", icon: zone?.icon ?? "shield.fill",
                    count: 0, armedTime: i.duration)
            }
        }
        zones = zoneMap.values.sorted { ($0.count, $0.armedTime, $0.name) > ($1.count, $1.armedTime, $1.name) }

        // Sources.
        let srcCounts = Dictionary(grouping: inPeriod.filter { $0.result == .sent }, by: \.source).mapValues(\.count)
        sources = EventSource.allCases.compactMap { s in
            guard let c = srcCounts[s], c > 0 else { return nil }
            return SourceUsage(source: s, count: c)
        }

        // Buckets.
        let dayCount = (calendar.dateComponents([.day], from: start, to: todayStart).day ?? 0) + 1
        let unit: BucketUnit = dayCount <= 31 ? .day : (dayCount <= 120 ? .week : .month)
        bucketUnit = unit
        var bucketStarts: [Date] = []
        if let first = calendar.dateInterval(of: unit.calendarComponent, for: start)?.start {
            var d = first
            while d <= now {
                bucketStarts.append(d)
                guard let next = calendar.date(byAdding: unit.calendarComponent, value: 1, to: d) else { break }
                d = next
            }
        }
        var bucketMap: [Date: ActivityBucket] = Dictionary(uniqueKeysWithValues: bucketStarts.map { ($0, ActivityBucket(start: $0, arms: 0, disarms: 0, status: 0)) })
        for e in smsSent {
            guard let b = calendar.dateInterval(of: unit.calendarComponent, for: e.date)?.start else { continue }
            var bucket = bucketMap[b] ?? ActivityBucket(start: b, arms: 0, disarms: 0, status: 0)
            switch e.kind {
            case .arm: bucket.arms += 1
            case .disarm: bucket.disarms += 1
            case .status: bucket.status += 1
            }
            bucketMap[b] = bucket
        }
        buckets = bucketMap.values.sorted { $0.start < $1.start }

        // Hours and weekdays.
        var armsH = Array(repeating: 0, count: 24)
        var disarmsH = Array(repeating: 0, count: 24)
        var week = Array(repeating: 0, count: 7)
        for e in smsSent {
            let h = calendar.component(.hour, from: e.date)
            if e.kind == .arm { armsH[h] += 1 }
            if e.kind == .disarm { disarmsH[h] += 1 }
            let wd = calendar.component(.weekday, from: e.date) // 1 = Sunday
            week[(wd + 5) % 7] += 1
        }
        armsByHour = armsH
        disarmsByHour = disarmsH
        byWeekday = week
        typicalArmHour = Self.mode(armsH)
        typicalDisarmHour = Self.mode(disarmsH)

        // Streaks of days with at least one arm.
        let armDays = Set(scoped.filter { $0.changesState && $0.kind == .arm && $0.source != .manual }
            .map { calendar.startOfDay(for: $0.date) })
        activeDays = Set(smsSent.map { calendar.startOfDay(for: $0.date) }).count
        var streak = 0
        var cursor = todayStart
        if !armDays.contains(cursor), let y = calendar.date(byAdding: .day, value: -1, to: cursor) { cursor = y }
        while armDays.contains(cursor) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        currentStreak = streak
        var longest = 0, run = 0
        var previous: Date?
        for d in armDays.sorted() {
            if let p = previous, calendar.date(byAdding: .day, value: 1, to: p) == d {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
            previous = d
        }
        longestStreak = longest
    }

    static func mode(_ values: [Int]) -> Int? {
        guard let m = values.max(), m > 0 else { return nil }
        return values.firstIndex(of: m)
    }

    public static let weekdaySymbols = ["Lun", "Mar", "Mer", "Gio", "Ven", "Sab", "Dom"]
}
