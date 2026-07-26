import '../models/heart_rate_models.dart';

/// Converts Intervals.icu-style relative streams into absolute samples.
///
/// Keeping this conversion outside the API client makes the time-series logic
/// reusable by file importers, fixtures and future sync sources.
abstract final class HeartRateTimeSeriesMapper {
  static List<HeartRateSample> fromRelativeStreams({
    required DateTime startedAt,
    required List<Object?> times,
    required List<Object?> heartRates,
    String? source,
  }) {
    final count =
        times.length < heartRates.length ? times.length : heartRates.length;
    final samples = <HeartRateSample>[];
    for (var index = 0; index < count; index++) {
      final seconds = times[index];
      final bpm = heartRates[index];
      if (seconds is! num || bpm is! num || seconds < 0 || bpm <= 0) {
        continue;
      }
      samples.add(
        HeartRateSample(
          timestamp: startedAt.add(
            Duration(milliseconds: (seconds * 1000).round()),
          ),
          bpm: bpm.round(),
          source: source,
        ),
      );
    }
    samples.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return List.unmodifiable(samples);
  }
}
