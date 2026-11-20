import XCTest
@testable import AlarmCore

final class MessageTests: XCTestCase {
    func testDefaultTemplate() {
        XCTAssertEqual(MessageBuilder.message(command: "attiva 1-2-3", password: "1966"), "attiva 1-2-3 1966")
        XCTAssertEqual(MessageBuilder.masked(command: "attiva 1-2-3", password: "1966"), "attiva 1-2-3 ••••")
    }

    func testCustomTemplateAndSpaces() {
        XCTAssertEqual(MessageBuilder.message(command: " disattiva ", password: "1966", template: "{password}  {comando}"), "1966 disattiva")
        XCTAssertEqual(MessageBuilder.message(command: "attiva 1", password: "1966", template: "PWD{password} {comando}"), "PWD1966 attiva 1")
        // Template without {comando} falls back to the default.
        XCTAssertEqual(MessageBuilder.message(command: "attiva 1", password: "9", template: "boh"), "attiva 1 9")
    }

    func testPhoneNormalization() {
        XCTAssertEqual(MessageBuilder.normalize(phone: "+39 333-123.45 (67)"), "+393331234567")
    }

    func testSMSURL() {
        let url = MessageBuilder.smsURL(number: "+39 333 1234567", body: "attiva 1-2-3 1966")
        XCTAssertEqual(url?.absoluteString, "sms:+393331234567&body=attiva%201-2-3%201966")
    }
}

final class ResolveTests: XCTestCase {
    func makeData() -> (AlarmData, House) {
        var h = House.example()
        h.phoneNumber = "+39 333 0000000"
        h.statusCommand = "stato"
        return (AlarmData(houses: [h]), h)
    }

    func testResolveArmDisarmStatus() throws {
        let (data, h) = makeData()
        let zone = h.zones[0]
        let arm = try data.resolve(.arm(h.id, zone: zone.id), password: "1966").get()
        XCTAssertEqual(arm.body, "attiva 1-2-3 1966")
        XCTAssertEqual(arm.recipient, "+393330000000")
        XCTAssertEqual(arm.kind, .arm)
        XCTAssertEqual(arm.zone?.id, zone.id)
        let dis = try data.resolve(.disarm(nil), password: "1966").get()
        XCTAssertEqual(dis.body, "disattiva 1966")
        XCTAssertEqual(dis.maskedBody, "disattiva ••••")
        let st = try data.resolve(.status(h.id), password: "1966").get()
        XCTAssertEqual(st.body, "stato 1966")
    }

    func testResolveErrors() {
        var (data, h) = makeData()
        XCTAssertEqual(data.resolve(.disarm(h.id), password: ""), .failure(.missingPassword(house: h.name)))
        XCTAssertEqual(data.resolve(.arm(h.id, zone: UUID()), password: "1"), .failure(.zoneNotFound))
        XCTAssertEqual(data.resolve(.disarm(UUID()), password: "1"), .failure(.houseNotFound))
        h.phoneNumber = ""
        data.upsert(h)
        XCTAssertEqual(data.resolve(.disarm(h.id), password: "1"), .failure(.missingPhoneNumber(house: h.name)))
        XCTAssertEqual(AlarmData().resolve(.disarm(nil), password: "1"), .failure(.noHouses))
    }

    func testTemplateWithoutPasswordNeedsNoPassword() throws {
        var (data, h) = makeData()
        h.messageTemplate = "{comando}"
        data.upsert(h)
        XCTAssertEqual(try data.resolve(.disarm(h.id), password: nil).get().body, "disattiva")
    }

    func testActionsList() {
        let (data, h) = makeData()
        let actions = data.actions(for: h)
        XCTAssertEqual(actions.first, .disarm(h.id))
        XCTAssertEqual(actions.count, 1 + h.zones.count + 1)
        XCTAssertEqual(data.describe(.disarm(h.id))?.title, "Disinserisci")
        XCTAssertEqual(data.describe(.arm(h.id, zone: h.zones[1].id))?.title, "Notte")
    }
}

final class LinkTests: XCTestCase {
    func testActionIdRoundTrip() {
        let h = UUID(), z = UUID()
        for ref in [AlarmActionRef.disarm(h), .disarm(nil), .status(h), .arm(h, zone: z), .arm(nil, zone: z)] {
            XCTAssertEqual(AlarmActionRef(id: ref.id), ref)
        }
        XCTAssertNil(AlarmActionRef(id: "garbage"))
        XCTAssertNil(AlarmActionRef(id: "default|zone:nope"))
    }

    func testDeepLinkRoundTrip() {
        let h = UUID(), z = UUID()
        let links: [DeepLink] = [.run(.arm(h, zone: z), source: .widget), .run(.disarm(nil), source: .control), .open(houseID: h), .open(houseID: nil)]
        for l in links {
            XCTAssertEqual(DeepLink(url: l.url), l, l.url.absoluteString)
        }
        XCTAssertNil(DeepLink(url: URL(string: "https://example.com")!))
    }
}

final class StateTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    func testStateFollowsLastSentEvent() {
        var h = House.example()
        h.phoneNumber = "1"
        var data = AlarmData(houses: [h])
        XCTAssertEqual(data.state(for: h.id), .unknown)
        data.record(AlarmEvent(houseID: h.id, zoneID: h.zones[1].id, zoneName: "Notte", kind: .arm, date: t0))
        data.record(AlarmEvent(houseID: h.id, kind: .disarm, result: .cancelled, date: t0.addingTimeInterval(60)))
        data.record(AlarmEvent(houseID: h.id, kind: .status, date: t0.addingTimeInterval(120)))
        let s = data.state(for: h.id)
        XCTAssertTrue(s.isArmed)
        XCTAssertEqual(s.zoneName, "Notte")
        XCTAssertEqual(s.since, t0)
        data.record(AlarmEvent(houseID: h.id, kind: .disarm, source: .manual, date: t0.addingTimeInterval(180)))
        XCTAssertFalse(data.state(for: h.id).isArmed)
    }

    func testArmedIntervals() {
        let h = House.example()
        var data = AlarmData(houses: [h])
        data.record(AlarmEvent(houseID: h.id, zoneID: h.zones[0].id, kind: .arm, date: t0))
        data.record(AlarmEvent(houseID: h.id, zoneID: h.zones[1].id, kind: .arm, date: t0.addingTimeInterval(3600)))
        data.record(AlarmEvent(houseID: h.id, kind: .disarm, date: t0.addingTimeInterval(5400)))
        data.record(AlarmEvent(houseID: h.id, zoneID: h.zones[0].id, kind: .arm, date: t0.addingTimeInterval(7200)))
        let iv = data.armedIntervals(now: t0.addingTimeInterval(9000))
        XCTAssertEqual(iv.map(\.duration), [3600, 1800, 1800])
        XCTAssertEqual(iv.map(\.isOpen), [false, false, true])
    }

    func testRemoveHouseDropsHistory() {
        let h = House.example()
        var data = AlarmData(houses: [h], settings: AppSettings(defaultHouseID: h.id))
        data.record(AlarmEvent(houseID: h.id, kind: .disarm, date: t0))
        data.removeHouse(h.id)
        XCTAssertTrue(data.houses.isEmpty)
        XCTAssertTrue(data.events.isEmpty)
        XCTAssertNil(data.settings.defaultHouseID)
    }
}

final class StatsTests: XCTestCase {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2
        return c
    }()

    func date(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        return f.date(from: s)!
    }

    func testWeekStats() {
        let h = House.example()
        let night = h.zones[1]
        var data = AlarmData(houses: [h])
        // Two nights armed 23:00 → 07:00, one cancelled attempt, one widget disarm.
        data.record(AlarmEvent(houseID: h.id, zoneID: night.id, zoneName: night.name, kind: .arm, date: date("2026-11-17T23:00:00Z")))
        data.record(AlarmEvent(houseID: h.id, kind: .disarm, date: date("2026-11-18T07:00:00Z")))
        data.record(AlarmEvent(houseID: h.id, zoneID: night.id, zoneName: night.name, kind: .arm, date: date("2026-11-18T23:00:00Z")))
        data.record(AlarmEvent(houseID: h.id, kind: .disarm, source: .widget, date: date("2026-11-19T07:00:00Z")))
        data.record(AlarmEvent(houseID: h.id, kind: .disarm, result: .cancelled, date: date("2026-11-19T08:00:00Z")))
        let now = date("2026-11-19T12:00:00Z")
        let s = AlarmStats(data: data, period: .week, now: now, calendar: calendar)
        XCTAssertEqual(s.sent, 4)
        XCTAssertEqual(s.arms, 2)
        XCTAssertEqual(s.disarms, 2)
        XCTAssertEqual(s.cancelled, 1)
        XCTAssertEqual(s.protectedTime, 16 * 3600)
        XCTAssertEqual(s.averageArmDuration, 8 * 3600)
        XCTAssertEqual(s.typicalArmHour, 23)
        XCTAssertEqual(s.typicalDisarmHour, 7)
        XCTAssertEqual(s.zones.first?.name, "Notte")
        XCTAssertEqual(s.zones.first?.count, 2)
        XCTAssertEqual(s.zones.first?.armedTime, 16 * 3600)
        XCTAssertEqual(s.bucketUnit, .day)
        XCTAssertEqual(s.buckets.count, 7)
        XCTAssertEqual(s.buckets.reduce(0) { $0 + $1.total }, 4)
        XCTAssertEqual(s.currentStreak, 2) // armed 17 and 18, none today: counted from yesterday
        XCTAssertEqual(s.sources.first { $0.source == .widget }?.count, 1)
        XCTAssertEqual(s.successRate ?? 0, 0.8, accuracy: 0.0001)
        // Weekday: 17 Nov 2026 is a Tuesday.
        XCTAssertEqual(s.byWeekday[1], 1)
    }

    func testStreak() {
        let h = House.example()
        var data = AlarmData(houses: [h])
        for d in ["2026-11-10", "2026-11-11", "2026-11-12", "2026-11-15", "2026-11-16"] {
            data.record(AlarmEvent(houseID: h.id, zoneID: h.zones[0].id, kind: .arm, date: date("\(d)T22:00:00Z")))
        }
        let s = AlarmStats(data: data, period: .month, now: date("2026-11-16T23:00:00Z"), calendar: calendar)
        XCTAssertEqual(s.currentStreak, 2)
        XCTAssertEqual(s.longestStreak, 3)
    }

    func testIntervalStartedBeforePeriodIsClipped() {
        let h = House.example()
        var data = AlarmData(houses: [h])
        data.record(AlarmEvent(houseID: h.id, zoneID: h.zones[0].id, kind: .arm, date: date("2026-10-01T00:00:00Z")))
        let now = date("2026-11-19T12:00:00Z")
        let s = AlarmStats(data: data, period: .week, now: now, calendar: calendar)
        let expected = now.timeIntervalSince(s.periodStart)
        XCTAssertEqual(s.protectedTime, expected, accuracy: 1)
        XCTAssertEqual(s.protectedShare, 1, accuracy: 0.0001)
        XCTAssertEqual(s.sent, 0)
    }

    func testLongPeriodsUseLargerBuckets() {
        let h = House.example()
        var data = AlarmData(houses: [h])
        data.record(AlarmEvent(houseID: h.id, kind: .disarm, date: date("2026-01-05T10:00:00Z")))
        let now = date("2026-11-19T12:00:00Z")
        XCTAssertEqual(AlarmStats(data: data, period: .quarter, now: now, calendar: calendar).bucketUnit, .week)
        XCTAssertEqual(AlarmStats(data: data, period: .year, now: now, calendar: calendar).bucketUnit, .month)
        let all = AlarmStats(data: data, period: .all, now: now, calendar: calendar)
        XCTAssertEqual(all.sent, 1)
        XCTAssertEqual(all.buckets.reduce(0) { $0 + $1.total }, 1)
    }
}

final class FormatAndPersistenceTests: XCTestCase {
    func testDuration() {
        XCTAssertEqual(AlarmFormat.duration(20), "< 1 min")
        XCTAssertEqual(AlarmFormat.duration(45 * 60), "45 min")
        XCTAssertEqual(AlarmFormat.duration(2 * 3600 + 14 * 60), "2 h 14 min")
        XCTAssertEqual(AlarmFormat.duration(3 * 3600), "3 h")
        XCTAssertEqual(AlarmFormat.duration(3 * 86400 + 4 * 3600), "3 g 4 h")
        XCTAssertEqual(AlarmFormat.percent(0.004), "< 1%")
        XCTAssertEqual(AlarmFormat.percent(0.5), "50%")
    }

    func testCSV() {
        let h = House.example()
        var data = AlarmData(houses: [h])
        data.record(AlarmEvent(houseID: h.id, kind: .disarm, message: "disattiva ••••"))
        let csv = AlarmFormat.csv(data)
        XCTAssertTrue(csv.hasPrefix("Data;Casa;Comando"))
        XCTAssertTrue(csv.contains("Disinserimento"))
        XCTAssertFalse(csv.contains("1966"))
    }

    func testJSONRoundTripAndBackup() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let h = House.example()
        var data = AlarmData(houses: [h], settings: AppSettings(confirmBeforeSending: true))
        data.record(AlarmEvent(houseID: h.id, kind: .disarm, date: Date(timeIntervalSince1970: 1_700_000_000)))
        let store = JSONFileStore<AlarmData>(url: dir.appendingPathComponent("data.json"))
        XCTAssertNil(try store.load())
        try store.save(data)
        XCTAssertEqual(try store.load(), data)

        let backup = BackupFile(data: data, passwords: [h.id: "1966"])
        let encoded = try JSONFileStore<BackupFile>.encoder.encode(backup)
        let decoded = try JSONFileStore<BackupFile>.decoder.decode(BackupFile.self, from: encoded)
        XCTAssertEqual(decoded.data, data)
        XCTAssertEqual(decoded.passwordsByHouse[h.id], "1966")
    }

    func testDecodingToleratesMissingFields() throws {
        let json = #"{"houses":[{"name":"Mare","zones":[{"name":"Notte","command":"attiva 2"}]}]}"#
        let data = try JSONFileStore<AlarmData>.decoder.decode(AlarmData.self, from: Data(json.utf8))
        XCTAssertEqual(data.houses.first?.name, "Mare")
        XCTAssertEqual(data.houses.first?.disarmCommand, "disattiva")
        XCTAssertEqual(data.houses.first?.messageTemplate, MessageBuilder.defaultTemplate)
        XCTAssertEqual(data.houses.first?.zones.first?.command, "attiva 2")
        XCTAssertFalse(data.settings.confirmBeforeSending)
    }

    func testProvisioningGroups() {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>Entitlements</key><dict>
        <key>com.apple.security.application-groups</key><array><string>group.com.garoth93.homealarm.ABCDE12345</string></array>
        </dict></dict></plist>
        """
        var blob = Data([0x30, 0x82, 0x01])
        blob.append(Data(plist.utf8))
        blob.append(Data([0x00, 0xA0]))
        let groups = ProvisioningProfile.appGroups(from: blob)
        XCTAssertEqual(groups, ["group.com.garoth93.homealarm.ABCDE12345"])
        XCTAssertEqual(ProvisioningProfile.pickGroup(configured: "group.com.garoth93.homealarm", available: groups), groups[0])
        XCTAssertEqual(ProvisioningProfile.pickGroup(configured: "group.x", available: ["group.x", "group.y"]), "group.x")
        XCTAssertNil(ProvisioningProfile.pickGroup(configured: "group.x", available: []))
    }
}
