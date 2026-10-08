import 'package:flutter/material.dart';

import 'academic_repository.dart';

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
      setState(
        () => _selectedWeek = _teachingWeek(date, DateTime.now()).clamp(1, 30),
      );
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
                    ],
                  ),
                ),
                Expanded(
                  child: _weeklyView
                      ? _WeeklySchedule(courses: courses, week: _selectedWeek)
                      : _CourseList(courses: courses),
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
  const _CourseList({required this.courses});
  final List<Course> courses;

  @override
  Widget build(BuildContext context) => ListView.separated(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
    itemCount: courses.length,
    separatorBuilder: (_, _) => const SizedBox(height: 10),
    itemBuilder: (context, index) {
      final course = courses[index];
      final meeting = course.meetings.first;
      return Card(
        child: ListTile(
          leading: CircleAvatar(
            child: Text('周${_weekdays[meeting.weekday - 1]}'),
          ),
          title: Text(course.name),
          subtitle: Text(
            [
              '${_time(meeting.startMinute)}–${_time(meeting.endMinute)}',
              if (course.teacher?.isNotEmpty == true) course.teacher!,
              if (meeting.room?.isNotEmpty == true) meeting.room!,
              '第 ${meeting.startWeek}–${meeting.endWeek} 周',
              if (meeting.weekParity != 'all')
                meeting.weekParity == 'odd' ? '单周' : '双周',
            ].join(' · '),
          ),
        ),
      );
    },
  );
}

class _WeeklySchedule extends StatelessWidget {
  const _WeeklySchedule({required this.courses, required this.week});
  final List<Course> courses;
  final int week;

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
                final meetings =
                    active
                        .where((item) => item.meeting.weekday == dayIndex + 1)
                        .toList()
                      ..sort(
                        (a, b) => a.meeting.startMinute.compareTo(
                          b.meeting.startMinute,
                        ),
                      );
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
                                    color: _color(item.course.color, context),
                                    child: Padding(
                                      padding: const EdgeInsets.all(10),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.course.name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${_time(item.meeting.startMinute)}–${_time(item.meeting.endMinute)}',
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

bool _occursInWeek(CourseMeeting meeting, int week) {
  if (week < meeting.startWeek || week > meeting.endWeek) return false;
  if (meeting.weekParity == 'odd') return week.isOdd;
  if (meeting.weekParity == 'even') return week.isEven;
  return true;
}

Color _color(String value, BuildContext context) {
  final parsed = int.tryParse(value.replaceFirst('#', ''), radix: 16);
  if (parsed == null) return Theme.of(context).colorScheme.primaryContainer;
  return Color(0xFF000000 | parsed).withAlpha(45);
}

class _CourseDialog extends StatefulWidget {
  const _CourseDialog({required this.repository});
  final AcademicRepository repository;

  @override
  State<_CourseDialog> createState() => _CourseDialogState();
}

class _CourseDialogState extends State<_CourseDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _teacher = TextEditingController();
  final _room = TextEditingController();
  final _startWeek = TextEditingController(text: '1');
  final _endWeek = TextEditingController(text: '16');
  int _weekday = 1;
  TimeOfDay _start = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 9, minute: 35);
  String _weekParity = 'all';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _teacher.dispose();
    _room.dispose();
    _startWeek.dispose();
    _endWeek.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final startMinute = _start.hour * 60 + _start.minute;
    final endMinute = _end.hour * 60 + _end.minute;
    if (endMinute <= startMinute) {
      setState(() => _error = '结束时间必须晚于开始时间');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.createCourse(
        name: _name.text.trim(),
        teacher: _nullable(_teacher.text),
        meeting: CourseMeeting(
          weekday: _weekday,
          startMinute: startMinute,
          endMinute: endMinute,
          startWeek: int.parse(_startWeek.text),
          endWeek: int.parse(_endWeek.text),
          weekParity: _weekParity,
          room: _nullable(_room.text),
        ),
      );
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
      title: const Text('添加课程'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  key: const Key('courseNameField'),
                  controller: _name,
                  validator: _required,
                  decoration: const InputDecoration(labelText: '课程名称'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _teacher,
                  decoration: const InputDecoration(labelText: '教师（可选）'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _weekday,
                  decoration: const InputDecoration(labelText: '星期'),
                  items: List.generate(
                    7,
                    (index) => DropdownMenuItem(
                      value: index + 1,
                      child: Text('星期${_weekdays[index]}'),
                    ),
                  ),
                  onChanged: (value) => setState(() => _weekday = value!),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _TimeField(
                        label: '开始',
                        value: _start,
                        onChanged: (value) => setState(() => _start = value),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _TimeField(
                        label: '结束',
                        value: _end,
                        onChanged: (value) => setState(() => _end = value),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _startWeek,
                        keyboardType: TextInputType.number,
                        validator: _week,
                        decoration: const InputDecoration(labelText: '起始周'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _endWeek,
                        keyboardType: TextInputType.number,
                        validator: _week,
                        decoration: const InputDecoration(labelText: '结束周'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: const Key('courseWeekParityField'),
                  initialValue: _weekParity,
                  decoration: const InputDecoration(labelText: '上课周次'),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('每周')),
                    DropdownMenuItem(value: 'odd', child: Text('仅单周')),
                    DropdownMenuItem(value: 'even', child: Text('仅双周')),
                  ],
                  onChanged: (value) => setState(() => _weekParity = value!),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _room,
                  decoration: const InputDecoration(labelText: '教室（可选）'),
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

class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final TimeOfDay value;
  final ValueChanged<TimeOfDay> onChanged;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () async {
      final picked = await showTimePicker(context: context, initialTime: value);
      if (picked != null) onChanged(picked);
    },
    child: InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: Text(value.format(context)),
    ),
  );
}

String? _required(String? value) =>
    value == null || value.trim().isEmpty ? '请填写此项' : null;
String? _week(String? value) {
  final week = int.tryParse(value ?? '');
  return week == null || week < 1 || week > 30 ? '请输入 1–30' : null;
}

String? _nullable(String value) => value.trim().isEmpty ? null : value.trim();
String _time(int minute) =>
    '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
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
