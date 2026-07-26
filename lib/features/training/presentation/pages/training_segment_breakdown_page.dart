import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../heart_rate/domain/models/heart_rate_models.dart';
import '../../../heart_rate/presentation/controllers/heart_rate_providers.dart';
import '../../domain/models/training_models.dart';
import '../../domain/models/training_report.dart';
import '../controllers/training_providers.dart';
import '../formatters/training_formatters.dart';

enum TrainingBreakdownKind { running, station }

extension TrainingBreakdownKindLabel on TrainingBreakdownKind {
  String get routeName => switch (this) {
        TrainingBreakdownKind.running => 'running',
        TrainingBreakdownKind.station => 'stations',
      };

  String get title => switch (this) {
        TrainingBreakdownKind.running => '跑步分段',
        TrainingBreakdownKind.station => '站点分段',
      };
}

class TrainingSegmentBreakdownPage extends ConsumerWidget {
  const TrainingSegmentBreakdownPage({
    required this.sessionId,
    required this.kind,
    super.key,
  });

  final int sessionId;
  final TrainingBreakdownKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(trainingReportProvider(sessionId));
    final heartRate = ref.watch(heartRateAnalysisProvider(sessionId));
    return Scaffold(
      appBar: AppBar(title: Text(kind.title)),
      body: report.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _MessageState(
          message: '分段记录读取失败：$error',
          onRetry: () => ref.invalidate(trainingReportProvider(sessionId)),
        ),
        data: (value) {
          if (value == null) {
            return const _MessageState(message: '训练记录不存在');
          }
          final segments = value.stations
              .where(
                (station) => kind == TrainingBreakdownKind.running
                    ? station.type == StationType.run
                    : station.type != StationType.run,
              )
              .toList(growable: false);
          return _BreakdownBody(
            report: value,
            segments: segments,
            kind: kind,
            heartRate: heartRate.valueOrNull,
          );
        },
      ),
    );
  }
}

class _BreakdownBody extends StatelessWidget {
  const _BreakdownBody({
    required this.report,
    required this.segments,
    required this.kind,
    required this.heartRate,
  });

  final TrainingReport report;
  final List<StationRecord> segments;
  final TrainingBreakdownKind kind;
  final HeartRateAnalysis? heartRate;

  @override
  Widget build(BuildContext context) {
    final measured = segments.where((segment) => segment.duration != null);
    final measuredCount = measured.length;
    final total = measured.fold(
      Duration.zero,
      (sum, segment) => sum + segment.duration!,
    );
    final average = measuredCount == 0
        ? null
        : Duration(
            microseconds: total.inMicroseconds ~/ measuredCount,
          );
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  children: [
                    _SummaryMetric(
                      label: '合计时间',
                      value: formatDuration(total),
                    ),
                    _SummaryMetric(
                      label: '已记录',
                      value: '$measuredCount / ${segments.length}',
                    ),
                    _SummaryMetric(
                      label: '平均每段',
                      value:
                          average == null ? '--:--' : formatDuration(average),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  report.session.title,
                  style: const TextStyle(color: Colors.white60),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          kind == TrainingBreakdownKind.running ? '每段跑步时间' : '每段站点时间',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 10),
        if (segments.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('没有对应的分段记录')),
            ),
          )
        else
          for (final segment in segments)
            _SegmentBreakdownCard(
              segment: segment,
              sessionStartedAt: report.session.startedAt,
              partnerName: report.session.partnerName,
              heartRate: heartRate?.byStationId[segment.id],
              showPace: kind == TrainingBreakdownKind.running,
            ),
      ],
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          children: [
            Text(
              value,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.white54),
            ),
          ],
        ),
      );
}

class _SegmentBreakdownCard extends StatelessWidget {
  const _SegmentBreakdownCard({
    required this.segment,
    required this.sessionStartedAt,
    required this.partnerName,
    required this.heartRate,
    required this.showPace,
  });

  final StationRecord segment;
  final DateTime? sessionStartedAt;
  final String? partnerName;
  final HeartRateSummary? heartRate;
  final bool showPace;

  @override
  Widget build(BuildContext context) {
    final skipped = segment.status == SegmentStatus.skipped;
    final elapsedRange = _elapsedRange(segment, sessionStartedAt);
    final pace = showPace ? _pace(segment) : null;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: _segmentColor(segment.type).withValues(alpha: .14),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _segmentIcon(segment.type),
                size: 22,
                color: _segmentColor(segment.type),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    segment.displayName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (elapsedRange != null)
                    Text(
                      elapsedRange,
                      style: const TextStyle(color: Colors.white54),
                    ),
                  if (segment.actualSpecification != null)
                    Text(
                      segment.actualSpecification!,
                      style: TextStyle(
                        color: segment.actualMatchesTarget
                            ? Colors.greenAccent.shade100
                            : Colors.orangeAccent.shade100,
                        fontSize: 12,
                      ),
                    ),
                  if (segment.athleteName != null || segment.athlete != null)
                    Text(
                      '完成：${segment.athleteName ?? athleteLabel(segment.athlete, partnerName: partnerName)}',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  if (heartRate != null)
                    Text(
                      '平均 ${heartRate!.average} · 最高 ${heartRate!.maximum} bpm',
                      style: TextStyle(
                        color: Colors.redAccent.shade100,
                        fontSize: 12,
                      ),
                    )
                  else if (segment.duration != null)
                    const Text(
                      '无心率交集',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  if (segment.transitionDuration != null)
                    Text(
                      '后续转换 +${formatDuration(segment.transitionDuration, includeHours: false)}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  skipped
                      ? '已跳过'
                      : formatDuration(segment.duration, includeHours: false),
                  style: TextStyle(
                    color: skipped ? Colors.white38 : Colors.white,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (pace != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    pace,
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.timer_off_outlined, size: 52),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              if (onRetry != null) ...[
                const SizedBox(height: 12),
                FilledButton(onPressed: onRetry, child: const Text('重试')),
              ],
            ],
          ),
        ),
      );
}

String? _elapsedRange(StationRecord segment, DateTime? sessionStartedAt) {
  if (sessionStartedAt == null ||
      segment.startedAt == null ||
      segment.endedAt == null) {
    return null;
  }
  return '${_shortElapsed(segment.startedAt!.difference(sessionStartedAt))}'
      ' – ${_shortElapsed(segment.endedAt!.difference(sessionStartedAt))}';
}

String _shortElapsed(Duration value) {
  final safe = value < Duration.zero ? Duration.zero : value;
  String two(int number) => number.toString().padLeft(2, '0');
  if (safe.inHours > 0) {
    return '${two(safe.inHours)}:${two(safe.inMinutes.remainder(60))}:'
        '${two(safe.inSeconds.remainder(60))}';
  }
  return '${safe.inMinutes}:${two(safe.inSeconds.remainder(60))}';
}

String? _pace(StationRecord segment) {
  final duration = segment.duration;
  final distance = segment.actualDistanceMeters ?? segment.targetDistanceMeters;
  if (duration == null || distance == null || distance <= 0) return null;
  final secondsPerKm = duration.inMilliseconds / 1000 * 1000 / distance;
  final rounded = secondsPerKm.round();
  return '${rounded ~/ 60}:${(rounded % 60).toString().padLeft(2, '0')} /km';
}

Color _segmentColor(StationType type) =>
    type == StationType.run ? const Color(0xFF4ECB63) : const Color(0xFFFFD719);

IconData _segmentIcon(StationType type) => switch (type) {
      StationType.run => Icons.directions_run_rounded,
      StationType.skiErg => Icons.downhill_skiing_rounded,
      StationType.sledPush => Icons.fitness_center_rounded,
      StationType.sledPull => Icons.multiple_stop_rounded,
      StationType.burpeeBroadJump => Icons.accessibility_new_rounded,
      StationType.row => Icons.rowing_rounded,
      StationType.farmerCarry => Icons.shopping_bag_rounded,
      StationType.sandbagLunge => Icons.directions_walk_rounded,
      StationType.wallBall => Icons.sports_basketball_rounded,
    };
