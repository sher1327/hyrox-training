# Page design

The visual language follows the supplied reference: near-black background, raised charcoal cards, white typography, and HYROX yellow for the primary action/current segment.

## Navigation

```text
Dashboard ── New training ── Active timer ── Summary
    └──────── History ────── Training detail
    └──────── Templates ──── Template editor
```

## 1. Dashboard `/`

- Today's training card and “Create training” primary action
- Recent three sessions with mode, date and elapsed time
- Bottom navigation: Home / History

## 2. Create training `/training/new`

- Mode selector: Single / Double / Relay
- Template selector: Men Open, Women Open, Men Pro, or any custom template
- Session title
- One teammate name for Double; three teammate names for Relay
- Read-only preview including distance, resistance, weight and repetitions
- “Start training” validates input, creates session + rows, then navigates to timer

## 3. Active timer `/training/:id/live`

- Total elapsed timer
- Current segment and segment elapsed timer
- Athlete selector for team modes: Me / named teammate(s) / Together
- Main action: Complete segment
- After completion, choose transition timing or start the next segment directly
- Transition view shows its own live timer and a “Start next segment” action
- Secondary action: Skip segment
- Compact 16-dot progress indicator
- Progress list accessible without changing timer state

Back navigation requires a future confirmation dialog because the active state is persisted.

## 4. History `/history`

- Reverse chronological session list
- Filter by mode/status reserved for the next increment
- Tap opens details

## 5. Training detail `/training/:id`

- Total, running, stations, and transition summary
- All 16 segment times and assigned athlete
- Notes
- Heart-rate import offers local FIT or Intervals.icu online pull
- Intervals.icu credentials are configured once and encrypted on-device
- Online activities are matched by time-range overlap; a single match imports
  directly, while multiple matches are presented for explicit selection
- Full-session average/maximum plus per-segment average/maximum heart rate
- Imported timestamped samples remain in SQLite for future analysis

## 6. Summary

The completed detail page doubles as the end-of-training summary. This avoids two report implementations and allows deep links from History.

## 7. Templates `/templates`

- Three built-in HYROX division templates are read-only.
- Custom templates can be created, edited and deleted.
- Each template contains any number and order of run/function-station segments.
- Every run requires its own distance in meters.
- Functional stations optionally accept their relevant resistance, distance,
  weight and/or repetition parameters.
- Segment rows provide explicit up/down controls for ordering.

## Accessibility

- Yellow is never the only status signal; labels/icons accompany it.
- Primary controls are at least 48 logical pixels high.
- Timer uses tabular figures and semantic elapsed-time labels.
