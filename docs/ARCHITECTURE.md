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
