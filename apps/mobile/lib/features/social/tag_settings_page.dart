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
  String _query = '';
  List<SocialTag> _available = [];
  final Map<String, SocialTag> _selected = {};
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
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
    if (selected && _selected.length >= 18 && !_selected.containsKey(tag.id)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('最多选择 18 个标签')));
      return;
    }
    setState(() {
      if (selected) {
        _selected[tag.id] = tag;
      } else {
        _selected.remove(tag.id);
      }
    });
  }

  List<SocialTag> get _filteredTags {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _available;
    return _available
        .where((tag) => tag.name.toLowerCase().contains(query))
        .toList();
  }

  Future<void> _openCreateTagDialog() async {
    final input = await showDialog<({String name, String category})>(
      context: context,
      builder: (context) => _CreateTagDialog(initialName: _query.trim()),
    );
    if (input == null || !mounted) return;
    await _createTag(input.name, input.category);
  }

  Future<void> _createTag(String name, String category) async {
    setState(() => _saving = true);
    try {
      final tag = await widget.repository.createTag(
        name: name,
        category: category,
      );
      if (!mounted) return;
      final wasSelected = _selected.containsKey(tag.id);
      setState(() {
        if (!_available.any((item) => item.id == tag.id)) {
          _available = [..._available, tag];
        }
        if (!wasSelected && _selected.length < 18) {
          _selected[tag.id] = tag;
        }
        _query = '';
        _search.clear();
        _error = null;
      });
      if (mounted) {
        final selected = _selected.containsKey(tag.id);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(selected ? '标签已创建并选中' : '标签已创建，已达 18 个上限，未自动选中'),
          ),
        );
      }
    } on SocialFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _available.isEmpty) {
      return Center(
        child: FilledButton.tonal(onPressed: _load, child: Text(_error!)),
      );
    }
    final filtered = _filteredTags;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: ListView(
          key: const Key('tagSettingsList'),
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              '个人标签',
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text('最多选择 18 个。标签全局共享，你可以创建并搜索新标签。'),
            const SizedBox(height: 16),
            TextField(
              key: const Key('tagSearchField'),
              controller: _search,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: '搜索标签',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        key: const Key('clearTagSearchButton'),
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.close),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('已选 ${_selected.length}/18 个'),
                const Spacer(),
                OutlinedButton.icon(
                  key: const Key('createTagButton'),
                  onPressed: _saving ? null : _openCreateTagDialog,
                  icon: const Icon(Icons.add),
                  label: const Text('创建标签'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (filtered.isEmpty)
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const Text('没有找到匹配的标签'),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: _saving ? null : _openCreateTagDialog,
                        icon: const Icon(Icons.add),
                        label: Text('创建「${_query.trim()}」'),
                      ),
                    ],
                  ),
                ),
              )
            else
              for (final category in const ['interest', 'field', 'goal'])
                if (filtered.any((tag) => tag.category == category))
                  _CategorySection(
                    title: const {
                      'interest': '兴趣',
                      'field': '领域',
                      'goal': '目标',
                    }[category]!,
                    tags: filtered
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

class _CreateTagDialog extends StatefulWidget {
  const _CreateTagDialog({required this.initialName});

  final String initialName;

  @override
  State<_CreateTagDialog> createState() => _CreateTagDialogState();
}

class _CreateTagDialogState extends State<_CreateTagDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );
  String _category = 'interest';

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty) return;
    Navigator.pop(context, (name: name, category: _category));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('创建标签'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('newTagNameField'),
            controller: _name,
            autofocus: true,
            maxLength: 40,
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              labelText: '标签名称',
              hintText: '例如：校园摄影',
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: const Key('newTagCategoryField'),
            initialValue: _category,
            decoration: const InputDecoration(labelText: '分类'),
            items: const [
              DropdownMenuItem(value: 'interest', child: Text('兴趣')),
              DropdownMenuItem(value: 'field', child: Text('领域')),
              DropdownMenuItem(value: 'goal', child: Text('目标')),
            ],
            onChanged: (value) =>
                setState(() => _category = value ?? 'interest'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        key: const Key('confirmCreateTagButton'),
        onPressed: _submit,
        child: const Text('创建'),
      ),
    ],
  );
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
