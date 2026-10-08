import 'package:flutter/material.dart';

import 'social_repository.dart';

class TagSettingsPage extends StatefulWidget {
  const TagSettingsPage({required this.repository, super.key});
  final SocialRepository repository;

  @override
  State<TagSettingsPage> createState() => _TagSettingsPageState();
}

class _TagSettingsPageState extends State<TagSettingsPage> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<SocialTag> _available = [];
  final Map<String, SocialTag> _selected = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        widget.repository.listAvailableTags(),
        widget.repository.listMyTags(),
      ]);
      if (!mounted) return;
      setState(() {
        _available = results[0];
        _selected
          ..clear()
          ..addEntries(results[1].map((tag) => MapEntry(tag.id, tag)));
        _loading = false;
        _error = null;
      });
    } on SocialFailure catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error.message;
        });
      }
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.repository.replaceMyTags(_selected.values.toList());
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('标签设置已保存')));
      }
    } on SocialFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toggle(SocialTag tag, bool selected) {
    setState(() {
      if (selected) {
        _selected[tag.id] = tag;
      } else {
        _selected.remove(tag.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _available.isEmpty) {
      return Center(
        child: FilledButton.tonal(onPressed: _load, child: Text(_error!)),
      );
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              '个人标签',
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text('最多选择 18 个。选中后可控制是否公开、是否参与推荐，并标记核心标签。'),
            const SizedBox(height: 20),
            for (final category in ['interest', 'field', 'goal'])
              _CategorySection(
                title: const {
                  'interest': '兴趣',
                  'field': '领域',
                  'goal': '目标',
                }[category]!,
                tags: _available
                    .where((tag) => tag.category == category)
                    .toList(),
                selected: _selected,
                onToggle: _toggle,
                onChanged: (tag) => setState(() => _selected[tag.id] = tag),
              ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                key: const Key('saveTagsButton'),
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(_saving ? '保存中…' : '保存标签'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategorySection extends StatelessWidget {
  const _CategorySection({
    required this.title,
    required this.tags,
    required this.selected,
    required this.onToggle,
    required this.onChanged,
  });

  final String title;
  final List<SocialTag> tags;
  final Map<String, SocialTag> selected;
  final void Function(SocialTag, bool) onToggle;
  final ValueChanged<SocialTag> onChanged;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 14),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          for (final tag in tags)
            _TagRow(
              tag: selected[tag.id] ?? tag,
              selected: selected.containsKey(tag.id),
              onToggle: (value) => onToggle(tag, value),
              onChanged: onChanged,
            ),
        ],
      ),
    ),
  );
}

class _TagRow extends StatelessWidget {
  const _TagRow({
    required this.tag,
    required this.selected,
    required this.onToggle,
    required this.onChanged,
  });

  final SocialTag tag;
  final bool selected;
  final ValueChanged<bool> onToggle;
  final ValueChanged<SocialTag> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      CheckboxListTile(
        key: Key('tag-${tag.id}'),
        contentPadding: EdgeInsets.zero,
        value: selected,
        title: Text(tag.name),
        onChanged: (value) => onToggle(value ?? false),
      ),
      if (selected)
        Padding(
          padding: const EdgeInsets.only(left: 28, bottom: 8),
          child: Wrap(
            spacing: 8,
            children: [
              FilterChip(
                label: const Text('核心'),
                selected: tag.isCore,
                onSelected: (value) => onChanged(tag.copyWith(isCore: value)),
              ),
              FilterChip(
                label: const Text('公开'),
                selected: tag.visible,
                onSelected: (value) => onChanged(tag.copyWith(visible: value)),
              ),
              FilterChip(
                label: const Text('参与推荐'),
                selected: tag.usedForRecommendation,
                onSelected: (value) =>
                    onChanged(tag.copyWith(usedForRecommendation: value)),
              ),
            ],
          ),
        ),
    ],
  );
}
