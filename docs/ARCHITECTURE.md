# Architecture

## Directory structure

```text
lib/
├── app/
│   ├── app.dart                 # MaterialApp + theme
│   └── router.dart              # GoRouter route table
├── core/
│   ├── database/
│   │   ├── app_database.dart    # SQLite lifecycle/migrations
│   │   └── database_schema.dart # SQL kept in one reviewable place
│   └── time/
│       └── clock.dart           # Injectable time source for tests
├── features/
│   ├── heart_rate/              # FIT/Intervals import + full sample storage
│   ├── replay/                  # Immutable replay aggregate + Riverpod playback
│   └── training/
│       ├── data/
│       │   ├── dao/             # Raw SQL and row mapping only
│       │   └── repositories/    # Repository implementation
│       ├── domain/
│       │   ├── models/          # Framework-independent entities
│       │   └── repositories/    # Repository contracts
│       └── presentation/
│           ├── controllers/     # Riverpod state machine
│           └── pages/           # Screens/widgets
└── main.dart
```

Dependencies point inward: `presentation -> domain <- data`. SQLite stays behind DAO and repository boundaries. Controllers depend on repository contracts, which keeps the timer testable and allows a future export/sync layer.

## Core decisions

1. Persist epoch milliseconds in UTC; format in local time only in the UI.
2. The built-in simulation contains 16 ordered segments; custom templates may contain any positive number.
3. `StationType` has nine values: `run` plus the eight functional station types.
4. Segment elapsed time is derived from timestamps; accumulated milliseconds support later pause/resume.
5. A session and all template station rows are created transactionally before timing starts.
6. FIT/Intervals heart-rate samples are stored separately and linked to a session. Imports never mutate timing records.
7. A running session can be restored from SQLite in a later increment; the schema already supports this.
8. Training Replay is derived from stored sessions, segments and the active
   heart-rate import batch. It does not duplicate persisted data.
9. Replay zones use an injectable reference maximum. Until athlete profile
   settings are added, the workout's observed maximum is used and disclosed in
   the UI. Sensor gaps over 30 seconds are not connected or counted as Zone time.
10. `TrainingReplay.toAnalysisPayload()` provides a compact, versioned and
    downsampled boundary for future AI analysis without coupling AI code to UI.
