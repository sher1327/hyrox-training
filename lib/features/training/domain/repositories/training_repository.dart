import '../models/training_models.dart';
import '../models/training_template.dart';

abstract interface class TrainingRepository {
  Future<int> createAndStartSession({
    required TrainingMode mode,
    required String title,
    required TrainingTemplate template,
    required List<String> teammateNames,
    required DateTime startedAt,
  });

  Future<TrainingSession?> getSession(int sessionId);
  Future<TrainingSession?> getActiveSession();
  Future<List<TrainingSession>> listSessions();
  Future<List<StationRecord>> listStations(int sessionId);

  Future<void> completeStation({
    required int stationId,
    required DateTime endedAt,
    required Duration duration,
    required String athleteName,
  });

  Future<void> activateStation(int stationId, DateTime startedAt);
  Future<void> skipStation(int stationId, DateTime at);
  Future<void> finishStationAndAdvance({
    required int sessionId,
    required int stationId,
    required int? nextStationId,
    required DateTime endedAt,
    required Duration duration,
    required String athleteName,
    required bool skipped,
    required bool startTransition,
    required StationActualPerformance actualPerformance,
  });

  Future<void> updateStationActualPerformance({
    required int stationId,
    required StationActualPerformance actualPerformance,
  });
  Future<void> correctStationBoundary({
    required int sessionId,
    required int previousStationId,
    required int nextStationId,
    required DateTime boundaryAt,
    required DateTime updatedAt,
  });
  Future<void> finishTransitionAndActivateNext({
    required int fromStationId,
    required int nextStationId,
    required DateTime at,
  });
  Future<int> undoLastStationCompletion({
    required int sessionId,
    required DateTime restoredAt,
  });
  Future<void> completeSession(int sessionId, DateTime endedAt);
  Future<void> cancelSession(int sessionId, DateTime endedAt);
  Future<void> deleteSession(int sessionId);
}
