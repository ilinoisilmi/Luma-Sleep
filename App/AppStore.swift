import SwiftUI
import Combine
import WidgetKit

@MainActor final class AppStore: ObservableObject {
    static let shared:AppStore = {
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            let url=FileManager.default.temporaryDirectory.appendingPathComponent("LumaUITests.json")
            if ProcessInfo.processInfo.arguments.contains("--reset-ui-testing") { try? FileManager.default.removeItem(at:url) }
            return AppStore(store:JSONSnapshotStore(url:url))
        }
        return AppStore()
    }()
    @Published private(set) var snapshot=Snapshot()
    @Published private var demoSnapshot: Snapshot?
    @Published var message: String?
    @Published var recoveryMessage: String?
    @Published var selectedTab=0
    @Published var pendingReviewID: UUID?
    @Published var busy=false
    let clock: any LumaClock
    private let store: any SnapshotStore
    let health:any SleepImportSource
    let motion=MotionImporter()
    let reminders=ReminderService()
    let alarms=WakeAlarmService()
    lazy var audio=AudioMonitor(store:self)
    static var dataDirectory: URL {
        FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("LumaSleep",isDirectory:true)
    }
    init(store: (any SnapshotStore)? = nil, clock: any LumaClock = SystemClock(), health: (any SleepImportSource)? = nil) {
        self.health=health ?? HealthImporter()
        self.store=store ?? JSONSnapshotStore(url:Self.dataDirectory.appendingPathComponent("sleep-v2.json")); self.clock=clock
        do {
            snapshot=try self.store.load()
            var recovered=snapshot
            for i in recovered.audioSessions.indices where recovered.audioSessions[i].end == nil {
                recovered.audioSessions[i].status="Interrupted by app exit; final stop time unknown"
                recovered.audioSessions[i].end=recovered.audioSessions[i].events.last?.date ?? recovered.audioSessions[i].start
            }
            try self.store.save(recovered); snapshot=recovered
        } catch { recoveryMessage="Your saved data could not be opened. It has not been overwritten. Export the existing file before restoring a backup. \(error.localizedDescription)" }
    }
    var data: Snapshot { demoSnapshot ?? snapshot }
    var isDemo: Bool { demoSnapshot != nil }
    var now: Date { clock.now }
    var days: [SleepDay] { SleepCalendar.days(records:data.effectiveRecords,endingOn:now,count:14,preferences:data.preferences) }
    var plan: BedtimePlan { SleepPlanner.plan(wake:SleepPlanner.nextWake(after:now,preferences:data.preferences),preferences:data.preferences) }
    var latestSleep: ResolvedSleep { days.last?.sleep ?? SleepReconciler.resolve([],priority:[]) }
    func transact(_ action: (inout Snapshot) throws -> Void) throws {
        guard recoveryMessage == nil else { throw LumaError.unavailable("Restore a valid backup before changing records.") }
        var next=data; try action(&next); try SnapshotCodec.validate(next)
        if isDemo { demoSnapshot=next } else { try store.save(next); snapshot=next; publishWidget() }
    }
    func perform(_ action: () throws -> Void) { do { try action() } catch { message=error.localizedDescription } }
    func updatePreferences(_ action: (inout Preferences) -> Void) { perform { try transact { action(&$0.preferences); if $0.preferences.ageBand == "13–17" { $0.preferences.targetHours=max(8,$0.preferences.targetHours) } } } }
    func startBedtime(kind: SleepKind = .main) {
        perform { try transact { try SessionActions.start(snapshot:&$0,at:now,zone:TimeZone.current.identifier,kind:kind) } }
    }
    func endBedtime() {
        perform {
            var review: UUID?
            try transact { review=try SessionActions.end(snapshot:&$0,at:now) }
            audio.stop(reason:"Stopped with bedtime session")
            pendingReviewID=review; selectedTab=1
        }
    }
    func saveDiary(_ version: DiaryVersion, editing id: UUID? = nil, replacing ids: [String] = []) throws {
        try version.validate()
        try transact { s in
            if !ids.isEmpty { s.corrections.append(Correction(originalIDs:ids,replacements:version.records(diaryID:UUID(),sourceID:"correction",sourceName:"Your correction"),reason:"User-corrected window")) }
            else if let id, let index=s.diaries.firstIndex(where:{$0.id == id}) { s.diaries[index].revise(version) }
            else { s.diaries.append(DiaryEntry(version:version)) }
        }
    }
    func checkIn(_ value: Int) { perform { try transact { $0.checkIns.append(EnergyCheckIn(date:now,value:value)) } } }
    func toggleDemo() {
        if isDemo { demoSnapshot=nil }
        else {
            guard snapshot.activeSession == nil, !audio.isRunning else { message="End your active recording or bedtime session before entering demo mode."; return }
            demoSnapshot=DemoData.snapshot(now:now)
        }
    }
    func syncHealth(requestAccess: Bool = false) async {
        guard !isDemo else { message="Health import is disabled in demo mode."; return }
        guard !busy else { return }; busy=true; defer { busy=false }
        do {
            if requestAccess { try await health.requestAccess() }
            let delta=try await health.sync(anchor:snapshot.healthAnchor)
            try transact { s in
                var map=Dictionary(s.records.map{($0.id,$0)},uniquingKeysWith:{a,_ in a})
                for r in delta.added { map[r.id]=r; s.deletedSourceIDs.remove(r.id) }
                s.records=map.values.sorted{$0.start < $1.start}
                s.deletedSourceIDs.formUnion(delta.deletedIDs)
                s.healthAnchor=delta.anchor; s.lastHealthSync=now
            }
            if requestAccess { message=delta.added.isEmpty ? "No new readable sleep records. Health may have no sleep data, access may be limited, or read access may be off. Luma cannot tell which." : "Imported \(delta.added.count) Health records. Sources are listed in Settings." }
        } catch { message=error.localizedDescription }
    }
    func backup() throws -> Data {
        var copy=data
        copy.healthAnchor=nil // Health anchors belong to this device/store, not portable backups.
        return try SnapshotCodec.encode(copy)
    }
    func restore(_ bytes: Data) throws {
        guard !isDemo else { throw LumaError.invalid("Exit demo mode before restoring real data.") }
        var restored=try SnapshotCodec.decode(bytes)
        restored.healthAnchor=nil; restored.lastHealthSync=nil
        restored.preferences.remindersEnabled=false; restored.preferences.widgetEnabled=false
        for i in restored.audioSessions.indices {
            restored.audioSessions[i].fileName=nil
            if restored.audioSessions[i].end == nil { restored.audioSessions[i].end=now; restored.audioSessions[i].status="Restored metadata; recording not resumed" }
        }
        // Preserve a rollback copy before replacing the real store.
        let backupURL=Self.dataDirectory.appendingPathComponent("before-restore.json")
        if recoveryMessage == nil { try SnapshotCodec.encode(snapshot).write(to:backupURL,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication]) }
        audio.stop(reason:"Stopped for restore")
        try store.save(restored)
        snapshot=restored; recoveryMessage=nil; reminders.cancelAll(); publishWidget()
        let audioFolder=Self.dataDirectory.appendingPathComponent("Audio")
        if FileManager.default.fileExists(atPath:audioFolder.path) {
            do { try FileManager.default.removeItem(at:audioFolder) }
            catch { message="Backup restored, but old retained recordings could not be removed. Use Delete all data if you want to clear them. \(error.localizedDescription)" }
        }
    }
    func deleteAll() async throws {
        guard !isDemo else { demoSnapshot=Snapshot(); return }
        audio.stop(reason:"Deleted")
        try await alarms.cancel()
        reminders.cancelAll()
        var empty=Snapshot(); empty.preferences.onboardingComplete=true
        try store.save(empty); snapshot=empty
        let folder=Self.dataDirectory.appendingPathComponent("Audio")
        if FileManager.default.fileExists(atPath:folder.path) { try FileManager.default.removeItem(at:folder) }
        let rollback=Self.dataDirectory.appendingPathComponent("before-restore.json")
        if FileManager.default.fileExists(atPath:rollback.path) { try FileManager.default.removeItem(at:rollback) }
        publishWidget()
    }
    func foreground() async {
        guard !isDemo, recoveryMessage == nil else { return }
        audio.prune()
        if snapshot.lastHealthSync != nil { await syncHealth() }
        await alarms.refresh()
    }
    func publishWidget() {
        #if HEALTH_ENABLED
        guard let group=Bundle.main.object(forInfoDictionaryKey:"LumaAppGroup") as? String,
              let defaults=UserDefaults(suiteName:group) else { return }
        defaults.set(snapshot.preferences.widgetEnabled,forKey:"enabled")
        if snapshot.preferences.widgetEnabled {
            defaults.set(snapshot.preferences.targetHours,forKey:"target")
            defaults.set(SleepPlanner.plan(wake:SleepPlanner.nextWake(after:now,preferences:snapshot.preferences),preferences:snapshot.preferences).windDown.timeIntervalSince1970,forKey:"windDown")
        } else { defaults.removeObject(forKey:"target"); defaults.removeObject(forKey:"windDown") }
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
