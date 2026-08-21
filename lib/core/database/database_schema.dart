abstract final class DatabaseSchema {
  static const version = 13;

  static const createTrainingTemplate = '''
CREATE TABLE training_template (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL COLLATE NOCASE UNIQUE,
  template_type TEXT NOT NULL DEFAULT 'other' CHECK(template_type IN (
    'hyrox_race', 'workout', 'interval', 'strength', 'other'
  )),
  is_built_in INTEGER NOT NULL DEFAULT 0 CHECK(is_built_in IN (0, 1)),
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
)
''';

  static const createTemplateSegment = '''
CREATE TABLE template_segment (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  template_id INTEGER NOT NULL REFERENCES training_template(id) ON DELETE CASCADE,
  segment_kind TEXT NOT NULL DEFAULT 'station' CHECK(segment_kind IN (
    'station', 'rest', 'warmup', 'cooldown'
  )),
  station_type TEXT NOT NULL CHECK(station_type IN (
    'run', 'ski_erg', 'sled_push', 'sled_pull', 'burpee_broad_jump',
    'row', 'farmer_carry', 'sandbag_lunge', 'wall_ball'
  )),
  sequence_index INTEGER NOT NULL CHECK(sequence_index >= 0),
  target_distance_meters INTEGER CHECK(target_distance_meters IS NULL OR target_distance_meters > 0),
  target_resistance_level INTEGER CHECK(target_resistance_level IS NULL OR target_resistance_level > 0),
  target_weight_kg REAL CHECK(target_weight_kg IS NULL OR target_weight_kg > 0),
  target_repetitions INTEGER CHECK(target_repetitions IS NULL OR target_repetitions > 0),
  UNIQUE(template_id, sequence_index)
)
''';

  static const uniqueActiveSessionIndex = '''
CREATE UNIQUE INDEX idx_single_active_session
ON training_session(status)
WHERE status = 'in_progress'
''';

  static const createTrainingSession = '''
CREATE TABLE training_session (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  mode TEXT NOT NULL CHECK(mode IN ('single', 'double', 'relay')),
  title TEXT NOT NULL,
  partner_name TEXT,
  partner_name_2 TEXT,
  partner_name_3 TEXT,
  template_id INTEGER REFERENCES training_template(id) ON DELETE SET NULL,
  template_name_snapshot TEXT,
  status TEXT NOT NULL CHECK(status IN ('draft', 'in_progress', 'completed', 'cancelled')),
  started_at_ms INTEGER,
  ended_at_ms INTEGER,
  total_duration_ms INTEGER CHECK(total_duration_ms IS NULL OR total_duration_ms >= 0),
  avg_heart_rate INTEGER CHECK(avg_heart_rate IS NULL OR avg_heart_rate > 0),
  max_heart_rate INTEGER CHECK(max_heart_rate IS NULL OR max_heart_rate > 0),
  heart_rate_source TEXT,
  heart_rate_external_id TEXT,
  heart_rate_sample_count INTEGER CHECK(heart_rate_sample_count IS NULL OR heart_rate_sample_count >= 0),
  heart_rate_imported_at_ms INTEGER,
  note TEXT,
  perceived_effort INTEGER CHECK(
    perceived_effort IS NULL OR perceived_effort BETWEEN 1 AND 10
  ),
  feeling TEXT CHECK(
    feeling IS NULL OR feeling IN (
      'very_bad', 'bad', 'neutral', 'good', 'very_good'
    )
  ),
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
)
''';

  static const createStationRecord = '''
CREATE TABLE station_record (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id INTEGER NOT NULL REFERENCES training_session(id) ON DELETE CASCADE,
  segment_kind TEXT NOT NULL DEFAULT 'station' CHECK(segment_kind IN (
    'station', 'rest', 'warmup', 'cooldown'
  )),
  station_type TEXT NOT NULL CHECK(station_type IN (
    'run', 'ski_erg', 'sled_push', 'sled_pull', 'burpee_broad_jump',
    'row', 'farmer_carry', 'sandbag_lunge', 'wall_ball'
  )),
  run_number INTEGER CHECK(run_number IS NULL OR run_number > 0),
  planned_sequence_index INTEGER CHECK(
    planned_sequence_index IS NULL OR planned_sequence_index >= 0
  ),
  sequence_index INTEGER NOT NULL CHECK(sequence_index >= 0),
  origin TEXT NOT NULL DEFAULT 'template' CHECK(origin IN ('template', 'ad_hoc')),
  status TEXT NOT NULL CHECK(status IN ('pending', 'active', 'completed', 'skipped')),
  started_at_ms INTEGER,
  ended_at_ms INTEGER,
  duration_ms INTEGER CHECK(duration_ms IS NULL OR duration_ms >= 0),
  accumulated_ms INTEGER NOT NULL DEFAULT 0 CHECK(accumulated_ms >= 0),
  athlete TEXT CHECK(athlete IS NULL OR athlete IN ('self', 'partner', 'both')),
  athlete_name TEXT,
  target_distance_meters INTEGER CHECK(target_distance_meters IS NULL OR target_distance_meters >= 0),
  target_resistance_level INTEGER CHECK(target_resistance_level IS NULL OR target_resistance_level > 0),
  target_weight_kg REAL CHECK(target_weight_kg IS NULL OR target_weight_kg >= 0),
  target_repetitions INTEGER CHECK(target_repetitions IS NULL OR target_repetitions >= 0),
  actual_distance_meters INTEGER CHECK(actual_distance_meters IS NULL OR actual_distance_meters >= 0),
  actual_resistance_level INTEGER CHECK(actual_resistance_level IS NULL OR actual_resistance_level > 0),
  actual_weight_kg REAL CHECK(actual_weight_kg IS NULL OR actual_weight_kg >= 0),
  actual_repetitions INTEGER CHECK(actual_repetitions IS NULL OR actual_repetitions >= 0),
  transition_started_at_ms INTEGER,
  transition_ended_at_ms INTEGER,
  transition_duration_ms INTEGER CHECK(
    transition_duration_ms IS NULL OR transition_duration_ms >= 0
  ),
  skip_reason TEXT,
  remark TEXT,
  UNIQUE(session_id, sequence_index)
)
''';

  static const createRunningLap = '''
CREATE TABLE running_lap (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id INTEGER NOT NULL REFERENCES training_session(id) ON DELETE CASCADE,
  station_record_id INTEGER NOT NULL REFERENCES station_record(id) ON DELETE CASCADE,
  sequence_index INTEGER NOT NULL CHECK(sequence_index >= 0),
  started_at_ms INTEGER NOT NULL,
  ended_at_ms INTEGER NOT NULL CHECK(ended_at_ms > started_at_ms),
  duration_ms INTEGER NOT NULL CHECK(duration_ms > 0),
  distance_meters INTEGER CHECK(distance_meters IS NULL OR distance_meters > 0),
  capture_type TEXT NOT NULL DEFAULT 'manual' CHECK(capture_type IN ('manual', 'finish')),
  UNIQUE(station_record_id, sequence_index)
)
''';

  static const createHeartRateImport = '''
CREATE TABLE heart_rate_import (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id INTEGER NOT NULL REFERENCES training_session(id) ON DELETE CASCADE,
  source TEXT NOT NULL,
  external_activity_id TEXT,
  external_activity_name TEXT,
  file_name TEXT,
  imported_at_ms INTEGER NOT NULL,
  sample_count INTEGER NOT NULL CHECK(sample_count > 0),
  avg_heart_rate INTEGER NOT NULL CHECK(avg_heart_rate > 0),
  max_heart_rate INTEGER NOT NULL CHECK(max_heart_rate > 0),
  is_active INTEGER NOT NULL DEFAULT 1 CHECK(is_active IN (0, 1))
)
''';

  static const createHeartRateSample = '''
CREATE TABLE heart_rate_sample (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id INTEGER NOT NULL REFERENCES training_session(id) ON DELETE CASCADE,
  import_batch_id INTEGER NOT NULL REFERENCES heart_rate_import(id) ON DELETE CASCADE,
  timestamp_ms INTEGER NOT NULL,
  heart_rate_bpm INTEGER NOT NULL CHECK(heart_rate_bpm > 0),
  speed_mps REAL,
  cadence_rpm INTEGER,
  UNIQUE(import_batch_id, timestamp_ms)
)
''';

  static const createConcept2Result = '''
CREATE TABLE concept2_result (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id INTEGER NOT NULL UNIQUE REFERENCES training_session(id) ON DELETE CASCADE,
  external_result_id INTEGER NOT NULL,
  machine_type TEXT NOT NULL CHECK(machine_type IN ('rower', 'skierg')),
  ended_at_ms INTEGER NOT NULL,
  distance_meters INTEGER NOT NULL CHECK(distance_meters >= 0),
  work_time_tenths INTEGER NOT NULL CHECK(work_time_tenths >= 0),
  rest_time_tenths INTEGER NOT NULL DEFAULT 0 CHECK(rest_time_tenths >= 0),
  workout_type TEXT NOT NULL,
  stroke_rate INTEGER,
  stroke_count INTEGER,
  drag_factor INTEGER,
  calories_total INTEGER,
  source TEXT,
  imported_at_ms INTEGER NOT NULL
)
''';

  static const createConcept2Interval = '''
CREATE TABLE concept2_interval (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  concept2_result_row_id INTEGER NOT NULL REFERENCES concept2_result(id) ON DELETE CASCADE,
  sequence_index INTEGER NOT NULL CHECK(sequence_index >= 0),
  interval_kind TEXT NOT NULL,
  time_tenths INTEGER NOT NULL CHECK(time_tenths >= 0),
  rest_time_tenths INTEGER NOT NULL DEFAULT 0 CHECK(rest_time_tenths >= 0),
  distance_meters INTEGER NOT NULL CHECK(distance_meters >= 0),
  rest_distance_meters INTEGER NOT NULL DEFAULT 0 CHECK(rest_distance_meters >= 0),
  stroke_rate INTEGER,
  calories_total INTEGER,
  UNIQUE(concept2_result_row_id, sequence_index)
)
''';

  static const createConcept2Stroke = '''
CREATE TABLE concept2_stroke (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  concept2_result_row_id INTEGER NOT NULL REFERENCES concept2_result(id) ON DELETE CASCADE,
  sequence_index INTEGER NOT NULL CHECK(sequence_index >= 0),
  stroke_time_tenths INTEGER NOT NULL CHECK(stroke_time_tenths >= 0),
  cumulative_work_tenths INTEGER NOT NULL CHECK(cumulative_work_tenths >= 0),
  distance_decimeters INTEGER NOT NULL CHECK(distance_decimeters >= 0),
  pace_tenths INTEGER,
  stroke_rate INTEGER,
  heart_rate INTEGER,
  UNIQUE(concept2_result_row_id, sequence_index)
)
''';

  static const indexes = [
    'CREATE INDEX idx_template_segment_order ON template_segment(template_id, sequence_index)',
    'CREATE INDEX idx_session_started_at ON training_session(started_at_ms DESC)',
    'CREATE INDEX idx_station_session ON station_record(session_id, sequence_index)',
    'CREATE INDEX idx_running_lap_session ON running_lap(session_id, station_record_id, sequence_index)',
    'CREATE INDEX idx_hr_session_time ON heart_rate_sample(session_id, timestamp_ms)',
    'CREATE INDEX idx_hr_import_session ON heart_rate_import(session_id, imported_at_ms DESC)',
    'CREATE UNIQUE INDEX idx_active_hr_import ON heart_rate_import(session_id) WHERE is_active = 1',
    'CREATE INDEX idx_concept2_session ON concept2_result(session_id)',
    'CREATE INDEX idx_concept2_interval_order ON concept2_interval(concept2_result_row_id, sequence_index)',
    'CREATE INDEX idx_concept2_stroke_order ON concept2_stroke(concept2_result_row_id, sequence_index)',
    uniqueActiveSessionIndex,
  ];

  static const standardTemplateSegments = <({String type, int? distance})>[
    (type: 'run', distance: 1000),
    (type: 'ski_erg', distance: null),
    (type: 'run', distance: 1000),
    (type: 'sled_push', distance: null),
    (type: 'run', distance: 1000),
    (type: 'sled_pull', distance: null),
    (type: 'run', distance: 1000),
    (type: 'burpee_broad_jump', distance: null),
    (type: 'run', distance: 1000),
    (type: 'row', distance: null),
    (type: 'run', distance: 1000),
    (type: 'farmer_carry', distance: null),
    (type: 'run', distance: 1000),
    (type: 'sandbag_lunge', distance: null),
    (type: 'run', distance: 1000),
    (type: 'wall_ball', distance: null),
  ];

  static const singleStationTemplates = <SingleStationTemplateDefinition>[
    SingleStationTemplateDefinition(name: '跑步训练', stationType: 'run'),
    SingleStationTemplateDefinition(name: '划船训练', stationType: 'row'),
    SingleStationTemplateDefinition(name: '滑雪训练', stationType: 'ski_erg'),
  ];

  static const builtInTemplates = <BuiltInTemplateDefinition>[
    BuiltInTemplateDefinition(
      name: 'HYROX 男子大众（Open）',
      sledPushWeightKg: 152,
      sledPullWeightKg: 103,
      farmerCarryWeightKg: 24,
      lungeWeightKg: 20,
      wallBallWeightKg: 6,
    ),
    BuiltInTemplateDefinition(
      name: 'HYROX 女子大众（Open）',
      sledPushWeightKg: 102,
      sledPullWeightKg: 78,
      farmerCarryWeightKg: 16,
      lungeWeightKg: 10,
      wallBallWeightKg: 4,
    ),
    BuiltInTemplateDefinition(
      name: 'HYROX 男子精英（Pro）',
      sledPushWeightKg: 202,
      sledPullWeightKg: 153,
      farmerCarryWeightKg: 32,
      lungeWeightKg: 30,
      wallBallWeightKg: 9,
    ),
  ];
}

final class BuiltInTemplateDefinition {
  const BuiltInTemplateDefinition({
    required this.name,
    required this.sledPushWeightKg,
    required this.sledPullWeightKg,
    required this.farmerCarryWeightKg,
    required this.lungeWeightKg,
    required this.wallBallWeightKg,
  });

  final String name;
  final double sledPushWeightKg;
  final double sledPullWeightKg;
  final double farmerCarryWeightKg;
  final double lungeWeightKg;
  final double wallBallWeightKg;

  List<BuiltInSegmentDefinition> get segments => [
        const BuiltInSegmentDefinition(type: 'run', distanceMeters: 1000),
        const BuiltInSegmentDefinition(
          type: 'ski_erg',
          distanceMeters: 1000,
          resistanceLevel: 6,
        ),
        const BuiltInSegmentDefinition(type: 'run', distanceMeters: 1000),
        BuiltInSegmentDefinition(
          type: 'sled_push',
          distanceMeters: 50,
          weightKg: sledPushWeightKg,
        ),
        const BuiltInSegmentDefinition(type: 'run', distanceMeters: 1000),
        BuiltInSegmentDefinition(
          type: 'sled_pull',
          distanceMeters: 50,
          weightKg: sledPullWeightKg,
        ),
        const BuiltInSegmentDefinition(type: 'run', distanceMeters: 1000),
        const BuiltInSegmentDefinition(
          type: 'burpee_broad_jump',
          distanceMeters: 80,
        ),
        const BuiltInSegmentDefinition(type: 'run', distanceMeters: 1000),
        const BuiltInSegmentDefinition(
          type: 'row',
          distanceMeters: 1000,
          resistanceLevel: 6,
        ),
        const BuiltInSegmentDefinition(type: 'run', distanceMeters: 1000),
        BuiltInSegmentDefinition(
          type: 'farmer_carry',
          distanceMeters: 200,
          weightKg: farmerCarryWeightKg,
        ),
        const BuiltInSegmentDefinition(type: 'run', distanceMeters: 1000),
        BuiltInSegmentDefinition(
          type: 'sandbag_lunge',
          distanceMeters: 100,
          weightKg: lungeWeightKg,
        ),
        const BuiltInSegmentDefinition(type: 'run', distanceMeters: 1000),
        BuiltInSegmentDefinition(
          type: 'wall_ball',
          weightKg: wallBallWeightKg,
          repetitions: 100,
        ),
      ];
}

final class BuiltInSegmentDefinition {
  const BuiltInSegmentDefinition({
    required this.type,
    this.distanceMeters,
    this.resistanceLevel,
    this.weightKg,
    this.repetitions,
  });

  final String type;
  final int? distanceMeters;
  final int? resistanceLevel;
  final double? weightKg;
  final int? repetitions;
}

final class SingleStationTemplateDefinition {
  const SingleStationTemplateDefinition({
    required this.name,
    required this.stationType,
  });

  final String name;
  final String stationType;
}
