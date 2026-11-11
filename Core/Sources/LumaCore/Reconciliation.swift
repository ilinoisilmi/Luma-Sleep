import Foundation

public struct ResolvedSegment: Identifiable, Sendable {
    public var id: String { "\(start.timeIntervalSince1970):\(end.timeIntervalSince1970):\(record.id)" }
    public var start: Date
    public var end: Date
    public var record: SleepRecord
    public var hasConflict: Bool
    public var duration: TimeInterval { end.timeIntervalSince(start) }
}
public struct ResolvedSleep: Sendable {
    public var segments: [ResolvedSegment]
    public var inBed: [DateInterval]
    public var asleepSeconds: Double { segments.filter { $0.record.stage.isAsleep }.reduce(0) { $0+$1.duration } }
    public var inBedSeconds: Double { inBed.reduce(0) { $0+$1.duration } }
    public var efficiency: Double? {
        // Only report when every asleep segment is covered by actual in-bed evidence.
        let sleep=segments.filter { $0.record.stage.isAsleep }
        guard !sleep.isEmpty, inBedSeconds > 0, sleep.allSatisfy({ s in inBed.contains { $0.start <= s.start && $0.end >= s.end } }) else { return nil }
        return asleepSeconds/inBedSeconds
    }
}
public enum SleepReconciler {
    public static func union(_ intervals: [DateInterval]) -> [DateInterval] {
        let sorted = intervals.filter { $0.duration > 0 }.sorted { $0.start < $1.start }
        var out: [DateInterval]=[]
        for next in sorted {
            if let last=out.last, next.start <= last.end { out[out.count-1]=DateInterval(start: last.start, end: max(last.end,next.end)) }
            else { out.append(next) }
        }
        return out
    }
    public static func resolve(_ input: [SleepRecord], priority: [String], within window: DateInterval? = nil) -> ResolvedSleep {
        let records=input.filter { r in r.start < r.end && (window == nil || (r.start < window!.end && r.end > window!.start)) }
        func clipped(_ r: SleepRecord) -> DateInterval { DateInterval(start: max(r.start,window?.start ?? r.start),end: min(r.end,window?.end ?? r.end)) }
        let bed=union(records.filter { $0.stage == .inBed }.map(clipped))
        let samples=records.filter { $0.stage != .inBed }
        let edges=Set(samples.flatMap { [clipped($0).start,clipped($0).end] }).sorted()
        func rank(_ r: SleepRecord) -> Int { r.sourceID == "correction" ? -1 : (priority.firstIndex(of: r.sourceID) ?? priority.count) }
        func stageRank(_ s: SleepStage) -> Int { switch s { case .awake: return 0; case .deep: return 1; case .rem: return 2; case .core: return 3; case .asleep: return 4; case .inBed: return 5 } }
        var segments: [ResolvedSegment]=[]
        if edges.count > 1 {
            for i in 0..<(edges.count-1) {
                let start=edges[i], end=edges[i+1]
                let candidates=samples.filter { $0.start < end && $0.end > start }.sorted {
                    if rank($0) != rank($1) { return rank($0) < rank($1) }
                    // Stable fallback between unranked sources; within a source, awake beats asleep.
                    if $0.sourceID != $1.sourceID { return $0.sourceID < $1.sourceID }
                    if stageRank($0.stage) != stageRank($1.stage) { return stageRank($0.stage) < stageRank($1.stage) }
                    return $0.id < $1.id
                }
                if let best=candidates.first {
                    let conflict=candidates.contains { $0.stage != best.stage }
                    segments.append(ResolvedSegment(start:start,end:end,record:best,hasConflict:conflict))
                }
            }
        }
        return ResolvedSleep(segments:segments,inBed:bed)
    }
}
public struct SleepDay: Identifiable, Sendable {
    public var date: Date
    public var window: DateInterval
    public var sleep: ResolvedSleep
    public var id: Date { date }
    public var hours: Double? { sleep.segments.contains { $0.record.stage.isAsleep } ? sleep.asleepSeconds/3600 : nil }
    public var napHours: Double { sleep.segments.filter { $0.record.kind == .nap && $0.record.stage.isAsleep }.reduce(0) { $0+$1.duration/3600 } }
}
public enum SleepCalendar {
    public static func calendar(zoneID: String) -> Calendar { var c=Calendar(identifier: .gregorian); c.timeZone=TimeZone(identifier: zoneID) ?? .current; return c }
    public static func window(endingOn date: Date, calendar: Calendar, boundaryHour: Int) -> DateInterval {
        let day=calendar.startOfDay(for: date)
        let end=calendar.date(bySettingHour: boundaryHour, minute:0, second:0, of:day)!
        let start=calendar.date(byAdding:.day,value:-1,to:end)!
        return DateInterval(start:start,end:end)
    }
    public static func days(records: [SleepRecord], endingOn date: Date, count: Int, preferences p: Preferences) -> [SleepDay] {
        let c=calendar(zoneID:p.reportingTimeZoneID)
        return (0..<max(0,count)).reversed().map { offset in
            let d=c.date(byAdding:.day,value:-offset,to:c.startOfDay(for:date))!
            let w=window(endingOn:d,calendar:c,boundaryHour:p.boundaryHour)
            return SleepDay(date:d,window:w,sleep:SleepReconciler.resolve(records,priority:p.sourcePriority,within:w))
        }
    }
}
