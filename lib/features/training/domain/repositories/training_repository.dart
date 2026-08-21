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
  Future<List<RunningLap>> listRunningLaps(int sessionId);

  Future<int> recordRunningLap({
    required int sessionId,
    required int stationId,
    required DateTime endedAt,
  });
  Future<void> updateRunningLapDistance({
    required int lapId,
    required int? distanceMeters,
  });

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
  Future<void> finishTransitionAndActivateNext({
    required int fromStationId,
    required int nextStationId,
    required DateTime at,
  });
  Future<void> finishTransitionAndCompleteSession({
    required int sessionId,
    required int fromStationId,
    required DateTime at,
  });
  Future<void> reorderPendingStations({
    required int sessionId,
    required List<int> orderedStationIds,
    required DateTime changedAt,
  });
  Future<int> addPendingStation({
    required int sessionId,
    required TemplateSegmentInput segment,
    required bool insertAsNext,
    required DateTime changedAt,
  });
  Future<void> skipPendingStation({
    required int sessionId,
    required int stationId,
    required String reason,
    required DateTime changedAt,
  });
  Future<void> restoreSkippedPendingStation({
    required int sessionId,
    required int stationId,
    required int pendingIndex,
    required DateTime changedAt,
  });
  Future<int> undoLastStationCompletion({
    required int sessionId,
    required DateTime restoredAt,
  });
  Future<void> completeSession(int sessionId, DateTime endedAt);
  Future<void> cancelSession(int sessionId, DateTime endedAt);
  Future<void> updateTrainingReflection({
    required int sessionId,
    required TrainingReflection reflection,
    required DateTime changedAt,
  });
  Future<void> deleteSession(int sessionId);
}
