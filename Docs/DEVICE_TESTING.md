# Mac and physical-device acceptance checklist

These are **remaining checks**, not completed results. Start with a backup and synthetic diary data. Fill in the device, iOS build, Xcode version, signing scheme, date and outcome for each run. Recommended matrix: iPhone 14 Pro Max / iOS 27.2; iOS 26 for AlarmKit; iOS 17 or 18 for the fallback path; a small supported iPhone such as SE (3rd generation) or its simulator.

## Build and first launch

- [ ] Build LumaBasic and LumaHealth in Xcode without signing for Simulator; fix every compiler error.
- [ ] Run the core package tests and native UI smoke tests.
- [ ] Provision Basic with the user's Personal Team and install on the iPhone.
- [ ] Provision Health + Widget with the exact same App Group; verify entitlements in the signed products.
- [ ] Fresh launch shows onboarding, correct age guidance and honest empty states.
- [ ] Open all five tabs with no history; no fake metrics or missing-control crashes.
- [ ] Basic Health/widget controls explain availability. iOS 17/18 wake-alarm control directs the user to Clock.

## Tracking and data

- [ ] Save, edit and undo a diary entry spanning midnight; relaunch and confirm it remains.
- [ ] Enter overlapping awakenings, a nap, split sleep and a daylight-saving interval; check totals against known elapsed times.
- [ ] Start bedtime, background, lock, force terminate and relaunch. The saved start time survives and elapsed time derives from it.
- [ ] End a bedside session: the bedside cover dismisses and the morning review opens once.
- [ ] Cancel the morning review: the unconfirmed interval remains time in bed, with no invented sleep.
- [ ] A stale timer longer than 48 hours offers discard instead of silently recording excessive sleep.
- [ ] Import example CSV/JSON, repeat it and verify duplicate reporting; rejected example produces one valid and one rejected row.
- [ ] Export a JSON backup, modify data, restore and check original records/revisions. Export and inspect the pre-restore rollback copy.
- [ ] Feed a malformed/future-schema backup; original data remains intact. A corrupt local file opens Recovery, not an empty database.
- [ ] Enter/exit demo; real records remain unchanged and no sensor, Health query or scheduled notification/alarm action occurs.

## Health and motion

- [ ] Grant Health reading with no data; copy stays neutral about permission versus missing records.
- [ ] Grant reading with real samples; stage/source/time metadata match Health. No write permission is requested.
- [ ] Import from two sources with overlaps, reorder priority and verify both originals remain visible.
- [ ] Delete a test source record in Health, foreground Luma and check its tombstone and changed total; repeat refresh without duplicates.
- [ ] Revoke or restrict reading; errors/empty results do not falsely report read denial. Cached history remains until the user deletes it.
- [ ] Test a third-party wearable only through the records its own app actually writes; document absent stages.
- [ ] Request and deny Motion & Fitness; appropriate state appears. Grant and query history, then confirm a suggestion manually.
- [ ] Leave the phone stationary while awake: Luma must not automatically count that interval as sleep.

## Audio

- [ ] Deny microphone, then grant it in Settings; starting works and errors are understandable.
- [ ] In default mode, inspect the app container and verify no raw recording file is created.
- [ ] Record a short controlled session, then lock the screen and background for at least 15 minutes; timestamps/events persist.
- [ ] Test a phone call, audio-route change and media-service interruption. Status says interrupted and a new start is required.
- [ ] Force terminate during monitoring; relaunch shows an interrupted session with unknown exact end, never an active microphone indicator.
- [ ] Opt into retention; verify playback/export, Data Protection while locked, low-storage refusal, duration/file limits and storage-error stop.
- [ ] Change retention to one day; with an expired fixture, relaunch and verify raw-file cleanup while event summaries remain.
- [ ] Delete an individual recording/events, restore a backup and delete all app data; retained files should not remain orphaned.
- [ ] Measure overnight battery impact with event-only and retained modes; do not publish a battery claim without measurements.

## Alarms, reminders, Shortcuts and widget

- [ ] Schedule an AlarmKit alarm a few minutes ahead on iOS 26+; test unlocked, locked, backgrounded and terminated.
- [ ] Repeat with Focus and silent mode, then revoke alarm permission and verify clear failure feedback.
- [ ] Replace the fixed alarm and confirm only the intended alarm remains; cancel it, relaunch and verify state from AlarmManager.
- [ ] Test a reboot, first unlock and free-provisioning expiration/renewal before treating Luma as a reliable wake mechanism.
- [ ] Enable reminders, deny/revoke notification permission, and test Focus restrictions. UI must never promise an ordinary notification will wake you.
- [ ] Change weekday/weekend times, explicitly Apply, and inspect all seven weekdays including reminders on the preceding day.
- [ ] Test timezone/DST changes: repeating reminder timezone is explicit, fixed alarms remain absolute instants; reapply schedules as needed.
- [ ] Run each Shortcut; the app opens, duplicate bedtime start fails cleanly, end opens review and nap bounds are enforced.
- [ ] Add widget, enable/disable sharing and confirm only target/wind-down are shared; allow for system-controlled refresh delays.

## Appearance and accessibility

- [ ] Light and midnight mode on both small and large phones: no clipped controls, unreadable labels or horizontal overflow.
- [ ] Largest accessibility text size; long notes/tags/source names; calendar and editor remain usable.
- [ ] VoiceOver order, button names, chart summaries, errors, permission controls and sleep-stage distinctions.
- [ ] Reduce Motion and increased contrast; no essential state communicated only by color.
- [ ] Interactive chart selection and dates in the chosen reporting timezone; source detail explains local display versus source metadata.
- [ ] Device screen captures of every destination, empty states, bedside mode and a failed permission flow; fix layout issues before release.

## Update and release decision

- [ ] Install an updated build over the same team/bundle ID; diary, active timer and settings survive.
- [ ] Renew Personal Team provisioning without deleting the app; check behavior around expiration.
- [ ] Switch Basic to Health with a backup and matching identity; verify data and widget settings.
- [ ] Mark every enabled hardware-dependent feature as passed or document its specific failure. Disable unresolved experiments before relying on nightly use.
