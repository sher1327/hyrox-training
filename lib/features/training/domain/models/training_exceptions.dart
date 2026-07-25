final class ActiveTrainingExistsException implements Exception {
  const ActiveTrainingExistsException(this.sessionId);

  final int sessionId;

  @override
  String toString() => '已有一场进行中的训练';
}
