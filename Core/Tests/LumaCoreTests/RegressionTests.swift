import XCTest
@testable import LumaCore
final class RegressionTests:XCTestCase {
    func d(_ s:String)->Date { SleepLogFormat.date(s)! }
    func record(id:String="a",start:Date,end:Date,stage:SleepStage = .asleep)->SleepRecord {
        SleepRecord(id:id,sourceID:"test",sourceName:"Test",method:.file,start:start,end:end,timeZoneID:"Europe/Skopje",stage:stage)
    }
    func testUnconfirmedBedtimeDoesNotBecomeZeroSleepOrShortfall() {
        let bed=record(start:d("2026-11-01T22:00:00Z"),end:d("2026-11-02T07:00:00Z"),stage:.inBed)
        var p=Preferences();p.reportingTimeZoneID="UTC"
        let days=SleepCalendar.days(records:[bed],endingOn:d("2026-11-02T12:00:00Z"),count:1,preferences:p)
        XCTAssertNil(days[0].hours)
        XCTAssertEqual(SleepInsights.shortfall(days:days,target:9).observedDays,0)
    }
    func testBoundarySplitConservesElapsedTime() {
        let sleep=record(start:d("2026-11-01T16:00:00Z"),end:d("2026-11-01T20:00:00Z"))
        var p=Preferences();p.reportingTimeZoneID="UTC";p.boundaryHour=18
        let days=SleepCalendar.days(records:[sleep],endingOn:d("2026-11-02T12:00:00Z"),count:2,preferences:p)
        XCTAssertEqual(days.compactMap(\.hours),[2,2])
        XCTAssertEqual(days.reduce(0){$0+$1.sleep.asleepSeconds},4*3600)
    }
    func testReportingZoneChangeDoesNotChangeSourceInstants() {
        let sleep=record(start:d("2026-11-01T22:00:00+01:00"),end:d("2026-11-02T06:00:00+01:00"))
        var p=Preferences();p.reportingTimeZoneID="Asia/Tokyo"
        let days=SleepCalendar.days(records:[sleep],endingOn:d("2026-11-03T12:00:00Z"),count:4,preferences:p)
        XCTAssertEqual(days.reduce(0){$0+$1.sleep.asleepSeconds},8*3600)
        XCTAssertEqual(sleep.start,d("2026-11-01T21:00:00Z"))
    }
    func testBlankSourceIDRejectedBeforeNamespaceIsAdded() throws {
        let csv=String(data:SleepLogFormat.exampleCSV(),encoding:.utf8)!.replacingOccurrences(of:"diary-export",with:"")
        let p=try SleepLogFormat.preview(Data(csv.utf8),format:"csv",existing:[])
        XCTAssertEqual(p.rejected.count,1);XCTAssertTrue(p.accepted.isEmpty)
    }
    func testRepeatedRowsWithinOneImportAreDeduplicated() throws {
        let csv=String(data:SleepLogFormat.exampleCSV(),encoding:.utf8)!
        let repeated=csv+csv.split(separator:"\n")[1]+"\n"
        let p=try SleepLogFormat.preview(Data(repeated.utf8),format:"csv",existing:[])
        XCTAssertEqual(p.accepted.count,1);XCTAssertEqual(p.duplicates,1)
    }
    func testInvalidBackupCannotOverwriteExistingSnapshot() throws {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("snapshot.json")
        defer{try? FileManager.default.removeItem(at:url.deletingLastPathComponent())}
        let store=JSONSnapshotStore(url:url);var snapshot=Snapshot();snapshot.preferences.targetHours=8.25
        try store.save(snapshot);let original=try Data(contentsOf:url)
        XCTAssertThrowsError(try SnapshotCodec.decode(Data("broken JSON".utf8)))
        XCTAssertEqual(try Data(contentsOf:url),original)
    }
    func testDuplicateDiaryIDsRejected() throws {
        var s=Snapshot()
        let v=DiaryVersion(bedtime:d("2026-11-01T22:00:00Z"),sleepStart:nil,wake:d("2026-11-02T07:00:00Z"),outOfBed:d("2026-11-02T07:00:00Z"),timeZoneID:"UTC")
        let entry=DiaryEntry(version:v);s.diaries=[entry,entry]
        XCTAssertThrowsError(try SnapshotCodec.encode(s))
    }
    func testDuplicateRevisionIDsRejected() throws {
        var s=Snapshot()
        let v=DiaryVersion(bedtime:d("2026-11-01T22:00:00Z"),sleepStart:nil,wake:d("2026-11-02T07:00:00Z"),outOfBed:d("2026-11-02T07:00:00Z"),timeZoneID:"UTC")
        var entry=DiaryEntry(version:v);entry.versions.append(v);s.diaries=[entry]
        XCTAssertThrowsError(try SnapshotCodec.encode(s))
    }
    func testMaliciousAudioPathRejected() throws {
        var s=Snapshot();var audio=AudioSession(start:Date());audio.fileName="../../private.m4a";s.audioSessions=[audio]
        XCTAssertThrowsError(try SnapshotCodec.encode(s))
    }
    func testEndedSessionCannotEndAgain() throws {
        var s=Snapshot();try SessionActions.start(snapshot:&s,at:d("2026-11-01T22:00:00Z"),zone:"UTC",kind:.main)
        try SessionActions.end(snapshot:&s,at:d("2026-11-02T07:00:00Z"))
        XCTAssertThrowsError(try SessionActions.end(snapshot:&s,at:d("2026-11-02T08:00:00Z")))
        XCTAssertEqual(s.diaries.count,1)
    }
    func testDiaryRevisionUndoPreservesOriginalVersion() throws {
        let a=DiaryVersion(bedtime:d("2026-11-01T22:00:00Z"),sleepStart:nil,wake:d("2026-11-02T07:00:00Z"),outOfBed:d("2026-11-02T07:00:00Z"),timeZoneID:"UTC")
        var entry=DiaryEntry(version:a);var b=a;b.id=UUID();b.sleepStart=d("2026-11-01T23:00:00Z");entry.revise(b)
        XCTAssertEqual(entry.current.sleepStart,b.sleepStart);entry.undoRevision()
        XCTAssertNil(entry.current.sleepStart);XCTAssertEqual(entry.versions.count,2)
    }
    func testNapOverlappingMainSleepNeverCountsTwice() {
        let a=record(start:d("2026-11-01T22:00:00Z"),end:d("2026-11-02T07:00:00Z"))
        var nap=record(id:"b",start:d("2026-11-02T06:00:00Z"),end:d("2026-11-02T08:00:00Z"));nap.kind = .nap
        XCTAssertEqual(SleepReconciler.resolve([a,nap],priority:[]).asleepSeconds,10*3600)
    }
}
