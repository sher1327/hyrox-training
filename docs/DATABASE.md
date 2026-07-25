# SQLite database design (v7)

Database: `hyrox.db`, with foreign keys enabled and schema version `7`.

## Relationships

```text
training_session 1 ─── 1..n station_record
training_session 1 ─── 0..n heart_rate_sample
training_template 1 ─── 1..n template_segment
training_template 0..1 ─── 0..n training_session
```

## `training_session`

| Column | Type | Notes |
|---|---|---|
| id | INTEGER PK AUTOINCREMENT | Local identity |
| mode | TEXT | `single`, `double`, `relay` |
| title | TEXT | User-visible name |
| partner_name | TEXT nullable | First teammate; used by double and relay |
| partner_name_2 | TEXT nullable | Second relay teammate |
| partner_name_3 | TEXT nullable | Third relay teammate |
| status | TEXT | `draft`, `in_progress`, `completed`, `cancelled` |
| started_at_ms | INTEGER nullable | UTC epoch ms |
| ended_at_ms | INTEGER nullable | UTC epoch ms |
| total_duration_ms | INTEGER nullable | Frozen report value |
| avg_heart_rate | INTEGER nullable | Rebuilt after a heart-rate import |
| max_heart_rate | INTEGER nullable | Rebuilt after a heart-rate import |
| heart_rate_source | TEXT nullable | `fit` or `intervals_icu` |
| heart_rate_external_id | TEXT nullable | FIT filename or Intervals activity ID |
| heart_rate_sample_count | INTEGER nullable | Number of full-session samples stored |
| heart_rate_imported_at_ms | INTEGER nullable | Latest import time |
| note | TEXT nullable | User note |
| created_at_ms / updated_at_ms | INTEGER | Audit timestamps |

## `station_record`

One row per flow segment. `sequence_index` is zero-based and unique inside a
session. The count is dynamic; a session is no longer limited to 16 segments.

| Column | Type | Notes |
|---|---|---|
| id | INTEGER PK AUTOINCREMENT | Local identity |
| session_id | INTEGER FK | Cascade delete |
| station_type | TEXT | Nine-value station enum |
| run_number | INTEGER nullable | 1–8 for run segments |
| sequence_index | INTEGER | 0–15 |
| status | TEXT | `pending`, `active`, `completed`, `skipped` |
| started_at_ms / ended_at_ms | INTEGER nullable | UTC epoch ms |
| duration_ms | INTEGER nullable | Frozen duration |
| accumulated_ms | INTEGER | Pause/resume-ready duration |
| athlete | TEXT nullable | `self`, `partner`, `both` |
| athlete_name | TEXT nullable | Actual selected teammate name; supports relay |
| distance_meters | INTEGER nullable | Future analysis |
| resistance_level | INTEGER nullable | SkiErg/RowErg damper setting |
| weight_kg | REAL nullable | Future analysis |
| repetitions | INTEGER nullable | Wall-ball etc. |
| transition_started_at_ms | INTEGER nullable | Transition after this segment |
| transition_ended_at_ms | INTEGER nullable | Transition completion time |
| transition_duration_ms | INTEGER nullable | Persisted transition duration |
| remark | TEXT nullable | Segment note |

## `heart_rate_sample`

Stores every imported sample: `session_id`, UTC `timestamp_ms`,
`heart_rate_bpm`, optional speed/cadence, and `source`. Samples are retained for
future charts, zones and recovery analysis. The `(session_id, timestamp_ms)`
index makes session and segment range queries efficient.

## Integrity rules

- Enum values are guarded by `CHECK` constraints.
- Session + sequence is unique.
- Durations and physiological values cannot be negative.
- Foreign-key cascading removes child records with a deleted session.
- A partial unique index permits at most one `in_progress` session.
- Active sessions must be cancelled before deletion.

## Version 2 migration

Before the single-active-session unique index is added, any unexpected older
duplicate active sessions are marked cancelled while the newest one remains
active. This makes the migration forward-only and preserves all training data.

## Version 3 templates

- `training_template` stores the reusable template name and built-in flag.
- `template_segment` stores an arbitrary ordered sequence of runs and stations.
- Run segments require a positive `distance_meters`; functional stations do not.
- A session stores `template_id` plus `template_name_snapshot`.
- Station rows are copied into the session at start, so later template edits or
  deletion never change historical training reports.
- Existing sessions are linked to the seeded built-in standard HYROX template.

## Version 4 relay teammates

- Relay sessions store three teammate names in addition to the local athlete.
- Each completed segment stores the actual selected athlete name.
- The legacy `athlete` enum remains populated for backward compatibility.

## Version 5 heart-rate imports

- Full timestamped samples are stored for both local FIT and Intervals.icu.
- Import metadata is stored on the session; API credentials are not stored in SQLite.
- Re-import atomically replaces the previous sample set and summary values.
- Segment average/maximum values are derived from absolute sample timestamps.

## Version 6 station specifications

- Template and session segments can snapshot optional distance, resistance,
  weight and repetition values.
- The legacy standard template migrates to Men Open specifications.
- Women Open and Men Pro read-only built-in templates are seeded alongside it.
- Custom functional-station specifications remain optional.

## Version 7 transition timing

- A completed or skipped segment can start a persisted transition timer.
- Ending a transition and activating the next segment happens atomically.
- Reports use explicitly recorded transition durations when available while
  retaining the legacy derived-duration fallback for older sessions.
