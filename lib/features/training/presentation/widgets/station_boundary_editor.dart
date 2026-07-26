import 'package:flutter/material.dart';

import '../../../heart_rate/domain/models/heart_rate_models.dart';
import '../../domain/models/training_models.dart';
import '../../domain/models/training_report.dart';
import '../formatters/training_formatters.dart';

typedef StationCorrectionBoundary = ({
  StationRecord previous,
  StationRecord next,
});

List<StationCorrectionBoundary> stationCorrectionBoundaries(
  TrainingReport report,
) {
  final result = <StationCorrectionBoundary>[];
  for (var index = 0; index < report.stations.length - 1; index++) {
    final previous = report.stations[index];
    final next = report.stations[index + 1];
    if (previous.status != SegmentStatus.completed ||
        next.status != SegmentStatus.completed ||
        previous.startedAt == null ||
        previous.endedAt == null ||
        next.startedAt == null ||
        next.endedAt == null ||
        !next.endedAt!.isAfter(previous.startedAt!.add(
          const Duration(seconds: 2),
        ))) {
      continue;
    }
    result.add((previous: previous, next: next));
  }
  return result;
}

Future<StationCorrectionBoundary?> showStationBoundaryPicker(
  BuildContext context, {
  required TrainingReport report,
}) {
  final boundaries = stationCorrectionBoundaries(report);
  if (boundaries.isEmpty || report.session.startedAt == null) {
    return Future.value();
  }
  return showModalBottomSheet<StationCorrectionBoundary>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .72,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '选择误触的分段交界',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '例如跑步被并入下一项目，请选择“该跑步 → 下一项目”。',
                    style: TextStyle(color: Colors.white54),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: boundaries.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final boundary = boundaries[index];
                  final previousElapsed = boundary.previous.endedAt!
                      .difference(report.session.startedAt!);
                  final nextElapsed = boundary.next.startedAt!
                      .difference(report.session.startedAt!);
                  final sameBoundary = previousElapsed == nextElapsed;
                  return ListTile(
                    leading: CircleAvatar(
                      child: Text('${boundary.previous.sequenceIndex + 1}'),
                    ),
                    title: Text(
                      '${boundary.previous.displayName}  →  '
                      '${boundary.next.displayName}',
                    ),
                    subtitle: Text(
                      sameBoundary
                          ? '当前交界：${formatDuration(previousElapsed)}'
                          : '上一段结束 ${formatDuration(previousElapsed)} · '
                              '下一段开始 ${formatDuration(nextElapsed)}',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.pop(context, boundary),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<DateTime?> showStationBoundaryEditor(
  BuildContext context, {
  required TrainingSession session,
  required StationRecord previous,
  required StationRecord next,
  required List<HeartRateSample> heartRateSamples,
}) {
  return showDialog<DateTime>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _StationBoundaryEditor(
      session: session,
      previous: previous,
      next: next,
      heartRateSamples: heartRateSamples,
    ),
  );
}

class _StationBoundaryEditor extends StatefulWidget {
  const _StationBoundaryEditor({
    required this.session,
    required this.previous,
    required this.next,
    required this.heartRateSamples,
  });

  final TrainingSession session;
  final StationRecord previous;
  final StationRecord next;
  final List<HeartRateSample> heartRateSamples;

  @override
  State<_StationBoundaryEditor> createState() => _StationBoundaryEditorState();
}

class _StationBoundaryEditorState extends State<_StationBoundaryEditor> {
  late final TextEditingController _controller;
  String? _error;

  DateTime get _sessionStartedAt => widget.session.startedAt!;
  DateTime get _minimum => widget.previous.startedAt!.add(
        const Duration(seconds: 1),
      );
  DateTime get _maximum => widget.next.endedAt!.subtract(
        const Duration(seconds: 1),
      );

  @override
  void initState() {
    super.initState();
    final initial = _initialBoundary();
    _controller = TextEditingController(
      text: _formatElapsed(initial.difference(_sessionStartedAt)),
    )..addListener(_refreshPreview);
  }

  DateTime _initialBoundary() {
    final candidate = widget.previous.endedAt ?? widget.next.startedAt!;
    if (candidate.isBefore(_minimum)) return _minimum;
    if (candidate.isAfter(_maximum)) return _maximum;
    return candidate;
  }

  void _refreshPreview() {
    if (mounted) setState(() => _error = null);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_refreshPreview)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final boundary = _parsedBoundary(showError: false);
    final previousSummary = boundary == null
        ? null
        : _summaryBetween(
            widget.heartRateSamples,
            widget.previous.startedAt!,
            boundary,
          );
    final nextSummary = boundary == null
        ? null
        : _summaryBetween(
            widget.heartRateSamples,
            boundary,
            widget.next.endedAt!,
          );
    final hadTransition = widget.previous.endedAt != widget.next.startedAt;

    return AlertDialog(
      title: const Text('修正分段交界'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${widget.previous.displayName}\n→ ${widget.next.displayName}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _controller,
                keyboardType: TextInputType.datetime,
                decoration: InputDecoration(
                  labelText: '新交界时间（从训练开始计算）',
                  hintText: '例如 32:15 或 01:02:15',
                  errorText: _error,
                  helperText:
                      '允许范围：${_formatElapsed(_minimum.difference(_sessionStartedAt))}'
                      ' – ${_formatElapsed(_maximum.difference(_sessionStartedAt))}',
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _AdjustmentButton(
                    label: '-5秒',
                    onPressed: () => _adjust(const Duration(seconds: -5)),
                  ),
                  _AdjustmentButton(
                    label: '-1秒',
                    onPressed: () => _adjust(const Duration(seconds: -1)),
                  ),
                  _AdjustmentButton(
                    label: '+1秒',
                    onPressed: () => _adjust(const Duration(seconds: 1)),
                  ),
                  _AdjustmentButton(
                    label: '+5秒',
                    onPressed: () => _adjust(const Duration(seconds: 5)),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                '保存后的心率预览',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _PreviewCard(
                      name: widget.previous.displayName,
                      duration:
                          boundary?.difference(widget.previous.startedAt!),
                      summary: previousSummary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _PreviewCard(
                      name: widget.next.displayName,
                      duration: boundary == null
                          ? null
                          : widget.next.endedAt!.difference(boundary),
                      summary: nextSummary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${hadTransition ? '原有转换区间会被这一个新交界时间替换。' : ''}'
                  '只会调整这两段的时间和统计；全程心率原始采样不会被修改。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('确认修正'),
        ),
      ],
    );
  }

  void _adjust(Duration delta) {
    final current = _parsedBoundary(showError: false) ?? _initialBoundary();
    var adjusted = current.add(delta);
    if (adjusted.isBefore(_minimum)) adjusted = _minimum;
    if (adjusted.isAfter(_maximum)) adjusted = _maximum;
    _controller.text = _formatElapsed(adjusted.difference(_sessionStartedAt));
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
  }

  void _save() {
    final boundary = _parsedBoundary(showError: true);
    if (boundary != null) Navigator.pop(context, boundary);
  }

  DateTime? _parsedBoundary({required bool showError}) {
    final elapsed = parseTrainingElapsed(_controller.text);
    String? error;
    DateTime? result;
    if (elapsed == null) {
      error = '请输入 MM:SS 或 HH:MM:SS';
    } else {
      result = _sessionStartedAt.add(elapsed);
      if (result.isBefore(_minimum) || result.isAfter(_maximum)) {
        error = '交界时间超出允许范围';
        result = null;
      }
    }
    if (showError && mounted) setState(() => _error = error);
    return result;
  }
}

class _AdjustmentButton extends StatelessWidget {
  const _AdjustmentButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(68, 36),
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
        onPressed: onPressed,
        child: Text(label),
      );
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.name,
    required this.duration,
    required this.summary,
  });

  final String name;
  final Duration? duration;
  final HeartRateSummary? summary;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .05),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(duration == null ? '--:--' : formatDuration(duration)),
            const SizedBox(height: 2),
            Text(
              summary == null
                  ? '无心率交集'
                  : '平均 ${summary!.average}\n最高 ${summary!.maximum} bpm',
              style: TextStyle(
                color: summary == null
                    ? Colors.white38
                    : Colors.redAccent.shade100,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
}

HeartRateSummary? _summaryBetween(
  List<HeartRateSample> samples,
  DateTime start,
  DateTime end,
) =>
    HeartRateSummary.fromSamples(
      samples.where(
        (sample) =>
            !sample.timestamp.isBefore(start) && sample.timestamp.isBefore(end),
      ),
    );

Duration? parseTrainingElapsed(String input) {
  final parts = input.trim().split(':');
  if (parts.length != 2 && parts.length != 3) return null;
  final values = parts.map(int.tryParse).toList(growable: false);
  if (values.any((value) => value == null || value < 0)) return null;
  final numbers = values.cast<int>();
  final seconds = numbers.last;
  if (seconds >= 60) return null;
  if (numbers.length == 2) {
    return Duration(minutes: numbers.first, seconds: seconds);
  }
  final minutes = numbers[1];
  if (minutes >= 60) return null;
  return Duration(hours: numbers[0], minutes: minutes, seconds: seconds);
}

String _formatElapsed(Duration duration) {
  String two(int value) => value.toString().padLeft(2, '0');
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  return hours > 0
      ? '${two(hours)}:${two(minutes)}:${two(seconds)}'
      : '${duration.inMinutes}:${two(seconds)}';
}
