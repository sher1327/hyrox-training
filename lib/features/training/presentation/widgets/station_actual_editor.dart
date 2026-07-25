import 'package:flutter/material.dart';

import '../../domain/models/training_models.dart';

Future<StationActualPerformance?> showStationActualEditor(
  BuildContext context,
  StationRecord station,
) =>
    showModalBottomSheet<StationActualPerformance>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _StationActualEditorSheet(station: station),
    );

class _StationActualEditorSheet extends StatefulWidget {
  const _StationActualEditorSheet({required this.station});

  final StationRecord station;

  @override
  State<_StationActualEditorSheet> createState() =>
      _StationActualEditorSheetState();
}

class _StationActualEditorSheetState extends State<_StationActualEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _distance;
  late final TextEditingController _resistance;
  late final TextEditingController _weight;
  late final TextEditingController _repetitions;

  StationRecord get station => widget.station;
  StationType get type => station.type;
  bool get hasResistance =>
      type == StationType.skiErg || type == StationType.row;
  bool get hasWeight =>
      type == StationType.sledPush ||
      type == StationType.sledPull ||
      type == StationType.farmerCarry ||
      type == StationType.sandbagLunge ||
      type == StationType.wallBall;
  bool get hasDistance => type != StationType.wallBall;
  bool get hasRepetitions =>
      type == StationType.burpeeBroadJump || type == StationType.wallBall;

  @override
  void initState() {
    super.initState();
    _distance = TextEditingController(
      text: _intText(
        station.actualDistanceMeters ?? station.targetDistanceMeters,
      ),
    );
    _resistance = TextEditingController(
      text: _intText(
        station.actualResistanceLevel ?? station.targetResistanceLevel,
      ),
    );
    _weight = TextEditingController(
      text: _doubleText(station.actualWeightKg ?? station.targetWeightKg),
    );
    _repetitions = TextEditingController(
      text: _intText(station.actualRepetitions ?? station.targetRepetitions),
    );
  }

  @override
  void dispose() {
    _distance.dispose();
    _resistance.dispose();
    _weight.dispose();
    _repetitions.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            20 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '实际完成 · ${station.type.label}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '默认已带入计划值，只需修改有差异的项目。',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: Colors.white54),
                  ),
                  if (hasResistance) ...[
                    const SizedBox(height: 16),
                    _ActualField(
                      controller: _resistance,
                      label: '实际阻力',
                      target: _targetText(
                        station.targetResistanceLevel,
                        '档',
                      ),
                      suffix: '档',
                    ),
                  ],
                  if (hasWeight) ...[
                    const SizedBox(height: 12),
                    _ActualField(
                      controller: _weight,
                      label: '实际重量',
                      target: _targetText(station.targetWeightKg, 'kg'),
                      suffix: 'kg',
                      decimal: true,
                    ),
                  ],
                  if (hasDistance) ...[
                    const SizedBox(height: 12),
                    _ActualField(
                      controller: _distance,
                      label: '实际距离',
                      target: _targetText(station.targetDistanceMeters, 'm'),
                      suffix: 'm',
                      allowZero: true,
                    ),
                  ],
                  if (hasRepetitions) ...[
                    const SizedBox(height: 12),
                    _ActualField(
                      controller: _repetitions,
                      label: '实际次数',
                      target: _targetText(station.targetRepetitions, '次'),
                      suffix: '次',
                      allowZero: true,
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _save,
                    child: const Text('保存实际数据'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.pop(
      context,
      StationActualPerformance(
        distanceMeters: hasDistance ? _optionalInt(_distance.text) : null,
        resistanceLevel: hasResistance ? _optionalInt(_resistance.text) : null,
        weightKg: hasWeight ? _optionalDouble(_weight.text) : null,
        repetitions: hasRepetitions ? _optionalInt(_repetitions.text) : null,
      ),
    );
  }
}

class _ActualField extends StatelessWidget {
  const _ActualField({
    required this.controller,
    required this.label,
    required this.target,
    required this.suffix,
    this.decimal = false,
    this.allowZero = false,
  });

  final TextEditingController controller;
  final String label;
  final String target;
  final String suffix;
  final bool decimal;
  final bool allowZero;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        decoration: InputDecoration(
          labelText: label,
          helperText: target,
          suffixText: suffix,
          border: const OutlineInputBorder(),
        ),
        validator: (text) {
          final value = text?.trim() ?? '';
          if (value.isEmpty) return null;
          final number = decimal ? double.tryParse(value) : int.tryParse(value);
          if (number == null || (allowZero ? number < 0 : number <= 0)) {
            return allowZero ? '请输入大于或等于 0 的数值' : '请输入大于 0 的数值';
          }
          return null;
        },
      );
}

String _intText(int? value) => value?.toString() ?? '';

String _doubleText(double? value) {
  if (value == null) return '';
  return value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);
}

String _targetText(num? value, String unit) =>
    value == null ? '计划未设置' : '计划：${_numberText(value)} $unit';

String _numberText(num value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(1);

int? _optionalInt(String value) =>
    value.trim().isEmpty ? null : int.tryParse(value.trim());

double? _optionalDouble(String value) =>
    value.trim().isEmpty ? null : double.tryParse(value.trim());
