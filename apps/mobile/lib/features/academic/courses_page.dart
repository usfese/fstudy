import 'package:flutter/material.dart';

import 'academic_repository.dart';
import 'class_periods.dart';
import 'recent_inputs.dart';

const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

class CoursesPage extends StatefulWidget {
  const CoursesPage({required this.repository, super.key});
  final AcademicRepository repository;

  @override
  State<CoursesPage> createState() => _CoursesPageState();
}

class _CoursesPageState extends State<CoursesPage> {
  late Future<List<Course>> _courses;
  late Future<DateTime?> _semesterStartDate;
  int _selectedWeek = 1;
  bool _weeklyView = true;
  bool _savingSemesterDate = false;

  @override
  void initState() {
    super.initState();
    _reload();
    _semesterStartDate = _loadSemesterStartDate();
  }

  void _reload() => _courses = widget.repository.listCourses();

  Future<DateTime?> _loadSemesterStartDate() async {
    final date = await widget.repository.getSemesterStartDate();
    if (mounted && date != null) {
      _selectedWeek = _teachingWeek(date, DateTime.now()).clamp(1, 30);
    }
    return date;
  }

  Future<void> _add() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _CourseDialog(repository: widget.repository),
    );
    if (created == true && mounted) {
      setState(() {
        _reload();
      });
    }
  }

  Future<void> _edit(Course course) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _CourseDialog(repository: widget.repository, course: course),
    );
    if (updated == true && mounted) {
      setState(() {
        _reload();
      });
    }
  }

  Future<void> _delete(Course course) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除课程？'),
        content: Text('将删除“${course.name}”及其全部上课时间，操作不可恢复。'),
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
      await widget.repository.deleteCourse(course.id);
      if (mounted) {
        setState(() {
          _reload();
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('课程已删除')));
      }
    } on AcademicFailure catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _clear() async {
    final cleared = await showDialog<bool>(
      context: context,
      builder: (_) => _ClearScheduleDialog(repository: widget.repository),
    );
    if (cleared == true && mounted) {
      setState(() {
        _reload();
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('课表已清空')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('addCourseButton'),
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('添加课程'),
      ),
      body: FutureBuilder<List<Course>>(
        future: _courses,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorView(
              message: _message(snapshot.error),
              retry: () => setState(() {
                _reload();
              }),
            );
          }
          final courses = snapshot.data!;
          return Column(
            children: [
              _SemesterSettings(
                repository: widget.repository,
                initialDate: _semesterStartDate,
                saving: _savingSemesterDate,
                onSavingChanged: (value) => setState(() {
                  _savingSemesterDate = value;
                }),
                onSaved: (date) => setState(() {
                  _semesterStartDate = Future.value(date);
                  if (date != null) {
                    _selectedWeek = _teachingWeek(
                      date,
                      DateTime.now(),
                    ).clamp(1, 30);
                  }
                }),
              ),
              if (courses.isEmpty)
                const Expanded(
                  child: _EmptyView(
                    icon: Icons.calendar_month_outlined,
                    title: '还没有课程',
                    detail: '点击右下角添加第一门课程。',
                  ),
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(
                            value: true,
                            icon: Icon(Icons.view_week_outlined),
                            label: Text('周视图'),
                          ),
                          ButtonSegment(
                            value: false,
                            icon: Icon(Icons.view_list_outlined),
                            label: Text('列表'),
                          ),
                        ],
                        selected: {_weeklyView},
                        onSelectionChanged: (value) =>
                            setState(() => _weeklyView = value.first),
                      ),
                      if (_weeklyView)
                        FutureBuilder<DateTime?>(
                          future: _semesterStartDate,
                          builder: (context, dateSnapshot) {
                            final startDate = dateSnapshot.data;
                            final currentWeek = startDate == null
                                ? 1
                                : _teachingWeek(startDate, DateTime.now());
                            final selectedWeek = _selectedWeek.clamp(1, 30);
                            return DropdownButton<int>(
                              key: const Key('scheduleWeekSelector'),
                              value: selectedWeek,
                              items: List.generate(
                                30,
                                (index) => DropdownMenuItem(
                                  value: index + 1,
                                  child: Text(
                                    '第 ${index + 1} 周${index + 1 == currentWeek ? ' · 本周' : ''}',
                                  ),
                                ),
                              ),
                              onChanged: (value) =>
                                  setState(() => _selectedWeek = value!),
                            );
                          },
                        ),
                      PopupMenuButton<String>(
                        key: const Key('scheduleMoreMenu'),
                        tooltip: '更多课表操作',
                        icon: const Icon(Icons.more_horiz),
                        onSelected: (value) {
                          if (value == 'clear') _clear();
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'clear', child: Text('清空全部课程')),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _weeklyView
                      ? _WeeklySchedule(
                          courses: courses,
                          week: _selectedWeek,
                          onEdit: _edit,
                          onDelete: _delete,
                        )
                      : _CourseList(
                          courses: courses,
                          onEdit: _edit,
                          onDelete: _delete,
                        ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

int _teachingWeek(DateTime semesterStartDate, DateTime date) {
  final start = DateTime.utc(
    semesterStartDate.year,
    semesterStartDate.month,
    semesterStartDate.day,
  );
  final today = DateTime.utc(date.year, date.month, date.day);
  final elapsedDays = today.difference(start).inDays;
  if (elapsedDays < 0) return 1;
  return (elapsedDays ~/ 7) + 1;
}

class _SemesterSettings extends StatefulWidget {
  const _SemesterSettings({
    required this.repository,
    required this.initialDate,
    required this.saving,
    required this.onSavingChanged,
    required this.onSaved,
  });

  final AcademicRepository repository;
  final Future<DateTime?> initialDate;
  final bool saving;
  final ValueChanged<bool> onSavingChanged;
  final ValueChanged<DateTime?> onSaved;

  @override
  State<_SemesterSettings> createState() => _SemesterSettingsState();
}

class _SemesterSettingsState extends State<_SemesterSettings> {
  late Future<DateTime?> _date;

  @override
  void initState() {
    super.initState();
    _date = widget.initialDate;
  }

  Future<void> _pick(DateTime? current) async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate:
          current ??
          DateTime(today.year, today.month, today.day - (today.weekday - 1)),
      firstDate: DateTime(today.year - 2),
      lastDate: DateTime(today.year + 2),
      helpText: '选择学期第一周的星期一',
      selectableDayPredicate: (date) => date.weekday == DateTime.monday,
    );
    if (picked == null) return;
    if (mounted) widget.onSavingChanged(true);
    try {
      await widget.repository.setSemesterStartDate(picked);
      if (!mounted) return;
      setState(() {
        _date = Future.value(picked);
      });
      widget.onSaved(picked);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('学期起始日期已保存')));
    } on AcademicFailure catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) widget.onSavingChanged(false);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<DateTime?>(
    future: _date,
    builder: (context, snapshot) {
      final date = snapshot.data;
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Card(
          child: ListTile(
            key: const Key('semesterStartDateSetting'),
            leading: const Icon(Icons.date_range_outlined),
            title: const Text('学期第一周起始日期'),
            subtitle: Text(
              date == null
                  ? '尚未设置；设置后可计算本周教学周次'
                  : '${date.year}年${date.month}月${date.day}日（星期一）',
            ),
            trailing: widget.saving
                ? const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : TextButton(
                    key: const Key('setSemesterStartDateButton'),
                    onPressed: () => _pick(date),
                    child: Text(date == null ? '设置' : '修改'),
                  ),
          ),
        ),
      );
    },
  );
}

class _CourseList extends StatelessWidget {
  const _CourseList({
    required this.courses,
    required this.onEdit,
    required this.onDelete,
  });

  final List<Course> courses;
  final ValueChanged<Course> onEdit;
  final ValueChanged<Course> onDelete;

  @override
  Widget build(BuildContext context) {
    final sorted = [...courses]..sort(_compareCourses);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: sorted.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final course = sorted[index];
        final meeting = course.meetings.isEmpty ? null : course.meetings.first;
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              child: Text(
                meeting == null ? '课' : '周${_weekdays[meeting.weekday - 1]}',
              ),
            ),
            title: Text(course.name),
            isThreeLine: course.meetings.length > 1,
            subtitle: Text(
              course.meetings.isEmpty
                  ? '未设置上课时间'
                  : course.meetings.map(_meetingText).join('\n'),
            ),
            trailing: _CourseMenu(
              course: course,
              onEdit: onEdit,
              onDelete: onDelete,
            ),
          ),
        );
      },
    );
  }
}

class _WeeklySchedule extends StatelessWidget {
  const _WeeklySchedule({
    required this.courses,
    required this.week,
    required this.onEdit,
    required this.onDelete,
  });

  final List<Course> courses;
  final int week;
  final ValueChanged<Course> onEdit;
  final ValueChanged<Course> onDelete;

  @override
  Widget build(BuildContext context) {
    final active = <({Course course, CourseMeeting meeting})>[];
    for (final course in courses) {
      for (final meeting in course.meetings) {
        if (_occursInWeek(meeting, week)) {
          active.add((course: course, meeting: meeting));
        }
      }
    }
    active.sort((a, b) {
      final weekday = a.meeting.weekday.compareTo(b.meeting.weekday);
      if (weekday != 0) return weekday;
      final start = a.meeting.startMinute.compareTo(b.meeting.startMinute);
      if (start != 0) return start;
      return a.course.name.compareTo(b.course.name);
    });
    if (active.isEmpty) {
      return Center(child: Text('第 $week 周没有课程'));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth < 840 ? 840.0 : constraints.maxWidth;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: List.generate(7, (dayIndex) {
                final meetings = active
                    .where((item) => item.meeting.weekday == dayIndex + 1)
                    .toList();
                return Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        right: BorderSide(
                          color: Theme.of(context).dividerColor,
                        ),
                      ),
                    ),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(10),
                          child: Text(
                            '星期${_weekdays[dayIndex]}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(6, 0, 6, 96),
                            children: meetings
                                .map(
                                  (item) => Card(
                                    key: ValueKey(
                                      'weekCourseCard-${item.course.id}-${item.meeting.weekday}-${item.meeting.startMinute}',
                                    ),
                                    color: _color(item.course.color, context),
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        10,
                                        6,
                                        4,
                                        10,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  item.course.name,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                              _CourseMenu(
                                                course: item.course,
                                                onEdit: onEdit,
                                                onDelete: onDelete,
                                                compact: true,
                                                menuKey: ValueKey(
                                                  'weekCourseMenu-${item.course.id}-${item.meeting.weekday}-${item.meeting.startMinute}',
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${formatMinute(item.meeting.startMinute)}–${formatMinute(item.meeting.endMinute)}',
                                          ),
                                          if (item.meeting.room?.isNotEmpty ==
                                              true)
                                            Text(item.meeting.room!),
                                        ],
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        );
      },
    );
  }
}

class _CourseMenu extends StatelessWidget {
  const _CourseMenu({
    required this.course,
    required this.onEdit,
    required this.onDelete,
    this.compact = false,
    this.menuKey,
  });

  final Course course;
  final ValueChanged<Course> onEdit;
  final ValueChanged<Course> onDelete;
  final bool compact;
  final Key? menuKey;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    key: menuKey ?? ValueKey('courseMenu-${course.id}'),
    tooltip: '课程操作',
    padding: compact ? EdgeInsets.zero : const EdgeInsets.all(8),
    iconSize: compact ? 18 : 24,
    onSelected: (value) {
      if (value == 'edit') onEdit(course);
      if (value == 'delete') onDelete(course);
    },
    itemBuilder: (_) => const [
      PopupMenuItem(value: 'edit', child: Text('编辑课程')),
      PopupMenuItem(value: 'delete', child: Text('删除课程')),
    ],
  );
}

bool _occursInWeek(CourseMeeting meeting, int week) {
  if (week < meeting.startWeek || week > meeting.endWeek) return false;
  if (meeting.weekParity == 'odd') return week.isOdd;
  if (meeting.weekParity == 'even') return week.isEven;
  return true;
}

int _compareCourses(Course a, Course b) {
  final aMeeting = a.meetings.isEmpty ? null : a.meetings.first;
  final bMeeting = b.meetings.isEmpty ? null : b.meetings.first;
  if (aMeeting == null && bMeeting == null) return a.name.compareTo(b.name);
  if (aMeeting == null) return 1;
  if (bMeeting == null) return -1;
  final weekday = aMeeting.weekday.compareTo(bMeeting.weekday);
  if (weekday != 0) return weekday;
  final start = aMeeting.startMinute.compareTo(bMeeting.startMinute);
  if (start != 0) return start;
  return a.name.compareTo(b.name);
}

String _meetingText(CourseMeeting meeting) => [
  '周${_weekdays[meeting.weekday - 1]}',
  '${formatMinute(meeting.startMinute)}–${formatMinute(meeting.endMinute)}',
  if (meeting.room?.isNotEmpty == true) meeting.room!,
  '第 ${meeting.startWeek}–${meeting.endWeek} 周',
  if (meeting.weekParity != 'all') meeting.weekParity == 'odd' ? '单周' : '双周',
].join(' · ');

Color _color(String value, BuildContext context) {
  final parsed = int.tryParse(value.replaceFirst('#', ''), radix: 16);
  if (parsed == null) return Theme.of(context).colorScheme.primaryContainer;
  return Color(0xFF000000 | parsed).withAlpha(45);
}

class _CourseDialog extends StatefulWidget {
  const _CourseDialog({required this.repository, this.course});

  final AcademicRepository repository;
  final Course? course;

  @override
  State<_CourseDialog> createState() => _CourseDialogState();
}

class _CourseDialogState extends State<_CourseDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _teacher = TextEditingController();
  late final List<_MeetingDraft> _meetings;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.course != null;

  @override
  void initState() {
    super.initState();
    final course = widget.course;
    _name.text = course?.name ?? '';
    _teacher.text = course?.teacher ?? '';
    final existing = course?.meetings ?? const <CourseMeeting>[];
    _meetings = existing.isEmpty
        ? [_MeetingDraft.blank()]
        : existing.map(_MeetingDraft.fromMeeting).toList();
  }

  @override
  void dispose() {
    _name.dispose();
    _teacher.dispose();
    for (final meeting in _meetings) {
      meeting.dispose();
    }
    super.dispose();
  }

  void _addMeeting() {
    setState(() => _meetings.add(_MeetingDraft.blank()));
  }

  void _removeMeeting(int index) {
    if (_meetings.length == 1) return;
    final removed = _meetings.removeAt(index);
    removed.dispose();
    setState(() {});
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final meetings = <CourseMeeting>[];
    for (final draft in _meetings) {
      if (draft.periods.isEmpty) {
        setState(() => _error = '请为每个上课时间选择至少一节');
        return;
      }
      final startWeek = int.parse(draft.startWeek.text);
      final endWeek = int.parse(draft.endWeek.text);
      if (endWeek < startWeek) {
        setState(() => _error = '结束周不能早于起始周');
        return;
      }
      for (final block in periodBlocks(draft.periods)) {
        meetings.add(
          CourseMeeting(
            weekday: draft.weekday,
            startMinute: block.startMinute,
            endMinute: block.endMinute,
            startWeek: startWeek,
            endWeek: endWeek,
            weekParity: draft.weekParity,
            room: _nullable(draft.room.text),
          ),
        );
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_editing) {
        await widget.repository.updateCourse(
          id: widget.course!.id,
          name: _name.text.trim(),
          teacher: _nullable(_teacher.text),
          color: widget.course!.color,
          meetings: meetings,
        );
      } else {
        await widget.repository.createCourse(
          name: _name.text.trim(),
          teacher: _nullable(_teacher.text),
          meetings: meetings,
        );
      }
      RecentInputs.remember('course.name', _name.text);
      RecentInputs.remember('course.teacher', _teacher.text);
      for (final meeting in _meetings) {
        RecentInputs.remember('course.room', meeting.room.text);
      }
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
      title: Text(_editing ? '编辑课程' : '添加课程'),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RecentInputField(
                  fieldKey: const Key('courseNameField'),
                  memoryKey: 'course.name',
                  controller: _name,
                  validator: _required,
                  decoration: const InputDecoration(labelText: '课程名称'),
                ),
                const SizedBox(height: 12),
                RecentInputField(
                  memoryKey: 'course.teacher',
                  controller: _teacher,
                  decoration: const InputDecoration(labelText: '教师（可选）'),
                ),
                for (var index = 0; index < _meetings.length; index++)
                  _MeetingEditor(
                    index: index,
                    draft: _meetings[index],
                    canRemove: _meetings.length > 1,
                    onChanged: () => setState(() {}),
                    onRemove: () => _removeMeeting(index),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const Key('addCourseMeetingButton'),
                    onPressed: _saving ? null : _addMeeting,
                    icon: const Icon(Icons.add),
                    label: const Text('添加上课时间'),
                  ),
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

class _MeetingEditor extends StatelessWidget {
  const _MeetingEditor({
    required this.index,
    required this.draft,
    required this.canRemove,
    required this.onChanged,
    required this.onRemove,
  });

  final int index;
  final _MeetingDraft draft;
  final bool canRemove;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(top: 14),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '上课时间 ${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                if (canRemove)
                  IconButton(
                    key: Key('removeCourseMeetingButton-$index'),
                    tooltip: '删除这个上课时间',
                    onPressed: onRemove,
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            DropdownButtonFormField<int>(
              key: Key('courseWeekdayField-$index'),
              initialValue: draft.weekday,
              decoration: const InputDecoration(labelText: '星期'),
              items: List.generate(
                7,
                (day) => DropdownMenuItem(
                  value: day + 1,
                  child: Text('星期${_weekdays[day]}'),
                ),
              ),
              onChanged: (value) {
                if (value == null) return;
                draft.weekday = value;
                onChanged();
              },
            ),
            const SizedBox(height: 12),
            Text(
              '节次（可多选，连续节次会合并）',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: List.generate(classPeriods.length, (periodIndex) {
                final period = classPeriods[periodIndex];
                return FilterChip(
                  key: Key('coursePeriodChip-$index-$periodIndex'),
                  label: Text(
                    period.label,
                    style: const TextStyle(fontSize: 12),
                  ),
                  selected: draft.periods.contains(periodIndex),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onSelected: (selected) {
                    if (selected) {
                      draft.periods.add(periodIndex);
                    } else {
                      draft.periods.remove(periodIndex);
                    }
                    onChanged();
                  },
                );
              }),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    key: Key('courseStartWeekField-$index'),
                    controller: draft.startWeek,
                    keyboardType: TextInputType.number,
                    validator: _week,
                    decoration: const InputDecoration(labelText: '起始周'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    key: Key('courseEndWeekField-$index'),
                    controller: draft.endWeek,
                    keyboardType: TextInputType.number,
                    validator: _week,
                    decoration: const InputDecoration(labelText: '结束周'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: Key('courseWeekParityField-$index'),
              initialValue: draft.weekParity,
              decoration: const InputDecoration(labelText: '上课周次'),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('每周')),
                DropdownMenuItem(value: 'odd', child: Text('仅单周')),
                DropdownMenuItem(value: 'even', child: Text('仅双周')),
              ],
              onChanged: (value) {
                if (value == null) return;
                draft.weekParity = value;
                onChanged();
              },
            ),
            const SizedBox(height: 12),
            RecentInputField(
              fieldKey: Key('courseRoomField-$index'),
              memoryKey: 'course.room',
              controller: draft.room,
              decoration: const InputDecoration(labelText: '教室（可选）'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MeetingDraft {
  _MeetingDraft({
    required this.weekday,
    required this.periods,
    required this.startWeek,
    required this.endWeek,
    required this.weekParity,
    required this.room,
  });

  factory _MeetingDraft.blank() => _MeetingDraft(
    weekday: 1,
    periods: {0},
    startWeek: TextEditingController(text: '1'),
    endWeek: TextEditingController(text: '16'),
    weekParity: 'all',
    room: TextEditingController(),
  );

  factory _MeetingDraft.fromMeeting(CourseMeeting meeting) => _MeetingDraft(
    weekday: meeting.weekday,
    periods: periodIndexesForMeeting(meeting.startMinute, meeting.endMinute),
    startWeek: TextEditingController(text: '${meeting.startWeek}'),
    endWeek: TextEditingController(text: '${meeting.endWeek}'),
    weekParity: meeting.weekParity,
    room: TextEditingController(text: meeting.room ?? ''),
  );

  int weekday;
  final Set<int> periods;
  final TextEditingController startWeek;
  final TextEditingController endWeek;
  String weekParity;
  final TextEditingController room;

  void dispose() {
    startWeek.dispose();
    endWeek.dispose();
    room.dispose();
  }
}

class _ClearScheduleDialog extends StatefulWidget {
  const _ClearScheduleDialog({required this.repository});

  final AcademicRepository repository;

  @override
  State<_ClearScheduleDialog> createState() => _ClearScheduleDialogState();
}

class _ClearScheduleDialogState extends State<_ClearScheduleDialog> {
  final _confirm = TextEditingController();
  bool _saving = false;
  String? _error;

  bool get _canClear => _confirm.text.trim() == '清空';

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _clear() async {
    if (!_canClear) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.clearCourses();
      if (mounted) Navigator.pop(context, true);
    } on AcademicFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('清空全部课程？'),
    content: SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('这会删除你的全部课程和上课时间，且无法恢复。作业不会被删除。'),
          const SizedBox(height: 16),
          const Text('请输入“清空”以确认：'),
          const SizedBox(height: 8),
          TextField(
            key: const Key('clearScheduleConfirmField'),
            controller: _confirm,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(hintText: '清空'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context, false),
        child: const Text('取消'),
      ),
      FilledButton(
        key: const Key('clearScheduleConfirmButton'),
        style: FilledButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.error,
          foregroundColor: Theme.of(context).colorScheme.onError,
        ),
        onPressed: _canClear && !_saving ? _clear : null,
        child: Text(_saving ? '清空中…' : '永久清空'),
      ),
    ],
  );
}

String? _required(String? value) =>
    value == null || value.trim().isEmpty ? '请填写此项' : null;
String? _week(String? value) {
  final week = int.tryParse(value ?? '');
  return week == null || week < 1 || week > 30 ? '请输入 1–30' : null;
}

String? _nullable(String value) => value.trim().isEmpty ? null : value.trim();
String _message(Object? error) =>
    error is AcademicFailure ? error.message : '加载失败';

class _EmptyView extends StatelessWidget {
  const _EmptyView({
    required this.icon,
    required this.title,
    required this.detail,
  });
  final IconData icon;
  final String title;
  final String detail;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 64, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 16),
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(detail),
      ],
    ),
  );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.retry});
  final String message;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message),
        const SizedBox(height: 12),
        FilledButton.tonal(onPressed: retry, child: const Text('重试')),
      ],
    ),
  );
}
