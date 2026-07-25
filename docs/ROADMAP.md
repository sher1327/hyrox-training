# Incremental implementation roadmap

## Increment 1 — delivered scaffold

- Architecture, schema and page specifications
- Domain models and standard 16-segment flow
- SQLite DAO/repository boundaries
- Riverpod timer state machine
- Minimal pages and routing

## Increment 2 — training loop and recovery (completed)

- [x] Create-training form for single/double/relay modes
- [x] Dashboard/history queries and empty/loading/error states
- [x] Restore entry for an interrupted active session
- [x] Cancel/delete confirmation and single-active-session database constraint
- [x] Lifecycle resume clock synchronization
- [ ] DAO-level database integration tests

## Increment 3 — reports (basic report completed)

- [x] Summary aggregation (running/station/transition)
- [x] Segment detail list
- [ ] Segment ranking, notes and edits

## Increment 4 — heart rate (completed)

- [x] Local FIT parser adapter and import validation
- [x] Intervals.icu activity matching and stream pull
- [x] Timestamp alignment with session/segments
- [x] Full HR sample persistence and aggregate updates
- [ ] Heart-rate curve and zone charts

## Increment 5 — hardening

- Android lifecycle/background behavior
- Widget/controller/database tests
- Accessibility, localization and release build checks
