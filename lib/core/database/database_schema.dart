abstract final class DatabaseSchema {
  static const version = 7;

  static const createTrainingTemplate = '''
CREATE TABLE training_template (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL COLLATE NOCASE UNIQUE,
  is_built_in INTEGER NOT NULL DEFAULT 0 CHECK(is_built_in IN (0, 1)),
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
)
''';

  static const createTemplateSegment = '''
CREATE TABLE template_segment (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  template_id INTEGER NOT NULL REFERENCES training_template(id) ON DELETE CASCADE,
  station_type TEXT NOT NULL CHECK(station_type IN (
    'run', 'ski_erg', 'sled_push', 'sled_pull', 'burpee_broad_jump',
    'row', 'farmer_carry', 'sandbag_lunge', 'wall_ball'
  )),
  sequence_index INTEGER NOT NULL CHECK(sequence_index >= 0),
  distance_meters INTEGER CHECK(distance_meters IS NULL OR distance_meters > 0),
  resistance_level INTEGER CHECK(resistance_level IS NULL OR resistance_level > 0),
  weight_kg REAL CHECK(weight_kg IS NULL OR weight_kg > 0),
  repetitions INTEGER CHECK(repetitions IS NULL OR repetitions > 0),
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
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
)
''';

  static const createStationRecord = '''
CREATE TABLE station_record (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id INTEGER NOT NULL REFERENCES training_session(id) ON DELETE CASCADE,
  station_type TEXT NOT NULL CHECK(station_type IN (
    'run', 'ski_erg', 'sled_push', 'sled_pull', 'burpee_broad_jump',
    'row', 'farmer_carry', 'sandbag_lunge', 'wall_ball'
  )),
  run_number INTEGER CHECK(run_number IS NULL OR run_number > 0),
  sequence_index INTEGER NOT NULL CHECK(sequence_index >= 0),
  status TEXT NOT NULL CHECK(status IN ('pending', 'active', 'completed', 'skipped')),
  started_at_ms INTEGER,
  ended_at_ms INTEGER,
  duration_ms INTEGER CHECK(duration_ms IS NULL OR duration_ms >= 0),
  accumulated_ms INTEGER NOT NULL DEFAULT 0 CHECK(accumulated_ms >= 0),
  athlete TEXT CHECK(athlete IS NULL OR athlete IN ('self', 'partner', 'both')),
  athlete_name TEXT,
  distance_meters INTEGER CHECK(distance_meters IS NULL OR distance_meters >= 0),
  resistance_level INTEGER CHECK(resistance_level IS NULL OR resistance_level > 0),
  weight_kg REAL CHECK(weight_kg IS NULL OR weight_kg >= 0),
  repetitions INTEGER CHECK(repetitions IS NULL OR repetitions >= 0),
  transition_started_at_ms INTEGER,
  transition_ended_at_ms INTEGER,
  transition_duration_ms INTEGER CHECK(
    transition_duration_ms IS NULL OR transition_duration_ms >= 0
  ),
  remark TEXT,
  UNIQUE(session_id, sequence_index)
)
''';

  static const createHeartRateSample = '''
CREATE TABLE heart_rate_sample (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id INTEGER NOT NULL REFERENCES training_session(id) ON DELETE CASCADE,
  timestamp_ms INTEGER NOT NULL,
  heart_rate_bpm INTEGER NOT NULL CHECK(heart_rate_bpm > 0),
  speed_mps REAL,
  cadence_rpm INTEGER,
  source TEXT NOT NULL,
  UNIQUE(session_id, timestamp_ms, source)
)
''';

  static const indexes = [
    'CREATE INDEX idx_template_segment_order ON template_segment(template_id, sequence_index)',
    'CREATE INDEX idx_session_started_at ON training_session(started_at_ms DESC)',
    'CREATE INDEX idx_station_session ON station_record(session_id, sequence_index)',
    'CREATE INDEX idx_hr_session_time ON heart_rate_sample(session_id, timestamp_ms)',
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
