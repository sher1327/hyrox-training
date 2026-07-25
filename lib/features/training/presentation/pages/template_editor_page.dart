import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models/training_models.dart';
import '../../domain/models/training_template.dart';
import '../controllers/training_providers.dart';

class TemplateEditorPage extends ConsumerStatefulWidget {
  const TemplateEditorPage({this.templateId, super.key});

  final int? templateId;

  @override
  ConsumerState<TemplateEditorPage> createState() => _TemplateEditorPageState();
}

class _TemplateEditorPageState extends ConsumerState<TemplateEditorPage> {
  final _nameController = TextEditingController();
  final _segments = <TemplateSegmentInput>[];
  TemplateType _templateType = TemplateType.other;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (widget.templateId != null) {
      final repository =
          await ref.read(trainingTemplateRepositoryFutureProvider.future);
      final template = await repository.getTemplate(widget.templateId!);
      if (template == null) throw StateError('模板不存在');
      _nameController.text = template.name;
      _templateType = template.type;
      _segments.addAll(
        template.segments.map(
          (segment) => TemplateSegmentInput(
            type: segment.type,
            segmentKind: segment.segmentKind,
            targetDistanceMeters: segment.targetDistanceMeters,
            targetResistanceLevel: segment.targetResistanceLevel,
            targetWeightKg: segment.targetWeightKg,
            targetRepetitions: segment.targetRepetitions,
          ),
        ),
      );
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty) {
      _message('请输入模板名称');
      return;
    }
    if (_segments.isEmpty) {
      _message('请至少添加一个跑步或站点');
      return;
    }
    setState(() => _saving = true);
    try {
      final repository =
          await ref.read(trainingTemplateRepositoryFutureProvider.future);
      final now = ref.read(clockProvider).now();
      if (widget.templateId == null) {
        await repository.createTemplate(
          name: _nameController.text,
          type: _templateType,
          segments: _segments,
          createdAt: now,
        );
      } else {
        await repository.updateTemplate(
          templateId: widget.templateId!,
          name: _nameController.text,
          type: _templateType,
          segments: _segments,
          updatedAt: now,
        );
      }
      ref.invalidate(trainingTemplatesProvider);
      if (mounted) context.pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _message('保存模板失败：$error');
    }
  }

  void _message(String message) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.templateId == null ? '新建模板' : '编辑模板'),
          actions: [
            TextButton(
              onPressed: _saving || _loading ? null : _save,
              child: Text(_saving ? '保存中…' : '保存'),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
                children: [
                  TextField(
                    controller: _nameController,
                    maxLength: 30,
                    decoration: const InputDecoration(
                      labelText: '模板名称',
                      hintText: '例如：短跑力量循环',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<TemplateType>(
                    initialValue: _templateType,
                    decoration: const InputDecoration(
                      labelText: '模板类型',
                      border: OutlineInputBorder(),
                    ),
                    items: TemplateType.values
                        .map(
                          (type) => DropdownMenuItem(
                            value: type,
                            child: Text(type.label),
                          ),
                        )
                        .toList(),
                    onChanged: _saving
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() => _templateType = value);
                            }
                          },
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '训练顺序',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _addSegment,
                        icon: const Icon(Icons.add),
                        label: const Text('添加'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_segments.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          '点击“添加”，自由组合跑步和功能站。',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white54),
                        ),
                      ),
                    ),
                  for (var index = 0; index < _segments.length; index++)
                    _SegmentEditorRow(
                      index: index,
                      segment: _segments[index],
                      canMoveUp: index > 0,
                      canMoveDown: index < _segments.length - 1,
                      onEdit: () => _editSegment(index),
                      onMoveUp: () => _move(index, index - 1),
                      onMoveDown: () => _move(index, index + 1),
                      onDelete: () => setState(() => _segments.removeAt(index)),
                    ),
                ],
              ),
      );

  void _move(int from, int to) {
    if (to < 0 || to >= _segments.length) return;
    setState(() {
      final item = _segments.removeAt(from);
      _segments.insert(to, item);
    });
  }

  Future<void> _addSegment() async {
    final type = await showModalBottomSheet<StationType>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('选择项目')),
            for (final type in StationType.values)
              ListTile(
                leading: _StationTypeIcon(type: type),
                title: Text(type.label),
                subtitle: Text(
                  type == StationType.run
                      ? '需设置跑步距离'
                      : _optionalFieldsLabel(type),
                ),
                onTap: () => Navigator.pop(context, type),
              ),
          ],
        ),
      ),
    );
    if (type == null || !mounted) return;
    if (type == StationType.run) {
      final distance = await _askDistance(1000);
      if (distance == null) return;
      setState(() => _segments.add(
            TemplateSegmentInput(
              type: type,
              targetDistanceMeters: distance,
            ),
          ));
    } else {
      setState(() => _segments.add(TemplateSegmentInput(type: type)));
    }
  }

  Future<void> _editSegment(int index) async {
    if (_segments[index].type == StationType.run) {
      await _editRunDistance(index);
    } else {
      await _editStationSpecifications(index);
    }
  }

  Future<void> _editRunDistance(int index) async {
    final distance =
        await _askDistance(_segments[index].targetDistanceMeters ?? 1000);
    if (distance == null) return;
    setState(() {
      _segments[index] = TemplateSegmentInput(
        type: StationType.run,
        targetDistanceMeters: distance,
      );
    });
  }

  Future<void> _editStationSpecifications(int index) async {
    final segment = _segments[index];
    final hasResistance =
        segment.type == StationType.skiErg || segment.type == StationType.row;
    final hasWeight = segment.type == StationType.sledPush ||
        segment.type == StationType.sledPull ||
        segment.type == StationType.farmerCarry ||
        segment.type == StationType.sandbagLunge ||
        segment.type == StationType.wallBall;
    final hasDistance = segment.type != StationType.wallBall;
    final hasRepetitions = segment.type == StationType.burpeeBroadJump ||
        segment.type == StationType.wallBall;
    final formKey = GlobalKey<FormState>();
    final resistanceController = TextEditingController(
      text: segment.targetResistanceLevel?.toString() ?? '',
    );
    final weightController = TextEditingController(
      text: _formatWeightInput(segment.targetWeightKg),
    );
    final distanceController = TextEditingController(
      text: segment.targetDistanceMeters?.toString() ?? '',
    );
    final repetitionsController = TextEditingController(
      text: segment.targetRepetitions?.toString() ?? '',
    );

    final result = await showDialog<TemplateSegmentInput>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text('${segment.type.label} 参数'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '以下参数均为选填，留空即可。',
                style: TextStyle(color: Colors.white54),
              ),
              if (hasResistance) ...[
                const SizedBox(height: 14),
                _OptionalNumberField(
                  controller: resistanceController,
                  label: '阻力档位',
                  suffix: '档',
                ),
              ],
              if (hasWeight) ...[
                const SizedBox(height: 14),
                _OptionalNumberField(
                  controller: weightController,
                  label: _weightLabel(segment.type),
                  suffix: 'kg',
                  decimal: true,
                ),
              ],
              if (hasDistance) ...[
                const SizedBox(height: 14),
                _OptionalNumberField(
                  controller: distanceController,
                  label: '距离',
                  suffix: 'm',
                ),
              ],
              if (hasRepetitions) ...[
                const SizedBox(height: 14),
                _OptionalNumberField(
                  controller: repetitionsController,
                  label: '次数',
                  suffix: '次',
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (!(formKey.currentState?.validate() ?? false)) return;
              Navigator.pop(
                context,
                TemplateSegmentInput(
                  type: segment.type,
                  targetResistanceLevel:
                      _optionalInt(resistanceController.text),
                  targetWeightKg: _optionalDouble(weightController.text),
                  targetDistanceMeters: _optionalInt(distanceController.text),
                  targetRepetitions: _optionalInt(repetitionsController.text),
                ),
              );
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );

    resistanceController.dispose();
    weightController.dispose();
    distanceController.dispose();
    repetitionsController.dispose();
    if (result == null || !mounted) return;
    setState(() => _segments[index] = result);
  }

  Future<int?> _askDistance(int initialValue) async {
    var input = '$initialValue';
    return showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('跑步距离'),
        content: TextFormField(
          initialValue: input,
          autofocus: true,
          keyboardType: TextInputType.number,
          onChanged: (value) => input = value,
          decoration: const InputDecoration(
            labelText: '距离（米）',
            suffixText: 'm',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(input.trim());
              if (value != null && value > 0) Navigator.pop(context, value);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}

class _SegmentEditorRow extends StatelessWidget {
  const _SegmentEditorRow({
    required this.index,
    required this.segment,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onEdit,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onDelete,
  });

  final int index;
  final TemplateSegmentInput segment;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback? onEdit;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(top: 8),
        child: ListTile(
          leading: CircleAvatar(child: Text('${index + 1}')),
          title: Text(
            segment.displayName,
          ),
          subtitle:
              segment.type == StationType.run ? null : const Text('点击填写可选参数'),
          onTap: onEdit,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: '上移',
                onPressed: canMoveUp ? onMoveUp : null,
                icon: const Icon(Icons.arrow_upward),
              ),
              IconButton(
                tooltip: '下移',
                onPressed: canMoveDown ? onMoveDown : null,
                icon: const Icon(Icons.arrow_downward),
              ),
              IconButton(
                tooltip: '删除',
                onPressed: onDelete,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      );
}

class _OptionalNumberField extends StatelessWidget {
  const _OptionalNumberField({
    required this.controller,
    required this.label,
    required this.suffix,
    this.decimal = false,
  });

  final TextEditingController controller;
  final String label;
  final String suffix;
  final bool decimal;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        decoration: InputDecoration(
          labelText: label,
          suffixText: suffix,
          border: const OutlineInputBorder(),
        ),
        validator: (input) {
          final text = input?.trim() ?? '';
          if (text.isEmpty) return null;
          final value = decimal
              ? double.tryParse(text.replaceAll(',', '.'))
              : int.tryParse(text)?.toDouble();
          return value == null || value <= 0 ? '请输入大于 0 的数字' : null;
        },
      );
}

class _StationTypeIcon extends StatelessWidget {
  const _StationTypeIcon({required this.type});

  final StationType type;

  @override
  Widget build(BuildContext context) {
    final color = switch (type) {
      StationType.run => Colors.greenAccent,
      StationType.skiErg => Colors.lightBlueAccent,
      StationType.sledPush => Colors.amberAccent,
      StationType.sledPull => Colors.orangeAccent,
      StationType.burpeeBroadJump => Colors.purpleAccent,
      StationType.row => Colors.cyanAccent,
      StationType.farmerCarry => Colors.yellowAccent,
      StationType.sandbagLunge => Colors.deepOrangeAccent,
      StationType.wallBall => Colors.pinkAccent,
    };
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: IconTheme(
        data: IconThemeData(color: color, size: 24),
        child: switch (type) {
          StationType.run => const Icon(Icons.directions_run_rounded),
          StationType.skiErg => const Icon(Icons.downhill_skiing_rounded),
          StationType.sledPush => const _DirectionalSledIcon(push: true),
          StationType.sledPull => const _DirectionalSledIcon(push: false),
          StationType.burpeeBroadJump =>
            const Icon(Icons.sports_gymnastics_rounded),
          StationType.row => const Icon(Icons.rowing_rounded),
          StationType.farmerCarry => const _FarmerCarryIcon(),
          StationType.sandbagLunge =>
            const Icon(Icons.airline_seat_legroom_extra_rounded),
          StationType.wallBall => const Icon(Icons.sports_basketball_rounded),
        },
      ),
    );
  }
}

class _DirectionalSledIcon extends StatelessWidget {
  const _DirectionalSledIcon({required this.push});

  final bool push;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 30,
        height: 26,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Positioned(
              top: 0,
              child: Icon(Icons.sledding_rounded, size: 21),
            ),
            Positioned(
              left: push ? null : 1,
              right: push ? 1 : null,
              bottom: 0,
              child: Icon(
                push ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded,
                size: 13,
              ),
            ),
          ],
        ),
      );
}

class _FarmerCarryIcon extends StatelessWidget {
  const _FarmerCarryIcon();

  @override
  Widget build(BuildContext context) => const SizedBox(
        width: 30,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              left: 1,
              bottom: 2,
              child: Icon(Icons.work_rounded, size: 17),
            ),
            Positioned(
              right: 1,
              bottom: 2,
              child: Icon(Icons.work_rounded, size: 17),
            ),
          ],
        ),
      );
}

String _optionalFieldsLabel(StationType type) => switch (type) {
      StationType.run => '跑步距离',
      StationType.skiErg || StationType.row => '可选：阻力、距离',
      StationType.sledPush ||
      StationType.sledPull ||
      StationType.farmerCarry ||
      StationType.sandbagLunge =>
        '可选：重量、距离',
      StationType.burpeeBroadJump => '可选：距离、次数',
      StationType.wallBall => '可选：重量、次数',
    };

String _weightLabel(StationType type) => switch (type) {
      StationType.sledPush || StationType.sledPull => '总重量（含雪橇）',
      StationType.farmerCarry => '单只重量',
      _ => '重量',
    };

String _formatWeightInput(double? value) {
  if (value == null) return '';
  return value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);
}

int? _optionalInt(String input) {
  final text = input.trim();
  return text.isEmpty ? null : int.parse(text);
}

double? _optionalDouble(String input) {
  final text = input.trim();
  return text.isEmpty ? null : double.parse(text.replaceAll(',', '.'));
}
