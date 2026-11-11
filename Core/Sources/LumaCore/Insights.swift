import Foundation
public struct Shortfall: Sendable {
    public var hours: Double
    public var observedDays: Int
    public var totalDays: Int
}
public struct HabitComparison: Sendable {
    public var tag: String
    public var withCount: Int
    public var withoutCount: Int
    public var withMean: Double
    public var withoutMean: Double
}
public struct EnergyPoint: Identifiable, Sendable {
    public var date: Date
    public var value: Double
    public var id: Date { date }
    public var label: String { value >= 3.6 ? "Higher estimate" : value <= 2.6 ? "Lower estimate" : "Moderate estimate" }
}
public enum SleepInsights {
    public static func shortfall(days: [SleepDay], target: Double) -> Shortfall {
        let values=days.compactMap(\.hours)
        return Shortfall(hours: values.reduce(0) { $0+max(0,target-$1) },observedDays:values.count,totalDays:days.count)
    }
    /// Circular standard deviation avoids the false midnight discontinuity.
    public static func timingVariation(wakeDates: [Date], calendar: Calendar) -> Double? {
        guard wakeDates.count >= 3 else { return nil }
        let angles=wakeDates.map { d -> Double in let v=calendar.dateComponents([.hour,.minute],from:d); return Double((v.hour ?? 0)*60+(v.minute ?? 0))/1440*2*Double.pi }
        let x=angles.map(cos).reduce(0,+)/Double(angles.count), y=angles.map(sin).reduce(0,+)/Double(angles.count)
        let r=min(1,max(0.000001,hypot(x,y)))
        return sqrt(-2*log(r))*1440/(2*Double.pi)
    }
    public static func habit(_ tag: String, diaries: [DiaryEntry]) -> HabitComparison? {
        let usable=diaries.filter { !$0.isDeleted && $0.current.sleepStart != nil && $0.current.kind != .nap }
        func hours(_ d: DiaryEntry) -> Double { SleepReconciler.resolve(d.current.records(diaryID:d.id),priority:[]).asleepSeconds/3600 }
        let a=usable.filter { $0.current.tags.contains(tag) }.map(hours)
        let b=usable.filter { !$0.current.tags.contains(tag) }.map(hours)
        guard a.count >= 3, b.count >= 3 else { return nil }
        return HabitComparison(tag:tag,withCount:a.count,withoutCount:b.count,withMean:a.reduce(0,+)/Double(a.count),withoutMean:b.reduce(0,+)/Double(b.count))
    }
    /// Planning heuristic, not a validated physiological or performance prediction.
    public static func energy(wake: Date, days: [SleepDay], target: Double, checkIns: [EnergyCheckIn]) -> [EnergyPoint] {
        guard days.compactMap(\.hours).count >= 3 else { return [] }
        let recent=days.suffix(7).compactMap(\.hours)
        let mean=recent.reduce(0,+)/Double(max(1,recent.count))
        let penalty=min(0.8,max(0,target-mean)*0.2)
        let valid=checkIns.filter { $0.date >= wake.addingTimeInterval(-14*86400) && $0.date <= wake && (1...5).contains($0.value) }
        // Small whole-curve adjustment only; never infer exact chronotype from sparse check-ins.
        let adjustment=valid.count >= 7 ? min(0.3,max(-0.3,Double(valid.map(\.value).reduce(0,+))/Double(valid.count)-3)) : 0
        return (0...32).map { step in
            let h=Double(step)/2
            let inertia=0.9*exp(-h/0.8)
            let middayDip=0.7*exp(-pow((h-7)/1.7,2))
            let lateFall=max(0,h-11)*0.22
            let value=min(5,max(1,3.8-inertia-middayDip-lateFall-penalty+adjustment))
            return EnergyPoint(date:wake.addingTimeInterval(h*3600),value:value)
        }
    }
}
public struct BedtimePlan: Sendable {
    public var wake: Date
    public var bedtime: Date
    public var windDown: Date
}
public enum SleepPlanner {
    public static func plan(wake: Date, preferences: Preferences) -> BedtimePlan {
        let bedtime=wake.addingTimeInterval(-(preferences.targetHours*3600+Double(preferences.settlingMinutes)*60))
        return BedtimePlan(wake:wake,bedtime:bedtime,windDown:bedtime.addingTimeInterval(-Double(preferences.windDownMinutes)*60))
    }
    public static func nextWake(after now: Date, preferences p: Preferences) -> Date {
        let cal=SleepCalendar.calendar(zoneID:p.reportingTimeZoneID)
        for offset in 0...8 {
            let day=cal.date(byAdding:.day,value:offset,to:now)!
            let minutes=cal.isDateInWeekend(day) ? p.weekendWakeMinutes : p.weekdayWakeMinutes
            if let wake=cal.date(bySettingHour:minutes/60,minute:minutes%60,second:0,of:day), wake > now { return wake }
        }
        return now.addingTimeInterval(86400)
    }
}
