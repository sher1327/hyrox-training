import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../replay/presentation/controllers/training_replay_providers.dart';
import '../../../training/presentation/controllers/training_providers.dart';
import '../../domain/models/heart_rate_models.dart';
import '../controllers/heart_rate_providers.dart';

class HeartRateSourcesPage extends ConsumerStatefulWidget {
  const HeartRateSourcesPage({required this.sessionId, super.key});

  final int sessionId;

  @override
  ConsumerState<HeartRateSourcesPage> createState() =>
      _HeartRateSourcesPageState();
}

class _HeartRateSourcesPageState
    extends ConsumerState<HeartRateSourcesPage> {
  final Set<int> _visibleBatchIds = {};
  bool _switching = false;

  @override
  Widget build(BuildContext context) {
    final sources = ref.watch(heartRateSourcesProvider(widget.sessionId));
    return Scaffold(
      appBar: AppBar(title: const Text('心率来源与对比')),
      body: sources.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('心率读取失败：$error')),
        data: (items) {
          if (items.isEmpty) {
            return const Center(
              child: Text(
                '还没有心率数据\n训练中连接心率带，或结束后从 Intervals.icu 导入。',
                textAlign: TextAlign.center,
              ),
            );
          }
          final defaults = [
            ...items.where((item) => item.batch.isActive),
            ...items.where((item) => !item.batch.isActive),
          ].take(2).map((item) => item.batch.id).toSet();
          final visible =
              _visibleBatchIds.isEmpty ? defaults : _visibleBatchIds;
          final shown = items
              .where((item) => visible.contains(item.batch.id))
              .toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '主要计算来源',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        '平均/最高心率、分段心率、Zone 和训练回放都使用主要来源。'
                        '切换不会删除其他来源。',
                        style: TextStyle(color: Colors.white54),
                      ),
                      const SizedBox(height: 8),
                      for (final item in items)
                        ListTile(
                          enabled: !_switching,
                          onTap: item.batch.isActive || _switching
                              ? null
                              : () => _setPrimary(item.batch.id),
                          leading: Icon(
                            item.batch.isActive
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            color: item.batch.isActive
                                ? Theme.of(context).colorScheme.primary
                                : null,
                          ),
                          title: Text(item.batch.displayName),
                          subtitle: Text(
                            '${item.batch.sourceLabel} · '
                            '${item.batch.sampleCount} 条 · '
                            '平均 ${item.batch.average} · '
                            '最高 ${item.batch.maximum} bpm',
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '曲线显示（最多两条）',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final item in items)
                    FilterChip(
                      selected: visible.contains(item.batch.id),
                      label: Text(item.batch.displayName),
                      onSelected: (selected) {
                        final next = Set<int>.of(visible);
                        if (selected) {
                          if (next.length >= 2) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('最多同时显示两个来源')),
                            );
                            return;
                          }
                          next.add(item.batch.id);
                        } else if (next.length > 1) {
                          next.remove(item.batch.id);
                        }
                        setState(() {
                          _visibleBatchIds
                            ..clear()
                            ..addAll(next);
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 18, 18, 12),
                  child: SizedBox(
                    height: 320,
                    child: _ComparisonChart(sources: shown),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              for (var index = 0; index < shown.length; index++)
                ListTile(
                  leading: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: _seriesColors[index],
                      shape: BoxShape.circle,
                    ),
                  ),
                  title: Text(shown[index].batch.displayName),
                  subtitle: Text(shown[index].batch.sourceLabel),
                  trailing: Text(
                    '平均 ${shown[index].batch.average}\n'
                    '最高 ${shown[index].batch.maximum}',
                    textAlign: TextAlign.end,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _setPrimary(int importBatchId) async {
    setState(() => _switching = true);
    try {
      final repository =
          await ref.read(heartRateRepositoryFutureProvider.future);
      await repository.setActiveBatch(
        sessionId: widget.sessionId,
        importBatchId: importBatchId,
      );
      ref.invalidate(heartRateSourcesProvider(widget.sessionId));
      ref.invalidate(heartRateAnalysisProvider(widget.sessionId));
      ref.invalidate(trainingReplayProvider(widget.sessionId));
      ref.invalidate(trainingReportProvider(widget.sessionId));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('切换心率来源失败：$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }
}

class _ComparisonChart extends StatelessWidget {
  const _ComparisonChart({required this.sources});

  final List<HeartRateSourceData> sources;

  @override
  Widget build(BuildContext context) {
    final samples = sources.expand((item) => item.samples).toList();
    if (samples.isEmpty) {
      return const Center(child: Text('没有可绘制的心率采样'));
    }
    final start = samples
        .map((sample) => sample.timestamp)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final end = samples
        .map((sample) => sample.timestamp)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final minimum = samples
        .map((sample) => sample.bpm)
        .reduce((a, b) => a < b ? a : b);
    final maximum = samples
        .map((sample) => sample.bpm)
        .reduce((a, b) => a > b ? a : b);
    final minY = (minimum - 10).clamp(30, 240).toDouble();
    final maxY = (maximum + 10).clamp(minY + 20, 260).toDouble();
    final maxX =
        end.difference(start).inMilliseconds.clamp(1000, 1 << 62) / 1000;
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: maxX,
        minY: minY,
        maxY: maxY,
        clipData: const FlClipData.all(),
        borderData: FlBorderData(
          show: true,
          border: const Border(
            left: BorderSide(color: Colors.white12),
            bottom: BorderSide(color: Colors.white12),
          ),
        ),
        gridData: const FlGridData(drawVerticalLine: false),
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
              interval: (maxX / 4).clamp(1, double.infinity).toDouble(),
              getTitlesWidget: (value, _) => Text(
                _clock(Duration(seconds: value.round())),
                style: const TextStyle(fontSize: 10, color: Colors.white54),
              ),
            ),
          ),
        ),
        lineBarsData: [
          for (var index = 0; index < sources.length; index++)
            LineChartBarData(
              spots: _spots(sources[index].samples, start),
              isCurved: true,
              curveSmoothness: .18,
              color: _seriesColors[index],
              barWidth: 2.4,
              dotData: const FlDotData(show: false),
            ),
        ],
      ),
      duration: const Duration(milliseconds: 120),
    );
  }
}

List<FlSpot> _spots(List<HeartRateSample> values, DateTime start) {
  final samples = [...values]
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  final spots = <FlSpot>[];
  for (var index = 0; index < samples.length; index++) {
    if (index > 0 &&
        samples[index].timestamp.difference(samples[index - 1].timestamp) >
            const Duration(seconds: 30)) {
      spots.add(FlSpot.nullSpot);
    }
    spots.add(
      FlSpot(
        samples[index].timestamp.difference(start).inMilliseconds / 1000,
        samples[index].bpm.toDouble(),
      ),
    );
  }
  return spots;
}

String _clock(Duration value) {
  final minutes = value.inMinutes;
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

const _seriesColors = [Color(0xFFFFD719), Colors.redAccent];

