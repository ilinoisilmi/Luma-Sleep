# Sleep-log imports and backups

## CSV and JSON sleep logs

Files must be UTF-8 and at most 10 MB, with at most 20,000 records. Use **Track → Import a sleep log**. Luma previews accepted rows, duplicates and rejected rows before the valid records are committed. Rejected records are not silently repaired. The example files in `Examples/` are downloadable with this project; the app can export examples too.

The exact CSV header and order are:

```csv
id,source_id,source_name,start,end,timezone,stage,kind
```

| Field | Required value |
| --- | --- |
| `id` | Nonblank stable identifier, unique within this source; keep it stable on repeated exports |
| `source_id` | Nonblank stable source identifier, for example `diary-export` |
| `source_name` | Nonblank display name; CSV quoting handles commas and newlines |
| `start` / `end` | ISO 8601 timestamps with `Z` or explicit `±HH:MM` offset; fractional seconds accepted on input; end must be later than start |
| `timezone` | Valid IANA timezone, such as `Europe/Skopje`; retained as provenance |
| `stage` | One of `inBed`, `awake`, `asleep`, `core`, `deep`, `rem` |
| `kind` | One of `main`, `nap`, `unspecified` |

Each record spans at most 48 elapsed hours. Multiple records can describe split sleep or stages. `asleep` means unspecified asleep; never synthesize deep/REM stages if the source did not supply them. In-bed rows are separate from asleep rows. Known awake intervals override generic asleep records within a source. Gaps are unknown.

JSON uses the same field names, all as strings, inside this envelope:

```json
{
  "formatVersion": 1,
  "records": [
    {
      "id": "night-001",
      "source_id": "diary-export",
      "source_name": "My diary",
      "start": "2026-11-01T23:00:00+01:00",
      "end": "2026-11-02T07:30:00+01:00",
      "timezone": "Europe/Skopje",
      "stage": "asleep",
      "kind": "main"
    }
  ]
}
```

The explicit offsets determine absolute instants. The IANA zone preserves context; duration is not computed by subtracting wall-clock strings. This handles midnight, travel and daylight-saving transitions. A timezone label without an offset cannot disambiguate a repeated local clock time and is rejected.

Luma namespaces file source IDs with `file:`. The stored record ID combines that source and the external record ID. Reimporting the same ID and interval is skipped; changing time/stage/kind under an existing ID is rejected for review. An identical source/start/end/stage/kind row under a different ID is also skipped. Imported records keep reported provenance, not a numerical confidence percentage.

The in-app preview numbers data rows starting at 2 for both formats (CSV-header convention). A CSV export contains the current effective record projection, not revision history. A file-import → CSV-export → file-import round trip preserves canonical rows; importing a diary/Health CSV creates a separate file source. Overlap reconciliation still prevents double counting. Use a complete JSON backup to preserve original identity, corrections and settings.

## Complete JSON backups

Use **Settings → Export, restore & delete → Export complete JSON backup**. This format uses `schemaVersion`, not `formatVersion`, and must be opened with **Restore**, not the sleep-log importer.

Schema 2 stores `records`, `deletedSourceIDs`, `diaries` with all `versions` and the `activeVersionID`, `corrections`, `activeSession`, `checkIns`, `audioSessions`, and `preferences`, with optional Health metadata. The portable export clears the Health anchor. Dates are UTC ISO strings at whole-second precision; subsecond recordings are outside this format's scope. Raw microphone files are excluded. A snapshot may not exceed 50 MB. Corrupt fields, duplicate collection identifiers, unsupported versions and unsafe audio filenames are rejected.

The v1 migration keeps records and compatible preferences, supplies missing collections and new preference defaults, then validates schema 2. `Examples/migration-v1.json` is a minimal fixture. Later schema versions must add explicit migration steps; do not rely on default Swift property values to accept missing Codable keys.

Restore replaces the current snapshot after a preview and preserves a local pre-restore copy when the current data is readable. It resets the device-specific Health anchor, disables reminder/widget settings, stops audio and removes retained raw recordings. It does not resume an imported microphone session. A separately scheduled fixed wake alarm is independent and is not replaced by a backup; review it in Planning. Previously exported files and Apple Health source data are outside Luma's deletion scope.

Backup files contain sensitive notes and are **not encrypted** by the export format. Choose their destination deliberately. Protect exported audio separately. Device Data Protection applies to Luma's local container, not arbitrary exported copies.
