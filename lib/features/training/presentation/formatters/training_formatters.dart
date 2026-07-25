import '../../domain/models/training_models.dart';

String formatDuration(Duration? duration, {bool includeHours = true}) {
  if (duration == null) return '--:--';
  String two(int value) => value.toString().padLeft(2, '0');
  final minutes = duration.inMinutes % 60;
  final seconds = duration.inSeconds % 60;
  if (!includeHours && duration.inHours == 0) {
    return '${two(minutes)}:${two(seconds)}';
  }
  return '${two(duration.inHours)}:${two(minutes)}:${two(seconds)}';
}

String formatSessionDate(DateTime? value) {
  if (value == null) return '未开始';
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}/${two(local.month)}/${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

String trainingModeLabel(TrainingMode mode) => switch (mode) {
      TrainingMode.single => '单人',
      TrainingMode.double => '双人',
      TrainingMode.relay => '接力',
    };

String athleteLabel(AthleteAssignment? athlete, {String? partnerName}) =>
    switch (athlete) {
      AthleteAssignment.self => '我',
      AthleteAssignment.partner => partnerName ?? '队友',
      AthleteAssignment.both => '共同完成',
      null => '未记录',
    };
