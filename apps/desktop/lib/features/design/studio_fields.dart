import 'package:flutter/material.dart';
import 'studio_view_model.dart';

class StudioNumberField extends StatelessWidget {
  const StudioNumberField({
    required this.model,
    required this.group,
    required this.field,
    required this.label,
    required this.min,
    required this.max,
    this.decimals = 0,
    super.key,
  });
  final StudioViewModel model;
  final String group, field, label;
  final double min, max;
  final int decimals;
  @override
  Widget build(BuildContext context) {
    final value = model.document.number(group, field);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text('$label · ${value.toStringAsFixed(decimals)}'),
        Slider(
          key: ValueKey('design-$field'),
          value: value,
          min: min,
          max: max,
          divisions: ((max - min) * (decimals == 0 ? 1 : 100)).round(),
          onChanged: (value) => model.change(group, field, value),
        ),
      ],
    );
  }
}

class StudioColorField extends StatefulWidget {
  const StudioColorField({
    required this.name,
    required this.value,
    required this.onChanged,
    super.key,
  });
  final String name, value;
  final ValueChanged<String> onChanged;
  @override
  State<StudioColorField> createState() => StudioColorFieldState();
}

class StudioColorFieldState extends State<StudioColorField> {
  late final controller = TextEditingController(text: widget.value);
  @override
  void didUpdateWidget(StudioColorField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && controller.text != widget.value) {
      controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: widget.name,
        prefixIcon: Icon(
          Icons.circle,
          color: Color(int.parse('ff${widget.value.substring(1)}', radix: 16)),
        ),
      ),
      onChanged: (text) {
        if (RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(text)) widget.onChanged(text);
      },
    ),
  );
}
