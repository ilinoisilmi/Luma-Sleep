import Foundation
public enum DemoData {
    /// Deterministic, conspicuously labeled demo. Never merged into the real store.
    public static func snapshot(now: Date) -> Snapshot {
        var s=Snapshot(); s.preferences.onboardingComplete=true; s.preferences.targetHours=9
        let cal=SleepCalendar.calendar(zoneID:s.preferences.reportingTimeZoneID)
        let durations:[Double]=[8.4,8.9,7.6,9.0,8.1,8.7,9.2,7.8,8.8,8.5,9.1,8.0,8.6,8.75]
        for i in 0..<14 {
            let day=cal.date(byAdding:.day,value:-(13-i),to:now)!
            let wake=cal.date(bySettingHour:7,minute:15,second:0,of:day)!
            let asleep=wake.addingTimeInterval(-durations[i]*3600)
            var v=DiaryVersion(bedtime:asleep.addingTimeInterval(-1200),sleepStart:asleep,wake:wake,outOfBed:wake.addingTimeInterval(600),timeZoneID:cal.timeZone.identifier)
            v.tags=i%2 == 0 ? ["Exercise"] : ["Late caffeine"]
            v.qualityRating=i%3+3; v.notes="Demo night. This is not your sleep data."
            s.diaries.append(DiaryEntry(version:v))
            s.checkIns.append(EnergyCheckIn(date:wake.addingTimeInterval(4*3600),value:i%3+3))
        }
        return s
    }
}
