import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../training/domain/models/training_models.dart';
import '../../../training/presentation/formatters/training_formatters.dart';
import '../../domain/models/training_replay.dart';

/// A static, non-scrollable representation of the complete training replay.
///
/// It intentionally contains no playback, import, edit, or navigation controls
/// so it can be rendered off-screen as one long image.
class TrainingReplayExportView extends StatelessWidget {
  const TrainingReplayExportView({required this.replay, super.key});

  static const double exportWidth = 430;

  final TrainingReplay replay;

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xFF090B0C),
        child: Container(
          width: exportWidth,
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF111718), Color(0xFF090B0C)],
              stops: [0, .22],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ExportHeader(replay: replay),
              const SizedBox(height: 14),
              _ExportSummary(replay: replay),
              const SizedBox(height: 14),
              _ExportSection(
                title: '全程心率曲线',
                child: replay.points.isEmpty
                    ? const _NoHeartRate()
                    : SizedBox(
                        height: 220,
                        width: 356,
                        child: _ExportHeartRateChart(replay: replay),
                      ),
              ),
              const SizedBox(height: 14),
              _ExportSection(
                title: '心率 Zone 统计',
                subtitle: replay.points.isEmpty
                    ? '未导入心率数据'
                    : '按本次最高心率 ${replay.zoneReferenceMaximumBpm} bpm 计算',
                child: _ExportZoneStats(stats: replay.zoneStats),
              ),
              const SizedBox(height: 14),
              _ExportSection(
                title: '完整训练时间轴',
                subtitle: '${replay.segments.length} 个已记录分段',
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (replay.segments.isNotEmpty) ...[
                      _ExportTimeline(replay: replay),
                      const SizedBox(height: 14),
                    ],
                    if (replay.segments.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 18),
                        child: Text(
                          '没有可导出的分段记录',
                          style: TextStyle(color: Colors.white54),
                        ),
                      )
                    else
                      for (final segment in replay.segments)
                        _ExportSegmentRow(segment: segment),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const Center(
                child: Text(
                  'HYROX TRAINING · 完整回放',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                    letterSpacing: 1.6,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

class _ExportHeader extends StatelessWidget {
  const _ExportHeader({required this.replay});

  final TrainingReplay replay;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'H Y R O X',
            style: TextStyle(
              color: Color(0xFFFFD719),
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            replay.title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            formatSessionDate(replay.startedAt),
            style: const TextStyle(color: Colors.white54),
          ),
        ],
      );
}

class _ExportSummary extends StatelessWidget {
  const _ExportSummary({required this.replay});

  final TrainingReplay replay;

  @override
  Widget build(BuildContext context) => _ExportCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _clock(replay.duration),
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const Text('总时长', style: TextStyle(color: Colors.white54)),
            const SizedBox(height: 18),
            const Divider(height: 1, color: Colors.white12),
            const SizedBox(height: 16),
            Wrap(
              spacing: 0,
              runSpacing: 12,
              children: [
                _ExportMetric(
                  label: '平均心率',
                  value: replay.averageHeartRate?.toString() ?? '--',
                  unit: 'bpm',
                ),
                _ExportMetric(
                  label: '最大心率',
                  value: replay.maximumHeartRate?.toString() ?? '--',
                  unit: 'bpm',
                ),
                _ExportMetric(
                  label: '心率采样',
                  value: replay.points.length.toString(),
                  unit: '条',
                ),
              ],
            ),
          ],
        ),
      );
}

class _ExportMetric extends StatelessWidget {
  const _ExportMetric({
    required this.label,
    required this.value,
    required this.unit,
  });

  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 118,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(color: Colors.white54)),
            const SizedBox(height: 5),
            Text(
              value,
              style: const TextStyle(
                color: Color(0xFFFF7C85),
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(unit, style: const TextStyle(color: Colors.white38)),
          ],
        ),
      );
}

class _ExportSection extends StatelessWidget {
  const _ExportSection({
    required this.title,
    required this.child,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => _ExportCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 3),
              Text(
                subtitle!,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
            const SizedBox(height: 16),
            child,
          ],
        ),
      );
}

class _ExportCard extends StatelessWidget {
  const _ExportCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        width: 390,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF15191B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: child,
      );
}

class _NoHeartRate extends StatelessWidget {
  const _NoHeartRate();

  @override
  Widget build(BuildContext context) => const SizedBox(
        width: 356,
        height: 90,
        child: Center(
          child: Text(
            '本次训练尚未导入心率数据',
            style: TextStyle(color: Colors.white54),
          ),
        ),
      );
}

class _ExportHeartRateChart extends StatelessWidget {
  const _ExportHeartRateChart({required this.replay});

  final TrainingReplay replay;

  @override
  Widget build(BuildContext context) {
    final minimumBpm =
        replay.points.map((point) => point.bpm).reduce((a, b) => a < b ? a : b);
    final maximumBpm = replay.maximumHeartRate ?? minimumBpm;
    final minY = (minimumBpm - 10).clamp(30, 240).toDouble();
    final maxY = (maximumBpm + 10).clamp(minY + 20, 260).toDouble();
    final maxX = replay.duration.inMilliseconds / 1000;
    final horizontalInterval = ((maxY - minY) / 3).clamp(10, 50).toDouble();
    final verticalInterval = (maxX / 4).clamp(1, double.infinity).toDouble();
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: maxX <= 0 ? 1 : maxX,
        minY: minY,
        maxY: maxY,
        clipData: const FlClipData.all(),
        lineTouchData: const LineTouchData(enabled: false),
        borderData: FlBorderData(
          show: true,
          border: const Border(
            left: BorderSide(color: Colors.white12),
            bottom: BorderSide(color: Colors.white12),
          ),
        ),
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: horizontalInterval,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: Colors.white10, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              interval: horizontalInterval,
              getTitlesWidget: (value, _) => Text(
                value.round().toString(),
                style: const TextStyle(fontSize: 9, color: Colors.white54),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              interval: verticalInterval,
              getTitlesWidget: (value, _) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _shortClock(
                    Duration(milliseconds: (value * 1000).round()),
                  ),
                  style: const TextStyle(fontSize: 9, color: Colors.white54),
                ),
              ),
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: _chartSpots(replay.points),
            isCurved: true,
            curveSmoothness: .2,
            color: Colors.redAccent,
            barWidth: 2.2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.redAccent.withValues(alpha: .3),
                  Colors.redAccent.withValues(alpha: .01),
                ],
              ),
            ),
          ),
        ],
      ),
      duration: Duration.zero,
    );
  }
}

class _ExportZoneStats extends StatelessWidget {
  const _ExportZoneStats({required this.stats});

  final List<HeartRateZoneStat> stats;

  @override
  Widget build(BuildContext context) {
    const barWidth = 356.0;
    final covered = stats.any((stat) => stat.percentage > 0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: barWidth,
            height: 14,
            child: covered
                ? Row(
                    children: [
                      for (final stat in stats)
                        if (stat.percentage > 0)
                          SizedBox(
                            width: barWidth * stat.percentage,
                            child: ColoredBox(color: _zoneColor(stat.zone)),
                          ),
                    ],
                  )
                : const ColoredBox(color: Colors.white10),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 7,
          runSpacing: 9,
          children: [
            for (final stat in stats)
              Container(
                width: 65,
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  color: _zoneColor(stat.zone).withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${stat.zone.label} ${(stat.percentage * 100).round()}%',
                      style: TextStyle(
                        color: _zoneColor(stat.zone),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _shortClock(stat.duration),
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _ExportTimeline extends StatelessWidget {
  const _ExportTimeline({required this.replay});

  final TrainingReplay replay;

  @override
  Widget build(BuildContext context) {
    const width = 356.0;
    final totalMs = replay.duration.inMilliseconds;
    if (totalMs <= 0) return const SizedBox.shrink();
    return Container(
      width: width,
      height: 24,
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Stack(
        children: [
          for (final segment in replay.segments)
            Positioned(
              left: width * segment.start.inMilliseconds / totalMs,
              width: (width * segment.duration.inMilliseconds / totalMs)
                  .clamp(2, width),
              top: 0,
              bottom: 0,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: .7),
                decoration: BoxDecoration(
                  color: _stationColor(segment.type),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ExportSegmentRow extends StatelessWidget {
  const _ExportSegmentRow({required this.segment});

  final ReplaySegment segment;

  @override
  Widget build(BuildContext context) => Container(
        width: 356,
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.white10)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _stationColor(segment.type).withValues(alpha: .16),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _stationIcon(segment.type),
                    size: 17,
                    color: _stationColor(segment.type),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 214,
                  child: Text(
                    '${segment.sequenceIndex + 1}. ${segment.name}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                SizedBox(
                  width: 100,
                  child: Text(
                    _clock(segment.duration),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 42),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_shortClock(segment.start)} – ${_shortClock(segment.end)}'
                    '  ·  ${segment.averageHeartRate == null ? '无心率交集' : '平均 ${segment.averageHeartRate} / 最高 ${segment.maximumHeartRate} bpm'}',
                    style: TextStyle(
                      color: segment.averageHeartRate == null
                          ? Colors.white38
                          : Colors.redAccent.shade100,
                      fontSize: 11,
                    ),
                  ),
                  if (segment.transitionDuration != null ||
                      segment.actualSpecification != null ||
                      segment.athleteName != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (segment.actualSpecification != null)
                          segment.actualSpecification!,
                        if (segment.athleteName != null)
                          '完成：${segment.athleteName}',
                        if (segment.transitionDuration != null)
                          '转换 ${_clock(segment.transitionDuration!)}',
                      ].join('  ·  '),
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
}

Color _zoneColor(HeartRateZone zone) => switch (zone) {
      HeartRateZone.zone1 => const Color(0xFF42A5F5),
      HeartRateZone.zone2 => const Color(0xFF48C751),
      HeartRateZone.zone3 => const Color(0xFFFFC12B),
      HeartRateZone.zone4 => const Color(0xFFFF7A16),
      HeartRateZone.zone5 => const Color(0xFFFF3B4D),
    };

Color _stationColor(StationType type) =>
    type == StationType.run ? const Color(0xFF4ECB63) : const Color(0xFFFFB016);

IconData _stationIcon(StationType type) => switch (type) {
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

String _clock(Duration duration) {
  String two(int value) => value.toString().padLeft(2, '0');
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  return hours > 0
      ? '${two(hours)}:${two(minutes)}:${two(seconds)}'
      : '${two(minutes)}:${two(seconds)}';
}

String _shortClock(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60);
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

List<FlSpot> _chartSpots(List<ReplayHeartRatePoint> points) {
  final spots = <FlSpot>[];
  for (var index = 0; index < points.length; index++) {
    if (index > 0 &&
        points[index].elapsed - points[index - 1].elapsed >
            const Duration(seconds: 30)) {
      spots.add(FlSpot.nullSpot);
    }
    spots.add(
      FlSpot(
        points[index].elapsed.inMilliseconds / 1000,
        points[index].bpm.toDouble(),
      ),
    );
  }
  return spots;
}
