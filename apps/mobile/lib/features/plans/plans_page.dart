import 'package:flutter/material.dart';

import 'plan_repository.dart';
import '../academic/recent_inputs.dart';

class PlansPage extends StatefulWidget {
  const PlansPage({required this.repository, super.key});
  final PlanRepository repository;

  @override
  State<PlansPage> createState() => _PlansPageState();
}

class _PlansPageState extends State<PlansPage> {
  late Future<List<Plan>> _plans;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _plans = widget.repository.listPlans();

  Future<void> _add() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _PlanDialog(repository: widget.repository),
    );
    if (created == true && mounted) {
      setState(() {
        _reload();
      });
    }
  }

  Future<void> _edit(Plan plan) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => _PlanDialog(repository: widget.repository, plan: plan),
    );
    if (updated == true && mounted) {
      setState(() {
        _reload();
      });
    }
  }

  Future<void> _delete(Plan plan) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除安排？'),
        content: Text('将删除“${plan.title}”，操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.repository.deletePlan(plan.id);
      if (mounted) {
        setState(() {
          _reload();
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('安排已删除')));
      }
    } on PlanFailure catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _toggle(Plan plan, bool completed) async {
    try {
      await widget.repository.setPlanCompleted(plan.id, completed);
      if (mounted) {
        setState(() {
          _reload();
        });
      }
    } on PlanFailure catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('addPlanButton'),
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('添加安排'),
      ),
      body: FutureBuilder<List<Plan>>(
        future: _plans,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: FilledButton.tonal(
                onPressed: () => setState(() {
                  _reload();
                }),
                child: const Text('加载失败，点击重试'),
              ),
            );
          }
          final plans = snapshot.data!;
          if (plans.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.event_note_outlined, size: 64),
                  SizedBox(height: 16),
                  Text('还没有自定义安排'),
                  SizedBox(height: 8),
                  Text('添加复习、会议或其他个人计划。'),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: plans.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final plan = plans[index];
              final completed = plan.completedAt != null;
              return Card(
                child: CheckboxListTile(
                  value: completed,
                  onChanged: (value) => _toggle(plan, value ?? false),
                  title: Text(
                    plan.title,
                    style: completed
                        ? const TextStyle(
                            decoration: TextDecoration.lineThrough,
                          )
                        : null,
                  ),
                  subtitle: Text(
                    [
                      '${_dateTime(plan.startsAt.toLocal())}–${_time(plan.endsAt.toLocal())}',
                      if (plan.reminderMinutes != null)
                        '提前 ${plan.reminderMinutes} 分钟提醒',
                      if (plan.notes.isNotEmpty) plan.notes,
                    ].join(' · '),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                  secondary: PopupMenuButton<String>(
                    key: ValueKey('planMenu-${plan.id}'),
                    tooltip: '安排操作',
                    onSelected: (value) {
                      if (value == 'edit') _edit(plan);
                      if (value == 'delete') _delete(plan);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('编辑安排')),
                      PopupMenuItem(value: 'delete', child: Text('删除安排')),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _PlanDialog extends StatefulWidget {
  const _PlanDialog({required this.repository, this.plan});
  final PlanRepository repository;
  final Plan? plan;

  @override
  State<_PlanDialog> createState() => _PlanDialogState();
}

class _PlanDialogState extends State<_PlanDialog> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _notes = TextEditingController();
  late DateTime _startsAt;
  late DateTime _endsAt;
  int? _reminderMinutes = 15;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.plan != null;

  @override
  void initState() {
    super.initState();
    final plan = widget.plan;
    if (plan != null) {
      _title.text = plan.title;
      _notes.text = plan.notes;
      _startsAt = plan.startsAt.toLocal();
      _endsAt = plan.endsAt.toLocal();
      _reminderMinutes = plan.reminderMinutes;
      return;
    }
    final now = DateTime.now();
    _startsAt = DateTime(now.year, now.month, now.day, now.hour + 1);
    _endsAt = _startsAt.add(const Duration(hours: 1));
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<DateTime?> _pickDateTime(DateTime initial) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (!_endsAt.isAfter(_startsAt)) {
      setState(() => _error = '结束时间必须晚于开始时间');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_editing) {
        await widget.repository.updatePlan(
          id: widget.plan!.id,
          title: _title.text.trim(),
          notes: _notes.text.trim(),
          startsAt: _startsAt,
          endsAt: _endsAt,
          reminderMinutes: _reminderMinutes,
        );
      } else {
        await widget.repository.createPlan(
          title: _title.text.trim(),
          notes: _notes.text.trim(),
          startsAt: _startsAt,
          endsAt: _endsAt,
          reminderMinutes: _reminderMinutes,
        );
      }
      RecentInputs.remember('plan.title', _title.text);
      RecentInputs.remember('plan.notes', _notes.text);
      if (mounted) Navigator.pop(context, true);
    } on PlanFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_editing ? '编辑安排' : '添加安排'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RecentInputField(
                  fieldKey: const Key('planTitleField'),
                  memoryKey: 'plan.title',
                  controller: _title,
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? '请填写安排标题' : null,
                  decoration: const InputDecoration(labelText: '安排标题'),
                ),
                const SizedBox(height: 12),
                RecentInputField(
                  memoryKey: 'plan.notes',
                  controller: _notes,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: '备注（可选）'),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('开始时间'),
                  subtitle: Text(_dateTime(_startsAt)),
                  onTap: () async {
                    final value = await _pickDateTime(_startsAt);
                    if (value != null) setState(() => _startsAt = value);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('结束时间'),
                  subtitle: Text(_dateTime(_endsAt)),
                  onTap: () async {
                    final value = await _pickDateTime(_endsAt);
                    if (value != null) setState(() => _endsAt = value);
                  },
                ),
                DropdownButtonFormField<int?>(
                  key: const Key('planReminderField'),
                  initialValue: _reminderMinutes,
                  decoration: const InputDecoration(labelText: '提醒时间'),
                  items: const [
                    DropdownMenuItem<int?>(value: null, child: Text('不提醒')),
                    DropdownMenuItem(value: 0, child: Text('开始时提醒')),
                    DropdownMenuItem(value: 5, child: Text('提前 5 分钟')),
                    DropdownMenuItem(value: 15, child: Text('提前 15 分钟')),
                    DropdownMenuItem(value: 30, child: Text('提前 30 分钟')),
                    DropdownMenuItem(value: 60, child: Text('提前 1 小时')),
                    DropdownMenuItem(value: 1440, child: Text('提前 1 天')),
                  ],
                  onChanged: (value) =>
                      setState(() => _reminderMinutes = value),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? '保存中…' : '保存'),
        ),
      ],
    );
  }
}

String _dateTime(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')} '
    '${_time(value)}';
String _time(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
