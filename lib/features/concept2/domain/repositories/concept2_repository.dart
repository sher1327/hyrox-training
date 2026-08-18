import '../models/concept2_models.dart';

abstract interface class Concept2Repository {
  Future<Concept2Result?> getForSession(int sessionId);

  Future<void> saveForSession({
    required int sessionId,
    required Concept2Result result,
    required DateTime importedAt,
  });
}
