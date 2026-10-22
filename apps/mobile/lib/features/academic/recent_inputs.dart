import 'package:flutter/material.dart';

/// Small, session-scoped memory for text fields.
///
/// Values are intentionally not persisted: they are a typing convenience, not
/// account data, and are cleared when the app restarts so one person's recent
/// course or assignment names do not leak into another account on the device.
class RecentInputs {
  RecentInputs._();

  static final Map<String, List<String>> _values = {};
  static const _limit = 8;

  static List<String> suggestions(String key) =>
      List.unmodifiable(_values[key] ?? const <String>[]);

  static void remember(String key, String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    final values = _values[key] ?? <String>[];
    values.removeWhere((item) => item == trimmed);
    values.insert(0, trimmed);
    if (values.length > _limit) values.removeRange(_limit, values.length);
    _values[key] = values;
  }

  static void clear() => _values.clear();
}

/// A text field with recent-value suggestions for the same kind of input.
class RecentInputField extends StatefulWidget {
  const RecentInputField({
    required this.memoryKey,
    required this.controller,
    required this.decoration,
    this.fieldKey,
    this.validator,
    this.maxLines = 1,
    this.maxLength,
    this.keyboardType,
    super.key,
  });

  final String memoryKey;
  final TextEditingController controller;
  final InputDecoration decoration;
  final Key? fieldKey;
  final FormFieldValidator<String>? validator;
  final int maxLines;
  final int? maxLength;
  final TextInputType? keyboardType;

  @override
  State<RecentInputField> createState() => _RecentInputFieldState();
}

class _RecentInputFieldState extends State<RecentInputField> {
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focusNode,
      optionsBuilder: (value) {
        final options = RecentInputs.suggestions(widget.memoryKey);
        if (options.isEmpty) return const Iterable<String>.empty();
        final query = value.text.trim().toLowerCase();
        if (query.isEmpty) return options;
        return options.where((option) => option.toLowerCase().contains(query));
      },
      onSelected: (value) {
        widget.controller.value = TextEditingValue(
          text: value,
          selection: TextSelection.collapsed(offset: value.length),
        );
      },
      fieldViewBuilder: (context, textController, focusNode, onSubmitted) =>
          TextFormField(
            key: widget.fieldKey,
            controller: textController,
            focusNode: focusNode,
            validator: widget.validator,
            maxLines: widget.maxLines,
            maxLength: widget.maxLength,
            keyboardType: widget.keyboardType,
            decoration: widget.decoration,
          ),
      optionsViewBuilder: (context, onSelected, options) {
        final values = options.toList(growable: false);
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420, maxHeight: 220),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: values.length,
                itemBuilder: (context, index) => ListTile(
                  dense: true,
                  leading: const Icon(Icons.history, size: 18),
                  title: Text(values[index]),
                  onTap: () => onSelected(values[index]),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
