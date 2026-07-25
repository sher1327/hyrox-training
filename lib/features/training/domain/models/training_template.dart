import 'training_models.dart';

final class TrainingTemplate {
  const TrainingTemplate({
    required this.id,
    required this.name,
    required this.isBuiltIn,
    required this.segments,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String name;
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
    this.distanceMeters,
    this.resistanceLevel,
    this.weightKg,
    this.repetitions,
  });

  final int id;
  final int templateId;
  final StationType type;
  final int sequenceIndex;
  final int? distanceMeters;
  final int? resistanceLevel;
  final double? weightKg;
  final int? repetitions;

  String get displayName => formatStationSpecification(
        type: type,
        distanceMeters: distanceMeters,
        resistanceLevel: resistanceLevel,
        weightKg: weightKg,
        repetitions: repetitions,
      );
}

final class TemplateSegmentInput {
  const TemplateSegmentInput({
    required this.type,
    this.distanceMeters,
    this.resistanceLevel,
    this.weightKg,
    this.repetitions,
  });

  final StationType type;
  final int? distanceMeters;
  final int? resistanceLevel;
  final double? weightKg;
  final int? repetitions;

  String get displayName => formatStationSpecification(
        type: type,
        distanceMeters: distanceMeters,
        resistanceLevel: resistanceLevel,
        weightKg: weightKg,
        repetitions: repetitions,
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
