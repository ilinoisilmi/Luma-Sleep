import Foundation
#if HEALTH_ENABLED
import HealthKit
#endif
struct HealthDelta {
    var added:[SleepRecord]
    var deletedIDs:Set<String>
    var anchor:Data?
}
@MainActor protocol SleepImportSource {
    var available:Bool { get }
    var explanation:String { get }
    func requestAccess() async throws
    func sync(anchor:Data?) async throws -> HealthDelta
}
@MainActor final class HealthImporter:SleepImportSource {
    #if HEALTH_ENABLED
    private let store=HKHealthStore()
    var available:Bool { HKHealthStore.isHealthDataAvailable() }
    var explanation:String { "Reads sleep records written to Apple Health. Apple Watch and other devices are supported only through records they actually share with Health. No wearable is required for the diary." }
    func requestAccess() async throws {
        guard available else { throw LumaError.unavailable("Apple Health is unavailable on this device.") }
        let type=HKObjectType.categoryType(forIdentifier:.sleepAnalysis)!
        try await store.requestAuthorization(toShare:[],read:[type])
        // A successful authorization request does NOT establish read authorization.
    }
    func sync(anchor:Data?) async throws -> HealthDelta {
        guard available else { throw LumaError.unavailable("Apple Health is unavailable on this device.") }
        var cursor:HKQueryAnchor?
        if let anchor { cursor=try NSKeyedUnarchiver.unarchivedObject(ofClass:HKQueryAnchor.self,from:anchor) }
        let type=HKObjectType.categoryType(forIdentifier:.sleepAnalysis)!
        var added:[SleepRecord]=[], deleted:Set<String>=[]
        for _ in 0..<250 {
            let page:([HKSample],[HKDeletedObject],HKQueryAnchor?)=try await withCheckedThrowingContinuation { continuation in
                let query=HKAnchoredObjectQuery(type:type,predicate:nil,anchor:cursor,limit:1000) { _, samples, removed, next, error in
                    if let error { continuation.resume(throwing:error) }
                    else { continuation.resume(returning:(samples ?? [],removed ?? [],next)) }
                }
                store.execute(query)
            }
            for sample in page.0 {
                guard let sample=sample as? HKCategorySample else { continue }
                let stage:SleepStage
                switch sample.value {
                case HKCategoryValueSleepAnalysis.inBed.rawValue: stage = .inBed
                case HKCategoryValueSleepAnalysis.awake.rawValue: stage = .awake
                case HKCategoryValueSleepAnalysis.asleepCore.rawValue: stage = .core
                case HKCategoryValueSleepAnalysis.asleepDeep.rawValue: stage = .deep
                case HKCategoryValueSleepAnalysis.asleepREM.rawValue: stage = .rem
                case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue: stage = .asleep
                default: continue // Never reinterpret an unknown future category as asleep.
                }
                let source=sample.sourceRevision.source
                let device=sample.device?.name ?? ""
                let zone=(sample.metadata?[HKMetadataKeyTimeZone] as? String).flatMap{TimeZone(identifier:$0)}?.identifier ?? TimeZone.current.identifier
                added.append(SleepRecord(id:"health:"+sample.uuid.uuidString,sourceID:"health:"+source.bundleIdentifier+":"+source.name,sourceName:source.name+(device.isEmpty ? "" : " · "+device),method:.health,start:sample.startDate,end:sample.endDate,timeZoneID:zone,stage:stage,quality:(sample.metadata?[HKMetadataKeyWasUserEntered] as? Bool == true) ? .reported : .imported))
            }
            deleted.formUnion(page.1.map{"health:"+$0.uuid.uuidString}); cursor=page.2
            if page.0.count+page.1.count < 1000 {
                let encoded=try cursor.map { try NSKeyedArchiver.archivedData(withRootObject:$0,requiringSecureCoding:true) }
                return HealthDelta(added:added,deletedIDs:deleted,anchor:encoded)
            }
        }
        throw LumaError.invalid("Health history exceeds this import's safety limit. No new anchor was committed; contact the developer to add paged persistence.")
    }
    #else
    var available:Bool { false }
    var explanation:String { "This is the Basic build. To enable Apple Health, build the LumaHealth scheme on your Mac and provision its HealthKit capability. Your diary works without it." }
    func requestAccess() async throws { throw LumaError.unavailable(explanation) }
    func sync(anchor:Data?) async throws -> HealthDelta { throw LumaError.unavailable(explanation) }
    #endif
}
