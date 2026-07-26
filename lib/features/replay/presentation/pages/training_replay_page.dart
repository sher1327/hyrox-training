import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../training/domain/models/training_models.dart';
import '../../../training/presentation/formatters/training_formatters.dart';
import '../../domain/models/training_replay.dart';
import '../controllers/training_replay_providers.dart';

class TrainingReplayPage extends ConsumerWidget {
  const TrainingReplayPage({required this.sessionId, super.key});

  final int sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final replay = ref.watch(trainingReplayProvider(sessionId));
    return Scaffold(
      appBar: AppBar(title: const Text('训练回放')),
      body: replay.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _MessageState(
          icon: Icons.error_outline_rounded,
          title: '回放读取失败',
          message: '$error',
          actionLabel: '重试',
          onAction: () => ref.invalidate(trainingReplayProvider(sessionId)),
        ),
        data: (value) {
          if (value == null) {
            return const _MessageState(
              icon: Icons.search_off_rounded,
              title: '训练记录不存在',
              message: '这条训练可能已经被删除。',
            );
          }
          if (value.points.isEmpty) {
            return const _MessageState(
              icon: Icons.monitor_heart_outlined,
              title: '还没有心率数据',
              message: '请先在训练报告中导入 FIT 文件或 Intervals.icu 心率。',
            );
          }
          if (value.duration <= Duration.zero) {
            return const _MessageState(
              icon: Icons.timer_off_outlined,
              title: '训练时长无效',
              message: '这条训练没有可用于回放的时间范围。',
            );
          }
          return _ReplayBody(replay: value);
        },
      ),
    );
  }
}

class _ReplayBody extends ConsumerWidget {
  const _ReplayBody({required this.replay});

  final TrainingReplay replay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = ReplayPlaybackKey(
      sessionId: replay.sessionId,
      duration: replay.duration,
    );
    final playback = ref.watch(replayPlaybackProvider(key));
    final controller = ref.read(replayPlaybackProvider(key).notifier);
    final currentHeartRate = replay.heartRateAt(playback.elapsed);
    final currentZone = replay.zoneAt(playback.elapsed);
    final currentSegment = replay.segmentAt(playback.elapsed);

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
            children: [
              _SummaryCard(replay: replay),
              const SizedBox(height: 12),
              _NowCard(
                elapsed: playback.elapsed,
                duration: replay.duration,
                heartRate: currentHeartRate,
                zone: currentZone,
                segment: currentSegment,
              ),
              const SizedBox(height: 12),
              _SectionCard(
                title: '心率曲线',
                trailing: Text(
                  '最高 ${replay.maximumHeartRate ?? '--'}  '
                  '平均 ${replay.averageHeartRate ?? '--'}',
                  style: const TextStyle(color: Colors.white60),
                ),
                child: SizedBox(
                  height: 240,
                  child: _HeartRateChart(
                    replay: replay,
                    elapsed: playback.elapsed,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _SectionCard(
                title: '心率 Zone',
                subtitle: '当前按本次最高心率 '
                    '${replay.zoneReferenceMaximumBpm} bpm 计算',
                child: _ZoneStats(stats: replay.zoneStats),
              ),
              const SizedBox(height: 12),
              _SectionCard(
                title: '训练时间轴',
                child: Column(
                  children: [
                    _SegmentTimeline(
                      replay: replay,
                      elapsed: playback.elapsed,
                      onSeek: controller.seek,
                    ),
                    const SizedBox(height: 8),
                    Slider(
                      value: playback.elapsed.inMilliseconds
                          .clamp(0, replay.duration.inMilliseconds)
                          .toDouble(),
                      max: replay.duration.inMilliseconds
                          .clamp(1, double.maxFinite.toInt())
                          .toDouble(),
                      onChanged: (value) => controller.seek(
                        Duration(milliseconds: value.round()),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_clock(playback.elapsed)),
                        Text(_clock(replay.duration)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...replay.segments.map(
                      (segment) => _SegmentRow(
                        segment: segment,
                        selected: segment == currentSegment,
                        onTap: () => controller.seek(segment.start),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _PlaybackControls(
          playback: playback,
          onToggle: controller.toggle,
          onBack: () => controller.skip(const Duration(seconds: -15)),
          onForward: () => controller.skip(const Duration(seconds: 15)),
          onSpeedChanged: controller.setSpeed,
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.replay});

  final TrainingReplay replay;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: .14),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.directions_run_rounded,
                      color: Colors.redAccent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          replay.title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          formatSessionDate(replay.startedAt),
                          style: const TextStyle(color: Colors.white54),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _clock(replay.duration),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                      const Text(
                        '总时长',
                        style: TextStyle(color: Colors.white54),
                      ),
                    ],
                  ),
                ],
              ),
              const Divider(height: 30),
              Row(
                children: [
                  _SummaryMetric(
                    label: '平均心率',
                    value: '${replay.averageHeartRate ?? '--'}',
                    unit: 'bpm',
                  ),
                  _SummaryMetric(
                    label: '最大心率',
                    value: '${replay.maximumHeartRate ?? '--'}',
                    unit: 'bpm',
                  ),
                  _SummaryMetric(
                    label: '心率采样',
                    value: '${replay.points.length}',
                    unit: '条',
                  ),
                ],
              ),
            ],
          ),
        ),
      );
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.label,
    required this.value,
    required this.unit,
  });

  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          children: [
            Text(label, style: const TextStyle(color: Colors.white54)),
            const SizedBox(height: 5),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.redAccent.shade100,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            Text(unit, style: const TextStyle(color: Colors.white38)),
          ],
        ),
      );
}

class _NowCard extends StatelessWidget {
  const _NowCard({
    required this.elapsed,
    required this.duration,
    required this.heartRate,
    required this.zone,
    required this.segment,
  });

  final Duration elapsed;
  final Duration duration;
  final int? heartRate;
  final HeartRateZone? zone;
  final ReplaySegment? segment;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '当前时间',
                      style: TextStyle(color: Colors.white54),
                    ),
                    Text(
                      '${_clock(elapsed)} / ${_clock(duration)}',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      segment?.name ?? '转换 / 未记录区间',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: segment == null
                            ? Colors.white38
                            : _stationColor(segment!.type),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: (zone == null ? Colors.white : _zoneColor(zone!))
                      .withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${heartRate ?? '--'}',
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                color: zone == null
                                    ? Colors.white
                                    : _zoneColor(zone!),
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const Padding(
                          padding: EdgeInsets.only(bottom: 4, left: 3),
                          child: Text('bpm'),
                        ),
                      ],
                    ),
                    Text(zone?.label ?? '--'),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: Colors.white54),
                          ),
                      ],
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
              const SizedBox(height: 16),
              child,
            ],
          ),
        ),
      );
}

class _HeartRateChart extends StatelessWidget {
  const _HeartRateChart({required this.replay, required this.elapsed});

  final TrainingReplay replay;
  final Duration elapsed;

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
    return Padding(
      padding: const EdgeInsets.only(top: 6, right: 8),
      child: LineChart(
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
            getDrawingHorizontalLine: (_) => const FlLine(
              color: Colors.white10,
              strokeWidth: 1,
            ),
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
                reservedSize: 36,
                interval: horizontalInterval,
                getTitlesWidget: (value, _) => Text(
                  value.round().toString(),
                  style: const TextStyle(fontSize: 10, color: Colors.white54),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: verticalInterval,
                getTitlesWidget: (value, _) => Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Text(
                    _shortClock(Duration(milliseconds: (value * 1000).round())),
                    style: const TextStyle(fontSize: 10, color: Colors.white54),
                  ),
                ),
              ),
            ),
          ),
          extraLinesData: ExtraLinesData(
            verticalLines: [
              VerticalLine(
                x: elapsed.inMilliseconds / 1000,
                color: Colors.white,
                strokeWidth: 1.5,
                dashArray: [5, 4],
              ),
            ],
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
                    Colors.redAccent.withValues(alpha: .28),
                    Colors.redAccent.withValues(alpha: .01),
                  ],
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 80),
      ),
    );
  }
}

class _ZoneStats extends StatelessWidget {
  const _ZoneStats({required this.stats});

  final List<HeartRateZoneStat> stats;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 14,
              child: Row(
                children: [
                  for (final stat in stats)
                    if (stat.percentage > 0)
                      Expanded(
                        flex: (stat.percentage * 1000).round().clamp(1, 1000),
                        child: ColoredBox(color: _zoneColor(stat.zone)),
                      ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final stat in stats)
                SizedBox(
                  width: 94,
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 34,
                        decoration: BoxDecoration(
                          color: _zoneColor(stat.zone),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${stat.zone.label} '
                              '${(stat.percentage * 100).round()}%',
                              maxLines: 1,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            Text(
                              _shortClock(stat.duration),
                              style: const TextStyle(color: Colors.white54),
                            ),
                          ],
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

class _SegmentTimeline extends StatelessWidget {
  const _SegmentTimeline({
    required this.replay,
    required this.elapsed,
    required this.onSeek,
  });

  final TrainingReplay replay;
  final Duration elapsed;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final totalMs = replay.duration.inMilliseconds;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) {
              final ratio = (details.localPosition.dx / constraints.maxWidth)
                  .clamp(0.0, 1.0);
              onSeek(Duration(milliseconds: (totalMs * ratio).round()));
            },
            child: SizedBox(
              height: 30,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                  for (final segment in replay.segments)
                    Positioned(
                      left: constraints.maxWidth *
                          segment.start.inMilliseconds /
                          totalMs,
                      width: (constraints.maxWidth *
                              segment.duration.inMilliseconds /
                              totalMs)
                          .clamp(2, constraints.maxWidth),
                      top: 0,
                      bottom: 0,
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(
                          color:
                              _stationColor(segment.type).withValues(alpha: .8),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  Positioned(
                    left: (constraints.maxWidth *
                            elapsed.inMilliseconds /
                            totalMs)
                        .clamp(0, constraints.maxWidth - 2),
                    top: -2,
                    bottom: -2,
                    child: Container(width: 2, color: Colors.white),
                  ),
                ],
              ),
            ),
          );
        },
      );
}

class _SegmentRow extends StatelessWidget {
  const _SegmentRow({
    required this.segment,
    required this.selected,
    required this.onTap,
  });

  final ReplaySegment segment;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? _stationColor(segment.type).withValues(alpha: .12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 17,
                backgroundColor:
                    _stationColor(segment.type).withValues(alpha: .2),
                foregroundColor: _stationColor(segment.type),
                child: Icon(_stationIcon(segment.type), size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      segment.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    Text(
                      '${_shortClock(segment.start)} – '
                      '${_shortClock(segment.end)}',
                      style: const TextStyle(color: Colors.white54),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _shortClock(segment.duration),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    segment.averageHeartRate == null
                        ? '无心率交集'
                        : '平均 ${segment.averageHeartRate} bpm',
                    style: TextStyle(
                      color: segment.averageHeartRate == null
                          ? Colors.white38
                          : Colors.redAccent.shade100,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
}

class _PlaybackControls extends StatelessWidget {
  const _PlaybackControls({
    required this.playback,
    required this.onToggle,
    required this.onBack,
    required this.onForward,
    required this.onSpeedChanged,
  });

  final ReplayPlaybackState playback;
  final VoidCallback onToggle;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final ValueChanged<double> onSpeedChanged;

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xFF141718),
        elevation: 12,
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: '后退 15 秒',
                onPressed: onBack,
                icon: const Icon(Icons.replay_10_rounded),
              ),
              const SizedBox(width: 12),
              FilledButton(
                style: FilledButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(16),
                  minimumSize: const Size.square(58),
                ),
                onPressed: onToggle,
                child: Icon(
                  playback.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  size: 30,
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                tooltip: '前进 15 秒',
                onPressed: onForward,
                icon: const Icon(Icons.forward_10_rounded),
              ),
              const Spacer(),
              DropdownButtonHideUnderline(
                child: DropdownButton<double>(
                  value: playback.speed,
                  borderRadius: BorderRadius.circular(10),
                  items: const [
                    DropdownMenuItem(value: .5, child: Text('0.5×')),
                    DropdownMenuItem(value: 1, child: Text('1.0×')),
                    DropdownMenuItem(value: 2, child: Text('2.0×')),
                    DropdownMenuItem(value: 4, child: Text('4.0×')),
                  ],
                  onChanged: (value) {
                    if (value != null) onSpeedChanged(value);
                  },
                ),
              ),
            ],
          ),
        ),
      );
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 56, color: Colors.white38),
              const SizedBox(height: 16),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 16),
                FilledButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ],
          ),
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
