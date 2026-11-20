import Foundation

/// Assumed state of a house, derived from the last SMS sent.
/// The control unit does not answer to the app, so this is a best guess.
public struct HouseState: Equatable, Sendable {
    public var isArmed: Bool
    public var zoneID: UUID?
    public var zoneName: String?
    /// When the current state started (nil = never used).
    public var since: Date?
    public var lastEvent: AlarmEvent?

    public init(isArmed: Bool, zoneID: UUID?, zoneName: String?, since: Date?, lastEvent: AlarmEvent?) {
        self.isArmed = isArmed
        self.zoneID = zoneID
        self.zoneName = zoneName
        self.since = since
        self.lastEvent = lastEvent
    }

    public static let unknown = HouseState(isArmed: false, zoneID: nil, zoneName: nil, since: nil, lastEvent: nil)

    public var title: String {
        if since == nil { return "Nessun comando" }
        return isArmed ? "Inserito" : "Disinserito"
    }

    public var subtitle: String? {
        isArmed ? zoneName : nil
    }
}

/// An interval during which a house was (assumed) armed.
public struct ArmedInterval: Equatable, Sendable {
    public var houseID: UUID
    public var zoneID: UUID?
    public var zoneName: String?
    public var start: Date
    public var end: Date
    /// True when the interval is still running (end = now).
    public var isOpen: Bool

    public var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }

    public func clipped(from lower: Date, to upper: Date) -> ArmedInterval? {
        let s = max(start, lower), e = min(end, upper)
        guard e > s else { return nil }
        var copy = self
        copy.start = s
        copy.end = e
        return copy
    }
}

extension AlarmData {
    /// Events sorted from newest to oldest.
    public var eventsNewestFirst: [AlarmEvent] {
        events.sorted { $0.date > $1.date }
    }

    public func state(for houseID: UUID) -> HouseState {
        let last = events
            .filter { $0.houseID == houseID && $0.changesState }
            .max { $0.date < $1.date }
        guard let last else { return .unknown }
        let house = houses.first { $0.id == houseID }
        let name = house?.zone(last.zoneID)?.name ?? last.zoneName
        return HouseState(
            isArmed: last.kind == .arm,
            zoneID: last.kind == .arm ? last.zoneID : nil,
            zoneName: last.kind == .arm ? name : nil,
            since: last.date,
            lastEvent: last
        )
    }

    /// Armed intervals of the given houses (all when `houseID` is nil), up to `now`.
    public func armedIntervals(houseID: UUID? = nil, now: Date = Date()) -> [ArmedInterval] {
        let relevant = events
            .filter { $0.changesState && (houseID == nil || $0.houseID == houseID) && $0.date <= now }
            .sorted { $0.date < $1.date }
        let byHouse = Dictionary(grouping: relevant, by: { $0.houseID })
        var out: [ArmedInterval] = []
        for (house, list) in byHouse {
            for (i, e) in list.enumerated() where e.kind == .arm {
                let next = i + 1 < list.count ? list[i + 1].date : nil
                out.append(ArmedInterval(
                    houseID: house,
                    zoneID: e.zoneID,
                    zoneName: e.zoneName,
                    start: e.date,
                    end: next ?? now,
                    isOpen: next == nil
                ))
            }
        }
        return out.sorted { $0.start < $1.start }
    }

    // MARK: Mutations

    public mutating func upsert(_ house: House) {
        if let i = houses.firstIndex(where: { $0.id == house.id }) {
            houses[i] = house
        } else {
            houses.append(house)
        }
    }

    /// Removes a house and its history.
    public mutating func removeHouse(_ id: UUID) {
        houses.removeAll { $0.id == id }
        events.removeAll { $0.houseID == id }
        if settings.defaultHouseID == id { settings.defaultHouseID = nil }
    }

    public mutating func record(_ event: AlarmEvent, limit: Int = 5000) {
        events.append(event)
        if events.count > limit {
            events = Array(events.sorted { $0.date > $1.date }.prefix(limit))
        }
    }
}
