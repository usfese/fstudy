import 'package:flutter/material.dart';

import 'academic_repository.dart';
import 'recent_inputs.dart';

class AssignmentsPage extends StatefulWidget {
  const AssignmentsPage({required this.repository, super.key});
  final AcademicRepository repository;

  @override
  State<AssignmentsPage> createState() => _AssignmentsPageState();
}

class _AssignmentsPageState extends State<AssignmentsPage> {
  late Future<({List<Assignment> assignments, List<Course> courses})> _data;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _data =
        Future.wait([
          widget.repository.listAssignments(),
          widget.repository.listCourses(),
        ]).then(
          (values) => (
            assignments: values[0] as List<Assignment>,
            courses: values[1] as List<Course>,
          ),
        );
  }

  Future<void> _add() async {
    final data = await _data;
    if (!mounted) return;
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _AssignmentDialog(
        repository: widget.repository,
        courses: data.courses,
      ),
    );
    if (created == true && mounted) {
      setState(() {
        _reload();
      });
    }
  }

  Future<void> _edit(Assignment assignment) async {
    final data = await _data;
    if (!mounted) return;
    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => _AssignmentDialog(
        repository: widget.repository,
        courses: data.courses,
        assignment: assignment,
      ),
    );
    if (updated == true && mounted) {
      setState(() {
        _reload();
      });
    }
  }

  Future<void> _delete(Assignment assignment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除作业？'),
        content: Text('将删除“${assignment.title}”，操作不可恢复。'),
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
      await widget.repository.deleteAssignment(assignment.id);
      if (mounted) {
        setState(() {
          _reload();
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('作业已删除')));
      }
    } on AcademicFailure catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _toggle(Assignment assignment, bool completed) async {
    try {
      await widget.repository.setAssignmentCompleted(assignment.id, completed);
      if (mounted) {
        setState(() {
          _reload();
        });
      }
    } on AcademicFailure catch (error) {
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
        key: const Key('addAssignmentButton'),
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('添加作业'),
      ),
      body:
          FutureBuilder<({List<Assignment> assignments, List<Course> courses})>(
            future: _data,
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
              final data = snapshot.data!;
              final assignments = data.assignments;
              final courseNames = {
                for (final course in data.courses) course.id: course.name,
              };
              if (assignments.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.task_alt_outlined, size: 64),
                      SizedBox(height: 16),
                      Text('还没有待交作业'),
                      SizedBox(height: 8),
                      Text('点击右下角添加第一项作业。'),
                    ],
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                itemCount: assignments.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final assignment = assignments[index];
                  final completed = assignment.completedAt != null;
                  return Card(
                    child: CheckboxListTile(
                      value: completed,
                      onChanged: (value) => _toggle(assignment, value ?? false),
                      title: Text(
                        assignment.title,
                        style: completed
                            ? const TextStyle(
                                decoration: TextDecoration.lineThrough,
                              )
                            : null,
                      ),
                      subtitle: Text(
                        [
                          if (assignment.dueAt != null)
                            '截止 ${_dateTime(assignment.dueAt!.toLocal())}',
                          if (assignment.courseId != null &&
                              courseNames[assignment.courseId] != null)
                            courseNames[assignment.courseId]!,
                          if (assignment.notes.isNotEmpty) assignment.notes,
                        ].join(' · '),
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                      secondary: PopupMenuButton<String>(
                        key: ValueKey('assignmentMenu-${assignment.id}'),
                        tooltip: '作业操作',
                        onSelected: (value) {
                          if (value == 'edit') _edit(assignment);
                          if (value == 'delete') _delete(assignment);
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('编辑作业')),
                          PopupMenuItem(value: 'delete', child: Text('删除作业')),
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

class _AssignmentDialog extends StatefulWidget {
  const _AssignmentDialog({
    required this.repository,
    required this.courses,
    this.assignment,
  });
  final AcademicRepository repository;
  final List<Course> courses;
  final Assignment? assignment;

  @override
  State<_AssignmentDialog> createState() => _AssignmentDialogState();
}

class _AssignmentDialogState extends State<_AssignmentDialog> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _notes = TextEditingController();
  DateTime? _dueAt;
  String? _courseId;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.assignment != null;

  @override
  void initState() {
    super.initState();
    final assignment = widget.assignment;
    _title.text = assignment?.title ?? '';
    _notes.text = assignment?.notes ?? '';
    _dueAt = assignment?.dueAt?.toLocal();
    _courseId = assignment?.courseId;
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDueAt() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _dueAt ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: _dueAt == null
          ? const TimeOfDay(hour: 23, minute: 59)
          : TimeOfDay.fromDateTime(_dueAt!),
    );
    if (time != null) {
      setState(() {
        _dueAt = DateTime(
          date.year,
          date.month,
          date.day,
          time.hour,
          time.minute,
        );
      });
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_editing) {
        await widget.repository.updateAssignment(
          id: widget.assignment!.id,
          title: _title.text.trim(),
          notes: _notes.text.trim(),
          courseId: _courseId,
          dueAt: _dueAt,
        );
      } else {
        await widget.repository.createAssignment(
          title: _title.text.trim(),
          notes: _notes.text.trim(),
          courseId: _courseId,
          dueAt: _dueAt,
        );
      }
      RecentInputs.remember('assignment.title', _title.text);
      RecentInputs.remember('assignment.notes', _notes.text);
      if (mounted) Navigator.pop(context, true);
    } on AcademicFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_editing ? '编辑作业' : '添加作业'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RecentInputField(
                  fieldKey: const Key('assignmentTitleField'),
                  memoryKey: 'assignment.title',
                  controller: _title,
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? '请填写作业标题' : null,
                  decoration: const InputDecoration(labelText: '作业标题'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  key: const Key('assignmentCourseField'),
                  initialValue: _courseId,
                  decoration: const InputDecoration(labelText: '关联课程（可选）'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('不关联课程'),
                    ),
                    ...widget.courses.map(
                      (course) => DropdownMenuItem<String?>(
                        value: course.id,
                        child: Text(course.name),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(() => _courseId = value),
                ),
                const SizedBox(height: 12),
                RecentInputField(
                  memoryKey: 'assignment.notes',
                  controller: _notes,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: '备注（可选）'),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_outlined),
                  title: Text(
                    _dueAt == null ? '设置截止时间（可选）' : _dateTime(_dueAt!),
                  ),
                  onTap: _pickDueAt,
                  trailing: _dueAt == null
                      ? null
                      : IconButton(
                          tooltip: '清除截止时间',
                          onPressed: () => setState(() => _dueAt = null),
                          icon: const Icon(Icons.close),
                        ),
                ),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
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
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
