import 'training_models.dart';

enum TemplateType { hyroxRace, workout, interval, strength, other }

extension TemplateTypeLabel on TemplateType {
  String get label => switch (this) {
        TemplateType.hyroxRace => 'HYROX 比赛',
        TemplateType.workout => '综合训练',
        TemplateType.interval => '间歇训练',
        TemplateType.strength => '力量训练',
        TemplateType.other => '其他',
      };
}

final class TrainingTemplate {
  const TrainingTemplate({
    required this.id,
    required this.name,
    required this.type,
    required this.isBuiltIn,
    required this.segments,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String name;
  final TemplateType type;
  final bool isBuiltIn;
  final List<TemplateSegment> segments;
  final DateTime createdAt;
  final DateTime updatedAt;
}

final class TemplateSegment {
  const TemplateSegment({
    required this.id,
    required this.templateId,
    required this.type,
    required this.sequenceIndex,
    this.segmentKind = TrainingSegmentKind.station,
    this.targetDistanceMeters,
    this.targetResistanceLevel,
    this.targetWeightKg,
    this.targetRepetitions,
  });

  final int id;
  final int templateId;
  final StationType type;
  final int sequenceIndex;
  final TrainingSegmentKind segmentKind;
  final int? targetDistanceMeters;
  final int? targetResistanceLevel;
  final double? targetWeightKg;
  final int? targetRepetitions;

  String get displayName => formatStationSpecification(
        type: type,
        distanceMeters: targetDistanceMeters,
        resistanceLevel: targetResistanceLevel,
        weightKg: targetWeightKg,
        repetitions: targetRepetitions,
      );
}

final class TemplateSegmentInput {
  const TemplateSegmentInput({
    required this.type,
    this.segmentKind = TrainingSegmentKind.station,
    this.targetDistanceMeters,
    this.targetResistanceLevel,
    this.targetWeightKg,
    this.targetRepetitions,
  });

  final StationType type;
  final TrainingSegmentKind segmentKind;
  final int? targetDistanceMeters;
  final int? targetResistanceLevel;
  final double? targetWeightKg;
  final int? targetRepetitions;

  String get displayName => formatStationSpecification(
        type: type,
        distanceMeters: targetDistanceMeters,
        resistanceLevel: targetResistanceLevel,
        weightKg: targetWeightKg,
        repetitions: targetRepetitions,
      );
}

String formatStationSpecification({
  required StationType type,
  int? distanceMeters,
  int? resistanceLevel,
  double? weightKg,
  int? repetitions,
}) {
  final details = <String>[];
  if (resistanceLevel != null) details.add('阻力 $resistanceLevel');
  if (weightKg != null) {
    final weight = weightKg == weightKg.roundToDouble()
        ? weightKg.toInt().toString()
        : weightKg.toStringAsFixed(1);
    details
        .add(type == StationType.farmerCarry ? '2 × $weight kg' : '$weight kg');
  }
  if (distanceMeters != null) details.add('$distanceMeters m');
  if (repetitions != null) details.add('$repetitions 次');
  return details.isEmpty
      ? type.label
      : '${type.label} · ${details.join(' · ')}';
}
