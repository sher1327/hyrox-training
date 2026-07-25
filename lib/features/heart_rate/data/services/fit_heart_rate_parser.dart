import 'dart:async';
import 'dart:typed_data';

import 'package:fit_tool/fit_tool.dart';

import '../../domain/models/heart_rate_models.dart';

final class FitHeartRateParser {
  const FitHeartRateParser();

  Future<List<HeartRateSample>> parse(Uint8List bytes) async {
    if (bytes.isEmpty) throw const FormatException('FIT 文件为空');
    final byTimestamp = <int, HeartRateSample>{};
    try {
      final messages = Stream<List<int>>.value(bytes).transform(FitDecoder());
      await for (final message in messages) {
        if (message is! RecordMessage) continue;
        final timestamp = message.timestamp;
        final bpm = message.heartRate;
        if (timestamp == null || bpm == null || bpm <= 0) continue;
        byTimestamp[timestamp] = HeartRateSample(
          timestamp: DateTime.fromMillisecondsSinceEpoch(
            timestamp,
            isUtc: true,
          ),
          bpm: bpm,
          source: HeartRateSources.fit,
        );
      }
    } catch (_) {
      throw const FormatException('FIT 文件无法解析或文件已损坏');
    }
    final samples = byTimestamp.values.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    if (samples.isEmpty) throw const FormatException('FIT 文件中没有心率记录');
    return samples;
  }
}
