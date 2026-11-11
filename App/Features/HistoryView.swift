import SwiftUI
struct HistoryView:View {
    @EnvironmentObject private var store:AppStore
    @State private var range=7
    @State private var selected=Date()
    var body:some View {
        let days=SleepCalendar.days(records:store.data.effectiveRecords,endingOn:selected,count:range,preferences:store.data.preferences)
        LumaPage {
            SectionTitle(title:"Every night tells a story.")
            DatePicker("End date",selection:$selected,in:...Date(),displayedComponents:.date).datePickerStyle(.graphical).environment(\.timeZone,TimeZone(identifier:store.data.preferences.reportingTimeZoneID) ?? .current)
            Picker("History range",selection:$range) { Text("Day").tag(1); Text("Week").tag(7); Text("Month").tag(30) }.pickerStyle(.segmented)
            SleepBarChart(days:days,target:store.data.preferences.targetHours,zoneID:store.data.preferences.reportingTimeZoneID)
            Text("Dashed line: your target. Cross: no recorded sleep. Tap or drag on a bar for its total.").font(.caption).foregroundStyle(.secondary)
            ForEach(days.reversed()) { day in
                NavigationLink { DayDetailView(day:day) } label: {
                    HStack(alignment:.top) {
                        VStack(alignment:.leading,spacing:5) { Text(Luma.day(day.date,zoneID:store.data.preferences.reportingTimeZoneID)).font(.headline); Text(day.napHours > 0 ? "Includes \(Luma.duration(day.napHours*3600)) of naps" : day.hours == nil ? "Unknown · no sleep estimate" : "Recorded sleep").font(.caption).foregroundStyle(.secondary) }
                        Spacer(); Text(day.hours.map{Luma.duration($0*3600)} ?? "—").font(.title3.weight(.medium)); Image(systemName:"chevron.right").font(.caption).padding(.top,5)
                    }.padding(.vertical,10)
                }.buttonStyle(.plain)
                Divider()
            }
        }.navigationTitle("History").navigationBarTitleDisplayMode(.inline)
    }
}
struct DayDetailView:View {
    @EnvironmentObject private var store:AppStore
    let day:SleepDay
    @State private var editing:DiaryEntry?
    @State private var correction=false
    var records:[SleepRecord] { store.data.effectiveRecords.filter{$0.start < day.window.end && $0.end > day.window.start} }
    var resolved:ResolvedSleep { SleepReconciler.resolve(records,priority:store.data.preferences.sourcePriority,within:day.window) }
    var body:some View {
        LumaPage {
            SectionTitle(title:Luma.day(day.date,zoneID:store.data.preferences.reportingTimeZoneID),subtitle:"\(Luma.duration(resolved.asleepSeconds)) recorded sleep")
            if !resolved.segments.isEmpty { StageTimeline(sleep:resolved) }
            Surface {
                LabeledContent("Recorded time in bed",value:resolved.inBedSeconds > 0 ? Luma.duration(resolved.inBedSeconds) : "Unknown")
                LabeledContent("Sleep efficiency",value:resolved.efficiency.map{($0*100).formatted(.number.precision(.fractionLength(0)))+"%"} ?? "Not enough evidence")
                Text("Times are displayed in this iPhone’s local timezone. Source timezone labels preserve available provenance.").font(.caption).foregroundStyle(.secondary)
                Text("Sources: \(Set(records.map(\.sourceName)).sorted().joined(separator:", "))").font(.footnote).foregroundStyle(.secondary)
                if resolved.segments.contains(where:{$0.hasConflict}) { Text("Overlapping records disagree. Your source order resolves each interval. Original records remain available below.").font(.footnote).foregroundStyle(Luma.warm) }
            }
            ForEach(store.data.diaries.filter{!$0.isDeleted && $0.current.bedtime < day.window.end && $0.current.outOfBed > day.window.start}) { entry in
                Surface {
                    HStack { Text(entry.current.kind == .nap ? "Nap diary" : "Sleep diary").font(.headline); Spacer(); if let q=entry.current.qualityRating { Text("Quality \(q)/5").font(.caption) } }
                    if !entry.current.notes.isEmpty { Text(entry.current.notes) }
                    if !entry.current.tags.isEmpty { Text(entry.current.tags.joined(separator:" · ")).font(.subheadline).foregroundStyle(.secondary) }
                    Button("Edit or review") { editing=entry }
                    if entry.versions.count>1 { Button("Undo last edit") { store.perform { try store.transact { s in if let i=s.diaries.firstIndex(where:{$0.id == entry.id}) { s.diaries[i].undoRevision() } } } } }
                    Button("Hide this diary entry",role:.destructive) { store.perform { try store.transact { s in if let i=s.diaries.firstIndex(where:{$0.id == entry.id}) { s.diaries[i].isDeleted=true } } } }
                }
            }
            if !records.isEmpty { Button("Correct these source records",systemImage:"pencil") { correction=true }; Text("This replaces the entire source intervals shown below, including portions outside this sleep day, with your reported window. Originals are preserved. Use separate diary entries for split sleep.").font(.caption).foregroundStyle(.secondary) }
            DisclosureGroup("Source records") {
                ForEach(records) { record in VStack(alignment:.leading,spacing:4) { Text("\(record.stage.label) · \(record.sourceName)").font(.subheadline.weight(.medium)); Text("\(record.start.formatted(date:.abbreviated,time:.shortened)) – \(record.end.formatted(date:.abbreviated,time:.shortened))").font(.caption); Text("\(record.quality.rawValue.capitalized) · Source zone: \(record.timeZoneID)").font(.caption).foregroundStyle(.secondary) }.padding(.vertical,6) }
            }
            NavigationLink("Revisions & hidden entries") { RevisionsView() }
        }.navigationTitle("Sleep detail").navigationBarTitleDisplayMode(.inline)
        .sheet(item:$editing) { DiaryEditor(version:$0.current,entryID:$0.id) }
        .sheet(isPresented:$correction) {
            let start=records.map(\.start).min() ?? day.window.start
            let end=records.map(\.end).max() ?? day.window.end
            DiaryEditor(version:DiaryVersion(bedtime:start,sleepStart:start,wake:end,outOfBed:end,timeZoneID:store.data.preferences.reportingTimeZoneID),replacing:records.map(\.id))
        }
    }
}
struct RevisionsView:View {
    @EnvironmentObject private var store:AppStore
    var body:some View {
        List {
            Section("Corrections") {
                if store.data.corrections.isEmpty { Text("No corrections yet.") }
                ForEach(store.data.corrections.reversed()) { c in
                    VStack(alignment:.leading,spacing:8) { Text(c.reason); Text(c.createdAt,style:.date).font(.caption); Button(c.isUndone ? "Apply again" : "Undo correction") { store.perform { try store.transact { s in if let i=s.corrections.firstIndex(where:{$0.id == c.id}) { s.corrections[i].isUndone.toggle() } } } } }
                }
            }
            Section("Hidden diary entries") {
                ForEach(store.data.diaries.filter(\.isDeleted)) { d in Button("Restore \(d.current.bedtime.formatted(date:.abbreviated,time:.shortened))") { store.perform { try store.transact { s in if let i=s.diaries.firstIndex(where:{$0.id == d.id}) { s.diaries[i].isDeleted=false } } } } }
            }
        }.navigationTitle("Revisions")
    }
}
