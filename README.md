# HYROX Training Tracker

Android-first, offline Flutter application for recording HYROX training.

## Current implementation

- Project structure and architecture decisions
- SQLite v8 schema with non-destructive migrations
- Page and navigation design
- Riverpod-driven HYROX timer state machine
- Repository interfaces and SQLite implementations
- Dashboard backed by SQLite, including active-session recovery entry
- Create-training form for single, double and relay modes
- Persisted segment and transition timers with background/process recovery
- Single, double and four-person relay training modes
- History list and training detail report with per-segment duration and heart rate
- Built-in race specifications and reusable custom training templates
- Planned versus actual station performance with post-workout editing
- FIT file and Intervals.icu heart-rate import with full timestamped samples

## Run

```sh
flutter pub get
flutter run
```

The Android runner is included. Connect a device with USB debugging enabled and
confirm it appears in `flutter devices` before running.

## Documents

- [Architecture](docs/ARCHITECTURE.md)
- [Database design](docs/DATABASE.md)
- [Page design](docs/PAGES.md)
- [Implementation roadmap](docs/ROADMAP.md)
