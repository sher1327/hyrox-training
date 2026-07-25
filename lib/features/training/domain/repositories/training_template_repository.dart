import '../models/training_template.dart';

abstract interface class TrainingTemplateRepository {
  Future<List<TrainingTemplate>> listTemplates();
  Future<TrainingTemplate?> getTemplate(int templateId);

  Future<int> createTemplate({
    required String name,
    required TemplateType type,
    required List<TemplateSegmentInput> segments,
    required DateTime createdAt,
  });

  Future<void> updateTemplate({
    required int templateId,
    required String name,
    required TemplateType type,
    required List<TemplateSegmentInput> segments,
    required DateTime updatedAt,
  });

  Future<void> deleteTemplate(int templateId);
}
