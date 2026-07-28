import 'package:flutter/material.dart';

import '../../domain/models/training_models.dart';
import '../../domain/models/training_template.dart';

Future<TemplateSegmentInput?> showTrainingSegmentPicker(
  BuildContext context,
) async {
  final type = await showModalBottomSheet<StationType>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Column(
          children: [
            const ListTile(
              title: Text('添加临时项目'),
              subtitle: Text('只加入本次训练，不会修改原模板'),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final type in StationType.values)
                    ListTile(
                      leading: StationTypeIcon(type: type),
                      title: Text(type.label),
                      subtitle: Text(_optionalFieldsLabel(type)),
                      onTap: () => Navigator.pop(context, type),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  if (type == null || !context.mounted) return null;
  return showDialog<TemplateSegmentInput>(
    context: context,
    builder: (context) => _SegmentInputDialog(type: type),
  );
}

class _SegmentInputDialog extends StatefulWidget {
  const _SegmentInputDialog({required this.type});

  final StationType type;

  @override
  State<_SegmentInputDialog> createState() => _SegmentInputDialogState();
}

class _SegmentInputDialogState extends State<_SegmentInputDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _resistanceController;
  late final TextEditingController _weightController;
  late final TextEditingController _distanceController;
  late final TextEditingController _repetitionsController;

  StationType get type => widget.type;

  @override
  void initState() {
    super.initState();
    _resistanceController = TextEditingController();
    _weightController = TextEditingController();
    _distanceController = TextEditingController(
      text: type == StationType.run ? '1000' : '',
    );
    _repetitionsController = TextEditingController();
  }

  @override
  void dispose() {
    _resistanceController.dispose();
    _weightController.dispose();
    _distanceController.dispose();
    _repetitionsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasResistance = type == StationType.skiErg || type == StationType.row;
    final hasWeight = type == StationType.sledPush ||
        type == StationType.sledPull ||
        type == StationType.farmerCarry ||
        type == StationType.sandbagLunge ||
        type == StationType.wallBall;
    final hasDistance = type != StationType.wallBall;
    final hasRepetitions =
        type == StationType.burpeeBroadJump || type == StationType.wallBall;
    return AlertDialog(
      scrollable: true,
      title: Text(type == StationType.run ? '跑步距离' : '${type.label} 参数'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              type == StationType.run ? '跑步距离为必填项。' : '以下参数均为选填。',
              style: const TextStyle(color: Colors.white54),
            ),
            if (hasResistance) ...[
              const SizedBox(height: 14),
              _NumberField(
                controller: _resistanceController,
                label: '阻力档位',
                suffix: '档',
              ),
            ],
            if (hasWeight) ...[
              const SizedBox(height: 14),
              _NumberField(
                controller: _weightController,
                label: _weightLabel(type),
                suffix: 'kg',
                decimal: true,
              ),
            ],
            if (hasDistance) ...[
              const SizedBox(height: 14),
              _NumberField(
                controller: _distanceController,
                label: '距离',
                suffix: 'm',
                required: type == StationType.run,
              ),
            ],
            if (hasRepetitions) ...[
              const SizedBox(height: 14),
              _NumberField(
                controller: _repetitionsController,
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
            if (!(_formKey.currentState?.validate() ?? false)) return;
            Navigator.pop(
              context,
              TemplateSegmentInput(
                type: type,
                targetResistanceLevel: _optionalInt(_resistanceController.text),
                targetWeightKg: _optionalDouble(_weightController.text),
                targetDistanceMeters: _optionalInt(_distanceController.text),
                targetRepetitions: _optionalInt(_repetitionsController.text),
              ),
            );
          },
          child: const Text('继续'),
        ),
      ],
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    required this.suffix,
    this.decimal = false,
    this.required = false,
  });

  final TextEditingController controller;
  final String label;
  final String suffix;
  final bool decimal;
  final bool required;

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
          if (text.isEmpty) return required ? '请填写距离' : null;
          final value = decimal
              ? double.tryParse(text.replaceAll(',', '.'))
              : int.tryParse(text)?.toDouble();
          return value == null || value <= 0 ? '请输入大于 0 的数字' : null;
        },
      );
}

class StationTypeIcon extends StatelessWidget {
  const StationTypeIcon({required this.type, this.size = 42, super.key});

  final StationType type;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = stationTypeColor(type);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      alignment: Alignment.center,
      child: Icon(stationTypeIconData(type), color: color, size: size * 0.56),
    );
  }
}

IconData stationTypeIconData(StationType type) => switch (type) {
      StationType.run => Icons.directions_run_rounded,
      StationType.skiErg => Icons.downhill_skiing_rounded,
      StationType.sledPush => Icons.trending_flat_rounded,
      StationType.sledPull => Icons.keyboard_backspace_rounded,
      StationType.burpeeBroadJump => Icons.sports_gymnastics_rounded,
      StationType.row => Icons.rowing_rounded,
      StationType.farmerCarry => Icons.work_rounded,
      StationType.sandbagLunge => Icons.airline_seat_legroom_extra_rounded,
      StationType.wallBall => Icons.sports_basketball_rounded,
    };

Color stationTypeColor(StationType type) => switch (type) {
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

String _optionalFieldsLabel(StationType type) => switch (type) {
      StationType.run => '设置本次跑步距离',
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

int? _optionalInt(String input) {
  final text = input.trim();
  return text.isEmpty ? null : int.parse(text);
}

double? _optionalDouble(String input) {
  final text = input.trim();
  return text.isEmpty ? null : double.parse(text.replaceAll(',', '.'));
}
