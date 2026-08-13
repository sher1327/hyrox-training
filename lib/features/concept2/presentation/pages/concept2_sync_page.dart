import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../training/domain/models/training_models.dart';
import '../../../training/presentation/controllers/training_providers.dart';
import '../../data/services/concept2_logbook_client.dart';
import '../../domain/models/concept2_models.dart';
import '../controllers/concept2_providers.dart';

class Concept2SyncPage extends ConsumerStatefulWidget {
  const Concept2SyncPage({required this.sessionId, super.key});

  final int sessionId;

  @override
  ConsumerState<Concept2SyncPage> createState() => _Concept2SyncPageState();
}

class _Concept2SyncPageState extends ConsumerState<Concept2SyncPage> {
  bool _syncing = false;

  @override
  Widget build(BuildContext context) {
    final report = ref.watch(trainingReportProvider(widget.sessionId));
    final result = ref.watch(concept2ResultProvider(widget.sessionId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Concept2 器械数据'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'token') _configureToken();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'token', child: Text('更换授权 Token')),
            ],
          ),
        ],
      ),
      body: report.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('训练读取失败：$error')),
        data: (value) {
          if (value == null) return const Center(child: Text('训练不存在'));
          final machine = _machineFor(value.stations);
          if (machine == null) {
            return const Center(
              child: Text(
                'Concept2 同步仅用于单项目划船或滑雪训练。',
                textAlign: TextAlign.center,
              ),
            );
          }
          final session = value.session;
          if (session.startedAt == null || session.endedAt == null) {
            return const Center(child: Text('训练结束后才能同步 Logbook'));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              _SyncStatusCard(
                machine: machine,
                syncing: _syncing,
                hasResult: result.valueOrNull != null,
                onSync: _syncing
                    ? null
                    : () => _sync(
                          machine: machine,
                          sessionStart: session.startedAt!,
                          sessionEnd: session.endedAt!,
                        ),
              ),
              const SizedBox(height: 14),
              result.when(
                loading: () => const LinearProgressIndicator(),
                error: (error, _) => Text('本地器械数据读取失败：$error'),
                data: (item) => item == null
                    ? const _EmptyResult()
                    : _ResultDetails(
                        result: item,
                        appDuration: session.endedAt!.difference(
                          session.startedAt!,
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _sync({
    required Concept2Machine machine,
    required DateTime sessionStart,
    required DateTime sessionEnd,
  }) async {
    var credentials =
        await ref.read(concept2CredentialsStoreProvider).read();
    credentials ??= await _requestToken();
    if (credentials == null || !mounted) return;
    setState(() => _syncing = true);
    try {
      final client = ref.read(concept2ClientProvider);
      final listed = await client.listResults(
        credentials: credentials,
        machine: machine,
        from: sessionStart.subtract(const Duration(days: 1)),
        to: sessionEnd.add(const Duration(days: 1)),
      );
      final candidates = Concept2ResultMatcher.forSession(
        results: listed,
        machine: machine,
        sessionStart: sessionStart,
        sessionEnd: sessionEnd,
      );
      if (candidates.isEmpty) {
        throw StateError(
          '没有找到时间接近的${machine.label}记录。请先确认 ErgData 已上传 Logbook。',
        );
      }
      final selected = candidates.length == 1
          ? candidates.single
          : await _selectCandidate(candidates);
      if (selected == null || !mounted) return;
      final detail = await client.getResult(
        credentials: credentials,
        resultId: selected.id,
      );
      final repository =
          await ref.read(concept2RepositoryFutureProvider.future);
      await repository.saveForSession(
        sessionId: widget.sessionId,
        result: detail,
        importedAt: DateTime.now().toUtc(),
      );
      ref.invalidate(concept2ResultProvider(widget.sessionId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Concept2 器械数据已保存到本地')),
        );
      }
    } on Concept2ApiException catch (error) {
      if (error.credentialsRejected) {
        await ref.read(concept2CredentialsStoreProvider).clear();
      }
      _showError(error.toString());
    } catch (error) {
      _showError(error.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<Concept2Credentials?> _requestToken() async {
    final controller = TextEditingController();
    final token = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('连接 Concept2 Logbook'),
        content: TextField(
          controller: controller,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: '长期授权 Token',
            helperText: '在 Concept2 Logbook 的 API integration 中生成',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('保存并同步'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (token == null || token.isEmpty) return null;
    final credentials = Concept2Credentials(token);
    await ref.read(concept2CredentialsStoreProvider).save(credentials);
    return credentials;
  }

  Future<void> _configureToken() async {
    await ref.read(concept2CredentialsStoreProvider).clear();
    if (!mounted) return;
    final saved = await _requestToken();
    if (saved != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Concept2 Token 已更新')),
      );
    }
  }

  Future<Concept2Result?> _selectCandidate(
    List<Concept2Result> candidates,
  ) =>
      showModalBottomSheet<Concept2Result>(
        context: context,
        useSafeArea: true,
        builder: (context) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Text(
              '选择 Concept2 记录',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            for (final item in candidates)
              ListTile(
                onTap: () => Navigator.pop(context, item),
                leading: const Icon(Icons.sports_gymnastics_rounded),
                title: Text(
                  '${item.distanceMeters} m · ${_duration(item.workDuration)}',
                ),
                subtitle: Text(
                  '${_dateTime(item.endedAt)}结束 · ${item.workoutType}',
                ),
                trailing: const Icon(Icons.chevron_right),
              ),
          ],
        ),
      );

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _SyncStatusCard extends StatelessWidget {
  const _SyncStatusCard({
    required this.machine,
    required this.syncing,
    required this.hasResult,
    required this.onSync,
  });

  final Concept2Machine machine;
  final bool syncing;
  final bool hasResult;
  final VoidCallback? onSync;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Concept2 Logbook · ${machine.label}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                hasResult
                    ? '已保存器械总成绩和内部间歇；重新同步会替换这份器械数据。'
                    : 'App 只记录整场时间；PM5 的间歇结构由 Logbook 补全。',
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: onSync,
                icon: syncing
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_download_rounded),
                label: Text(
                  syncing ? '正在查找 Logbook 记录…' : hasResult ? '重新同步' : '同步器械数据',
                ),
              ),
            ],
          ),
        ),
      );
}

class _EmptyResult extends StatelessWidget {
  const _EmptyResult();

  @override
  Widget build(BuildContext context) => const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            '还没有器械数据。完成训练并通过 ErgData 上传到 Logbook 后，点击上方同步。',
            textAlign: TextAlign.center,
          ),
        ),
      );
}

class _ResultDetails extends StatelessWidget {
  const _ResultDetails({required this.result, required this.appDuration});

  final Concept2Result result;
  final Duration appDuration;

  @override
  Widget build(BuildContext context) {
    final difference = appDuration - result.totalDuration;
    final metrics = <(String, String)>[
      ('App 总经过时间', _duration(appDuration)),
      ('PM5 工作时间', _duration(result.workDuration)),
      if (result.restTimeTenths > 0)
        ('PM5 休息时间', _duration(result.restDuration)),
      ('PM5 总训练时间', _duration(result.totalDuration)),
      ('计时差异', _signedDuration(difference)),
      ('总距离', '${result.distanceMeters} m'),
      if (result.strokeRate != null) ('平均 SPM', '${result.strokeRate}'),
      if (result.strokeCount != null) ('划桨总数', '${result.strokeCount}'),
      if (result.dragFactor != null) ('阻力系数', '${result.dragFactor}'),
      if (result.calories != null) ('卡路里', '${result.calories} kcal'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                for (final metric in metrics)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Expanded(child: Text(metric.$1)),
                        Text(
                          metric.$2,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text('PM5 内部间歇', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (result.intervals.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('这条 Logbook 记录只包含总成绩，没有上传分段或间歇。'),
            ),
          )
        else
          Card(
            child: Column(
              children: [
                for (var index = 0; index < result.intervals.length; index++)
                  _IntervalTile(
                    interval: result.intervals[index],
                    isLast: index == result.intervals.length - 1,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _IntervalTile extends StatelessWidget {
  const _IntervalTile({required this.interval, required this.isLast});

  final Concept2Interval interval;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final details = [
      '${interval.distanceMeters} m',
      _duration(interval.workDuration),
      if (interval.distanceMeters > 0)
        '${_pace(interval.timeTenths, interval.distanceMeters)} /500m',
      if (interval.strokeRate != null) '${interval.strokeRate} SPM',
    ];
    return Column(
      children: [
        ListTile(
          leading: CircleAvatar(child: Text('${interval.sequenceIndex + 1}')),
          title: Text(details.join(' · ')),
          subtitle: interval.restTimeTenths > 0
              ? Text('休息 ${_duration(interval.restDuration)}')
              : null,
        ),
        if (!isLast) const Divider(height: 1),
      ],
    );
  }
}

Concept2Machine? _machineFor(List<StationRecord> stations) {
  if (stations.length != 1) return null;
  return switch (stations.single.type) {
    StationType.row => Concept2Machine.rower,
    StationType.skiErg => Concept2Machine.skierg,
    _ => null,
  };
}

String _duration(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  final tenths = (value.inMilliseconds.remainder(1000) ~/ 100);
  return hours > 0
      ? '$hours:$minutes:$seconds.$tenths'
      : '${value.inMinutes}:$seconds.$tenths';
}

String _signedDuration(Duration value) {
  final sign = value.isNegative ? '-' : '+';
  return '$sign${_duration(value.abs())}';
}

String _pace(int timeTenths, int distanceMeters) {
  if (distanceMeters <= 0) return '--';
  return _duration(Duration(milliseconds: (timeTenths * 100 * 500 / distanceMeters).round()));
}

String _dateTime(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

