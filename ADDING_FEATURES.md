# Adding features safely

Start by reading `ARCHITECTURE.md`, `Docs/DATA_FORMATS.md` and the test results. Keep data transformations in the core, native permission work in an integration, and screen composition in a feature file. Add the smallest clear interface needed; do not introduce a plugin framework just to add a screen.

## Common extensions

| New work | Where it belongs | Required checks |
| --- | --- | --- |
| Tracking source | `App/Integrations`, conform to `SleepImportSource` or a source-specific adapter; return canonical `SleepRecord` values | Stable namespaced IDs, offsets/timezones, duplicates, source deletion, refused permission, no fabricated stage |
| Metric | Pure function in `Core/Sources/LumaCore`; presentation in Insights/Today | Missing-data behavior, coverage/sample size, determinism and evidence/limitations |
| Screen | `App/Features`, use existing design tokens; add a NavigationLink to the appropriate destination | Small phone, large text, VoiceOver labels, empty/error and demo states |
| Permission | Integration adapter plus an accurate Info.plist description; entitlements only if required | Denied/restricted, later revocation, background behavior and both build schemes |
| Persistence field | Versioned Codable model and explicit migration in `SnapshotCodec` | Old backup load, new round trip, future-version rejection, corrupt-data preservation |
| Experimental integration | Build/availability gate with an honest unavailable message | Keep it out of the normal experience until it has a meaningful implementation and device evidence |

Do not couple a new metric to a tracking screen. Do not change source records to make UI output look nicer. Corrections and classification must remain explicit and reversible. Never introduce a new network service without reviewing the privacy flow with the owner.

## Worked example: a dream journal

A dream journal needs a small private text model, one editor and navigation from History. It needs **no new system permission**. Do not use HealthKit or microphone access merely to save text.

### 1. Add a core model

Create `Core/Sources/LumaCore/DreamEntry.swift`:

```swift
import Foundation

public struct DreamEntry: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var sleepDay: Date
    public var timeZoneID: String
    public var text: String
    public var updatedAt: Date

    public init(id: UUID = UUID(), sleepDay: Date,
                timeZoneID: String, text: String, updatedAt: Date) {
        self.id = id
        self.sleepDay = sleepDay
        self.timeZoneID = timeZoneID
        self.text = text
        self.updatedAt = updatedAt
    }
}
```

This is an example for the next feature, not already-enabled app functionality. If dream edits need the same undo guarantees as sleep entries, use a revision array from the beginning instead of destructively replacing text.

### 2. Migrate schema 2 to schema 3

In `Models.swift`, add `public var dreams: [DreamEntry] = []` to `Snapshot`, and change its default schema version to 3. In `SnapshotCodec.decode`:

1. Accept only versions 1, 2 and 3.
2. Keep the existing v1-to-v2 normalization unchanged.
3. For any normalized object with version 2, insert an empty `dreams` array and set `schemaVersion` to 3.
4. Decode the result, then validate schema 3. Update the validation guard from `== 2` to `== 3`.
5. Validate unique dream IDs, a real timezone and a bounded text length (for example 20,000 characters); reject inconsistent backups before writing.

The Codable default alone does not make a missing key compatible with synthesized decoding. The explicit migration matters. Keep a checked-in v2 fixture with nonempty diary history and confirm it survives the upgrade unchanged.

### 3. Add store actions

Add methods to `AppStore.swift`, for example `saveDream(_:)` and `deleteDream(id:)`, implemented exclusively through `transact`. Set dates with `store.now`. Never write a separate JSON file from a view. The existing snapshot-based backup and demo routing then include dreams automatically after the migration. Extend `DemoData` with clearly marked sample dream text only if the demo should show it.

### 4. Add the UI and link it

Create `App/Features/DreamJournalView.swift` with an editor using `TextEditor`, a visible Save button, empty-state copy and deletion confirmation. Reuse `LumaPage`, `Surface` and `PrimaryButton`; use a semantic text style and accessible labels. Label its association with a sleep day in the selected reporting timezone.

Add a `NavigationLink("Dream journal")` to `DayDetailView` in `HistoryView.swift`, passing `day.date`. Do not add a sixth primary tab for one editor. Link notes by day/ID, not by a formatted date string. Show dreams as subjective diary content; do not invent psychological diagnoses or sleep-stage explanations.

### 5. Add meaningful tests

Create `Core/Tests/LumaCoreTests/DreamMigrationTests.swift` covering:

- A v2 fixture migrates to v3 with an empty journal while preserving records, corrections and diary revisions.
- A v3 backup round trip preserves nonempty Unicode dream text and timezone.
- A v4 backup is rejected without a save.
- Duplicate IDs or an oversized note are rejected.
- App-store save/delete in demo mode cannot alter the real snapshot (use an injected temporary store in a native app test).

Add a UI smoke test for opening a sleep day, saving text, relaunching and reading the same note. Keep real user data and HealthKit out of the tests.

### 6. Regenerate and verify

Run `python3 Scripts/generate_project.py`, core tests, the project audit and both simulator builds. Test the editor on the smaller iPhone and with the largest accessibility text size. Confirm the JSON export includes dreams, deletion clears them, and no unexpected permission prompt appears. Update `DATA_FORMATS.md`, the capability/status table and the device checklist before considering the feature complete.

## Configuration locations

- iOS minimum, bundle ID and build versions: `Config/Base.xcconfig`.
- Personal signing overrides: `Config/User.xcconfig` (untracked).
- Health and widget compilation: generator schemes and `HEALTH_ENABLED`.
- Target, sleep-day boundary, wake/settling/wind-down and retention defaults: `Preferences` in `Models.swift`.
- Heuristic energy parameters: `SleepInsights.energy` in `Insights.swift`.
- Sound threshold, batching, duration and file cap: `LevelProcessor` in `AudioMonitor.swift`; document any change and remeasure battery/false detections.
- Import/snapshot limits and schema versions: `ImportExport.swift` and `Persistence.swift`.
- Colors, type, spacing and components: `DesignSystem.swift`.
