import Foundation
import CoreMotion
struct MotionSuggestion:Identifiable {
    var id=UUID()
    var start:Date
    var end:Date
    var version:DiaryVersion {
        var v=DiaryVersion(bedtime:start,sleepStart:nil,wake:end,outOfBed:end,timeZoneID:TimeZone.current.identifier)
        v.method = .motion; v.notes="Window suggested by stationary phone activity; reviewed by me. Phone motion does not establish sleep."
        return v
    }
}
@MainActor final class MotionImporter {
    private let manager=CMMotionActivityManager()
    var available:Bool { CMMotionActivityManager.isActivityAvailable() }
    func suggest(from start:Date,to end:Date) async throws -> [MotionSuggestion] {
        guard available else { throw LumaError.unavailable("Motion activity history is unavailable on this device.") }
        guard CMMotionActivityManager.authorizationStatus() != .denied && CMMotionActivityManager.authorizationStatus() != .restricted else { throw LumaError.unavailable("Motion access is off. You can review it in iPhone Settings → Privacy & Security → Motion & Fitness.") }
        let activities:[CMMotionActivity]=try await withCheckedThrowingContinuation { continuation in
            manager.queryActivityStarting(from:max(start,end.addingTimeInterval(-7*86400)),to:end,to:.main) { data,error in
                if let error { continuation.resume(throwing:error) } else { continuation.resume(returning:data ?? []) }
            }
        }
        let sorted=activities.sorted{$0.startDate < $1.startDate}
        var intervals:[DateInterval]=[]
        for (i,a) in sorted.enumerated() {
            // Last event is deliberately not extended to 'now': activity history may be delayed.
            guard i+1<sorted.count, a.stationary, !a.walking, !a.running, !a.cycling, !a.automotive, a.confidence != .low else { continue }
            let from=max(a.startDate,start), to=min(sorted[i+1].startDate,end)
            if from<to { intervals.append(DateInterval(start:from,end:to)) }
        }
        return SleepReconciler.union(intervals).filter{$0.duration>=3600 && $0.duration<=16*3600}.sorted{$0.duration>$1.duration}.prefix(5).map{MotionSuggestion(start:$0.start,end:$0.end)}
    }
}
