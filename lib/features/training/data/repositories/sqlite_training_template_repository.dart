import '../../domain/models/training_models.dart';
import '../../domain/models/training_template.dart';
import '../../domain/repositories/training_template_repository.dart';
import '../dao/training_template_dao.dart';

final class SqliteTrainingTemplateRepository
    implements TrainingTemplateRepository {
  const SqliteTrainingTemplateRepository(this._dao);

  final TrainingTemplateDao _dao;

  @override
  Future<List<TrainingTemplate>> listTemplates() async {
    final rows = await _dao.listTemplates();
    final result = <TrainingTemplate>[];
    for (final row in rows) {
      result.add(await _mapTemplate(row));
    }
    return result;
  }

  @override
  Future<TrainingTemplate?> getTemplate(int templateId) async {
    final rows = await _dao.getTemplate(templateId);
    return rows.isEmpty ? null : _mapTemplate(rows.single);
  }

  @override
  Future<int> createTemplate({
    required String name,
    required List<TemplateSegmentInput> segments,
    required DateTime createdAt,
  }) {
    _validate(name, segments);
    return _dao.createTemplate(
      name: name.trim(),
      segments: segments,
      createdAt: createdAt,
    );
  }

  @override
  Future<void> updateTemplate({
    required int templateId,
    required String name,
    required List<TemplateSegmentInput> segments,
    required DateTime updatedAt,
  }) {
    _validate(name, segments);
    return _dao.updateTemplate(
      templateId: templateId,
      name: name.trim(),
      segments: segments,
      updatedAt: updatedAt,
    );
  }

  @override
  Future<void> deleteTemplate(int templateId) =>
      _dao.deleteTemplate(templateId);

  Future<TrainingTemplate> _mapTemplate(Map<String, Object?> row) async {
    final templateId = row['id']! as int;
    final segmentRows = await _dao.listSegments(templateId);
    return TrainingTemplate(
      id: templateId,
      name: row['name']! as String,
      isBuiltIn: (row['is_built_in']! as int) == 1,
      segments: segmentRows.map(_mapSegment).toList(growable: false),
      createdAt: _date(row['created_at_ms']! as int),
      updatedAt: _date(row['updated_at_ms']! as int),
    );
  }

  TemplateSegment _mapSegment(Map<String, Object?> row) => TemplateSegment(
        id: row['id']! as int,
        templateId: row['template_id']! as int,
        type: _stationType(row['station_type']! as String),
        sequenceIndex: row['sequence_index']! as int,
        distanceMeters: row['distance_meters'] as int?,
        resistanceLevel: row['resistance_level'] as int?,
        weightKg: (row['weight_kg'] as num?)?.toDouble(),
        repetitions: row['repetitions'] as int?,
      );

  void _validate(String name, List<TemplateSegmentInput> segments) {
    if (name.trim().isEmpty) throw ArgumentError('模板名称不能为空');
    if (segments.isEmpty) throw ArgumentError('模板至少需要一个训练项目');
    for (final segment in segments) {
      if (segment.type == StationType.run &&
          (segment.distanceMeters == null || segment.distanceMeters! <= 0)) {
        throw ArgumentError('跑步距离必须大于 0 米');
      }
      if (segment.distanceMeters != null && segment.distanceMeters! <= 0) {
        throw ArgumentError('项目距离必须大于 0 米');
      }
      if (segment.resistanceLevel != null && segment.resistanceLevel! <= 0) {
        throw ArgumentError('阻力必须大于 0');
      }
      if (segment.weightKg != null && segment.weightKg! <= 0) {
        throw ArgumentError('重量必须大于 0 kg');
      }
      if (segment.repetitions != null && segment.repetitions! <= 0) {
        throw ArgumentError('次数必须大于 0');
      }
      final allowsDistance = segment.type != StationType.wallBall;
      final allowsResistance =
          segment.type == StationType.skiErg || segment.type == StationType.row;
      final allowsWeight = segment.type == StationType.sledPush ||
          segment.type == StationType.sledPull ||
          segment.type == StationType.farmerCarry ||
          segment.type == StationType.sandbagLunge ||
          segment.type == StationType.wallBall;
      final allowsRepetitions = segment.type == StationType.burpeeBroadJump ||
          segment.type == StationType.wallBall;
      if (!allowsDistance && segment.distanceMeters != null ||
          !allowsResistance && segment.resistanceLevel != null ||
          !allowsWeight && segment.weightKg != null ||
          !allowsRepetitions && segment.repetitions != null) {
        throw ArgumentError('${segment.type.label} 包含不支持的参数');
      }
    }
  }
}

DateTime _date(int value) =>
    DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);

StationType _stationType(String value) => switch (value) {
      'run' => StationType.run,
      'ski_erg' => StationType.skiErg,
      'sled_push' => StationType.sledPush,
      'sled_pull' => StationType.sledPull,
      'burpee_broad_jump' => StationType.burpeeBroadJump,
      'row' => StationType.row,
      'farmer_carry' => StationType.farmerCarry,
      'sandbag_lunge' => StationType.sandbagLunge,
      'wall_ball' => StationType.wallBall,
      _ => throw FormatException('Unknown station type: $value'),
    };
