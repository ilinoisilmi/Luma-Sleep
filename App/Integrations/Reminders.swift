import Foundation
import UserNotifications
@MainActor protocol ReminderScheduling {
    func install(preferences:Preferences) async throws
    func cancelAll()
}
@MainActor final class ReminderService:ReminderScheduling {
    private let center=UNUserNotificationCenter.current()
    func install(preferences p:Preferences) async throws {
        guard try await center.requestAuthorization(options:[.alert,.sound,.badge]) else { throw LumaError.unavailable("Notifications are off. Enable them in iPhone Settings to receive reminders.") }
        // Repeating weekday notifications follow the fixed reporting timezone until rescheduled.
        let cal=SleepCalendar.calendar(zoneID:p.reportingTimeZoneID)
        let base=Date()
        var requests:[UNNotificationRequest]=[]
        for weekday in 1...7 {
            let minutes=(weekday == 1 || weekday == 7) ? p.weekendWakeMinutes : p.weekdayWakeMinutes
            var components=DateComponents(); components.weekday=weekday; components.hour=minutes/60; components.minute=minutes%60
            guard let wake=cal.nextDate(after:base,matching:components,matchingPolicy:.nextTime,repeatedTimePolicy:.first) else { continue }
            let plan=SleepPlanner.plan(wake:wake,preferences:p)
            for (kind,date,title,body) in [("wind",plan.windDown,"A softer landing","Your wind-down time is here."),("bed",plan.bedtime,"Make room for rest","Your planned bedtime is here.")] {
                var match=cal.dateComponents([.weekday,.hour,.minute],from:date); match.timeZone=cal.timeZone
                let content=UNMutableNotificationContent(); content.title=title; content.body=body; content.sound = .default
                requests.append(UNNotificationRequest(identifier:"luma.\(kind).\(weekday)",content:content,trigger:UNCalendarNotificationTrigger(dateMatching:match,repeats:true)))
            }
        }
        cancelAll()
        do { for request in requests { try await center.add(request) } }
        catch { cancelAll(); throw error }
    }
    func habit(at date:Date,title:String) async throws {
        guard date>Date() else { throw LumaError.invalid("Choose a future time.") }
        guard try await center.requestAuthorization(options:[.alert,.sound]) else { throw LumaError.unavailable("Notification permission is off.") }
        let content=UNMutableNotificationContent(); content.title="Your habit reminder"; content.body=title; content.sound = .default
        try await center.add(UNNotificationRequest(identifier:"luma.habit",content:content,trigger:UNTimeIntervalNotificationTrigger(timeInterval:date.timeIntervalSinceNow,repeats:false)))
    }
    func cancelAll() { center.removePendingNotificationRequests(withIdentifiers:(1...7).flatMap{["luma.wind.\($0)","luma.bed.\($0)"]}+["luma.habit"]); center.removeAllDeliveredNotifications() }
}
