import XCTest
@testable import InstaCore

final class ZipTests: XCTestCase {
    func testInflateLargeDynamicBlock() throws {
        let raw = [UInt8](Data(base64Encoded: inflateFixtureBase64.replacingOccurrences(of: "\n", with: ""))!)
        let out = try XCTUnwrap(Inflate.inflate(raw))
        XCTAssertEqual(out.count, inflateFixtureLength)
        XCTAssertEqual(CRC32.checksum(out), inflateFixtureCRC)
    }

    func testCorruptedDeflateFails() {
        XCTAssertNil(Inflate.inflate([0xFF, 0xFF, 0xFF]))
    }

    func testZipEntries() throws {
        let zip = try MiniZip(data: Data(base64Encoded: exportZipBase64)!)
        let names = zip.entries.map(\.baseName)
        XCTAssertTrue(names.contains("followers_1.json"))
        XCTAssertTrue(names.contains("photo.jpg"))
        XCTAssertFalse(zip.entries.contains { $0.name.hasSuffix("/") })
        let photo = try XCTUnwrap(zip.entries.first { $0.baseName == "photo.jpg" })
        XCTAssertEqual(zip.read(photo)?.count, 2 + 256 * 40)
    }

    func testNotAZip() {
        XCTAssertThrowsError(try MiniZip(data: Data("hello".utf8)))
    }

    func testZipFromFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("instagram-mario.test-2025-05-16-AbCd.zip")
        try Data(base64Encoded: exportZipBase64)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let e = try ExportReader.read(url: url)
        XCTAssertEqual(e.owner, "mario.test")
        XCTAssertEqual(e.count(.follower), 2)
    }
}

final class ExportReaderTests: XCTestCase {
    func parsedZip(name: String = "instagram-mario.test-2025-05-16-AbCd") throws -> ParsedExport {
        let zip = try MiniZip(data: Data(base64Encoded: exportZipBase64)!)
        let c = try ExportReader.collectZip(zip)
        return try ExportReader.parse(files: c.files, sawHtml: c.sawHtml, sourceName: name)
    }

    func testAllFormats() throws {
        let e = try parsedZip()
        XCTAssertEqual(e.owner, "mario.test") // from personal_information.json
        XCTAssertEqual(e.lists[.follower]?.map(\.username), ["anna.verdi", "marco_rossi"])
        XCTAssertEqual(e.lists[.follower]?[1].since, 1_700_100_000) // milliseconds normalized
        XCTAssertEqual(Set(e.lists[.following]?.map(\.username) ?? []), ["anna.verdi", "brand.shop", "luca99"])
        XCTAssertEqual(e.lists[.closeFriend]?.first?.fullName, "Anna Verdi")
        XCTAssertEqual(e.lists[.closeFriend]?.first?.since, 1_699_000_000)
    }

    func testDateFromNameAndNewestFollow() throws {
        let e = try parsedZip()
        // name says 2025-05-16 12:00 UTC, newer than all follows
        XCTAssertEqual(e.takenAt.timeIntervalSince1970, 1_747_396_800)
        let old = try parsedZip(name: "instagram-mario.test-2020-01-01-x")
        XCTAssertEqual(old.takenAt.timeIntervalSince1970, 1_700_100_000) // bumped to newest follow
    }

    func testExportName() {
        XCTAssertEqual(ExportReader.parseExportName("instagram-mario.rossi-2025-05-16-AbCdEf")?.owner, "mario.rossi")
        XCTAssertEqual(ExportReader.parseExportName("Instagram-Ale_Film-2024-12-01-xyz")?.owner, "ale_film")
        XCTAssertNil(ExportReader.parseExportName("export.zip"))
    }

    func testHtmlExport() throws {
        let zip = try MiniZip(data: Data(base64Encoded: htmlZipBase64)!)
        let c = try ExportReader.collectZip(zip)
        XCTAssertThrowsError(try ExportReader.parse(files: c.files, sawHtml: c.sawHtml, sourceName: "x")) { err in
            XCTAssertEqual(err as? ExportError, .htmlFormat)
        }
        XCTAssertThrowsError(try ExportReader.parse(files: [], sourceName: "x")) { err in
            XCTAssertEqual(err as? ExportError, .noData)
        }
    }

    func testUsernameHelpers() {
        XCTAssertTrue(ExportReader.isValidUsername("a.b_c9"))
        XCTAssertFalse(ExportReader.isValidUsername("Abc"))
        XCTAssertFalse(ExportReader.isValidUsername(""))
        XCTAssertEqual(ExportReader.usernameFromHref("https://www.instagram.com/_u/luca99"), "luca99")
        XCTAssertEqual(ExportReader.usernameFromHref("https://www.instagram.com/anna/"), "anna")
        XCTAssertEqual(ExportReader.kind(for: "followers_12.json"), .rel(.follower))
        XCTAssertNil(ExportReader.kind(for: "followers_x.json"))
        XCTAssertEqual(ExportReader.kind(for: "follow_requests_you've_received.json"), .rel(.requestRecv))
    }

    func testFolderImport() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("instagram-luca.dir-2025-01-02-z")
        let sub = dir.appendingPathComponent("connections/followers_and_following")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(#"[{"string_list_data":[{"value":"x.y","timestamp":1}]}]"#.utf8).write(to: sub.appendingPathComponent("followers_1.json"))
        try Data(#"{"relationships_following":[{"title":"z","string_list_data":[{"timestamp":2}]}]}"#.utf8).write(to: sub.appendingPathComponent("following.json"))
        let e = try ExportReader.read(url: dir)
        XCTAssertEqual(e.owner, "luca.dir")
        XCTAssertEqual(e.lists[.follower]?.map(\.username), ["x.y"])
        XCTAssertEqual(e.lists[.following]?.map(\.username), ["z"])
    }
}

final class AnalysisTests: XCTestCase {
    func export(followers: [String], following: [String], owner: String = "me", day: Double = 0, pending: [String] = []) -> ParsedExport {
        ParsedExport(owner: owner, takenAt: Date(timeIntervalSince1970: 1_700_000_000 + day * 86400),
                     lists: [.follower: followers.map { Entry(username: $0, since: 1_600_000_000) },
                             .following: following.map { Entry(username: $0, since: 1_650_000_000) },
                             .pendingSent: pending.map { Entry(username: $0) }])
    }

    func testViewsAndStats() {
        var data = InstaData()
        guard case .added(let first, _, _) = data.importExport(export(followers: ["a", "b", "c"], following: ["a", "b", "x", "y"]), preferredOwner: nil) else { return XCTFail() }
        guard case .added(let second, _, _) = data.importExport(export(followers: ["a", "c", "d"], following: ["a", "x", "z"], day: 10, pending: ["p"]), preferredOwner: nil) else { return XCTFail() }
        let an = Analysis(data: data, owner: "me", currentID: second, compareID: first)
        XCTAssertEqual(an.rows(for: .notBack).map(\.username), ["x", "z"])
        XCTAssertEqual(an.rows(for: .fans).map(\.username), ["c", "d"])
        XCTAssertEqual(an.rows(for: .mutual).map(\.username), ["a"])
        XCTAssertEqual(an.rows(for: .newFollowers).map(\.username), ["d"])
        XCTAssertEqual(an.rows(for: .lostFollowers).map(\.username), ["b"])
        XCTAssertEqual(an.rows(for: .newFollowing).map(\.username), ["z"])
        XCTAssertEqual(an.rows(for: .dropped).map(\.username), ["b", "y"])
        XCTAssertEqual(an.rows(for: .pending).map(\.username), ["p"])
        XCTAssertEqual(an.stats.followers, 3)
        XCTAssertEqual(an.stats.followersDelta, 0)
        XCTAssertEqual(an.stats.followingDelta, -1)
        XCTAssertEqual(an.stats.days, 10)
        XCTAssertEqual(an.stats.mutualPercent, 33)
        XCTAssertEqual(an.row("b")?.status, "Ti ha smesso di seguire")
        XCTAssertEqual(an.rows(for: .notBack, search: "@Z").map(\.username), ["z"])
        // without comparison the change lists are empty
        let single = Analysis(data: data, owner: "me", currentID: second, compareID: nil)
        XCTAssertEqual(single.count(.newFollowers), 0)
        XCTAssertFalse(single.stats.hasCompare)
    }

    func testMarksKeepAndUnfollow() {
        var data = InstaData()
        guard case .added(let id, _, _) = data.importExport(export(followers: ["a"], following: ["a", "x", "y"]), preferredOwner: nil) else { return XCTFail() }
        data.setMark("me", "x", state: .keep)
        data.setMark("me", "y", state: .unfollow)
        data.setNote("me", "y", note: "brand")
        var an = Analysis(data: data, owner: "me", currentID: id, compareID: nil)
        XCTAssertEqual(an.rows(for: .notBack).map(\.username), ["y"])   // kept hidden
        XCTAssertEqual(an.rows(for: .kept).map(\.username), ["x"])
        XCTAssertEqual(an.rows(for: .toUnfollow).first?.note, "brand")
        data.settings.showKept = true
        an = Analysis(data: data, owner: "me", currentID: id, compareID: nil)
        XCTAssertEqual(an.rows(for: .notBack).map(\.username), ["x", "y"])
        // clearing state but keeping the note keeps the mark record
        data.setMark("me", "y", state: .none)
        XCTAssertEqual(data.mark("me", "y").note, "brand")
        data.setNote("me", "y", note: "")
        XCTAssertNil(data.marks["me"]?["y"])
    }

    func testImportResolvesUnfollowAndDetectsDuplicates() {
        var data = InstaData()
        let e1 = export(followers: ["a"], following: ["a", "x", "y"])
        _ = data.importExport(e1, preferredOwner: nil)
        data.setMark("me", "x", state: .unfollow)
        data.setMark("me", "y", state: .unfollow)
        XCTAssertEqual(data.importExport(e1, preferredOwner: nil), .duplicate(id: data.snapshots[0].id, owner: "me"))
        let out = data.importExport(export(followers: ["a"], following: ["a", "y"], day: 5), preferredOwner: nil)
        guard case .added(_, _, let resolved) = out else { return XCTFail() }
        XCTAssertEqual(resolved, 1)
        XCTAssertEqual(data.mark("me", "x").state, .none)
        XCTAssertEqual(data.mark("me", "y").state, .unfollow)
        XCTAssertEqual(data.snapshots(of: "me").count, 2)
    }

    func testDefaultOwnerMergedIntoFirstNamedOwner() {
        var data = InstaData()
        _ = data.importExport(export(followers: ["a"], following: ["b"], owner: ""), preferredOwner: nil)
        XCTAssertEqual(data.owners, [InstaData.defaultOwner])
        data.setMark(InstaData.defaultOwner, "b", state: .keep)
        _ = data.importExport(export(followers: ["a", "c"], following: ["b"], owner: "real", day: 3), preferredOwner: nil)
        XCTAssertEqual(data.owners, ["real"])
        XCTAssertEqual(data.mark("real", "b").state, .keep)
    }

    func testSortingAndSubtitles() {
        var data = InstaData()
        var e = export(followers: [], following: [])
        e.lists[.following] = [Entry(username: "old", since: 100), Entry(username: "new", since: 300), Entry(username: "mid", since: 200)]
        guard case .added(let id, _, _) = data.importExport(e, preferredOwner: nil) else { return XCTFail() }
        let an = Analysis(data: data, owner: "me", currentID: id, compareID: nil)
        XCTAssertEqual(an.rows(for: .notBack, sort: .newest).map(\.username), ["new", "mid", "old"])
        XCTAssertEqual(an.rows(for: .notBack, sort: .oldest).map(\.username), ["old", "mid", "new"])
        XCTAssertTrue(an.row("new")!.subtitle(for: .notBack).hasPrefix("Lo segui dal "))
    }

    func testInitialsAndColors() {
        var r = AccountRow(username: "ale_film")
        XCTAssertEqual(r.initials, "AF")
        r = AccountRow(username: "marco.rossi99")
        XCTAssertEqual(r.initials, "MR")
        r = AccountRow(username: "alelab", fullName: "Alessio Bianchi")
        XCTAssertEqual(r.initials, "AB")
        XCTAssertEqual(AccountRow(username: "alelab").initials, "AL")
        XCTAssertEqual(InstaFormat.avatarColor("x"), InstaFormat.avatarColor("x"))
    }

    func testHistoryAndCSV() {
        var data = InstaData()
        _ = data.importExport(export(followers: ["a"], following: ["a"]), preferredOwner: nil)
        guard case .added(let id, _, _) = data.importExport(export(followers: [], following: ["a"], day: 2), preferredOwner: nil) else { return XCTFail() }
        let h = data.history(owner: "me", username: "a", currentID: id)
        XCTAssertEqual(h.map(\.follower), [true, false])
        XCTAssertEqual(h.last?.isCurrent, true)
        let an = Analysis(data: data, owner: "me", currentID: id, compareID: nil)
        let csv = InstaFormat.csv(an.rows(for: .following))
        XCTAssertTrue(csv.hasPrefix("\u{FEFF}username;nome;profilo"))
        XCTAssertTrue(csv.contains("\"https://www.instagram.com/a\";no;sì"))
    }

    func testRenameAndSnapshotOps() {
        var data = InstaData()
        guard case .added(let id, _, _) = data.importExport(export(followers: ["a"], following: ["b"]), preferredOwner: nil) else { return XCTFail() }
        data.setMark("me", "b", state: .keep)
        data.renameOwner("me", to: "nuovo")
        XCTAssertEqual(data.owners, ["nuovo"])
        XCTAssertEqual(data.mark("nuovo", "b").state, .keep)
        data.renameSnapshot(id, label: "  Primo  ")
        XCTAssertEqual(data.snapshots[0].label, "Primo")
        data.deleteSnapshot(id)
        XCTAssertTrue(data.snapshots.isEmpty)
    }

    func testPersistenceRoundTrip() throws {
        var data = InstaData()
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        _ = data.importExport(export(followers: ["a"], following: ["b"]), preferredOwner: nil, now: now)
        data.setMark("me", "b", state: .unfollow, now: now)
        let encoded = try JSONFileStore<InstaData>.encoder.encode(data)
        let decoded = try JSONFileStore<InstaData>.decoder.decode(InstaData.self, from: encoded)
        XCTAssertEqual(decoded, data)
    }
}

final class MergeTests: XCTestCase {
    func testMergeSkipsDuplicatesAndKeepsExistingMarks() {
        var data = InstaData()
        let e = ParsedExport(owner: "me", takenAt: Date(timeIntervalSince1970: 1_700_000_000),
                             lists: [.follower: [Entry(username: "a")], .following: [Entry(username: "b")]])
        _ = data.importExport(e, preferredOwner: nil)
        let same = Snapshot(owner: "me", label: "desktop", takenAt: Date(), signature: "sha1-from-desktop",
                            lists: [1: [Entry(username: "a")], 2: [Entry(username: "b")]])
        XCTAssertFalse(data.merge(snapshot: same))
        let other = Snapshot(owner: "me", label: "desktop 2", takenAt: Date(), lists: [1: [Entry(username: "a"), Entry(username: "c")]])
        XCTAssertTrue(data.merge(snapshot: other))
        XCTAssertEqual(data.snapshots.count, 2)
        data.setMark("me", "b", state: .keep)
        let added = data.merge(marks: ["me": ["b": MarkInfo(state: .unfollow), "c": MarkInfo(state: .keep)]])
        XCTAssertEqual(added, 1)
        XCTAssertEqual(data.mark("me", "b").state, .keep)
        XCTAssertEqual(data.mark("me", "c").state, .keep)
    }
}
