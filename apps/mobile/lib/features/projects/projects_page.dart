import 'package:flutter/material.dart';

import 'project_repository.dart';

class ProjectsPage extends StatefulWidget {
  const ProjectsPage({required this.repository, super.key});
  final ProjectRepository repository;

  @override
  State<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends State<ProjectsPage> {
  late Future<List<ProjectTag>> _tags;
  late Future<List<StudyProject>> _projects;
  late Future<List<ProjectApplication>> _applications;
  String? _status = 'recruiting';
  String? _tagId;

  @override
  void initState() {
    super.initState();
    _tags = widget.repository.listTags();
    _reload();
  }

  void _reload() {
    _projects = widget.repository.listProjects(status: _status, tagId: _tagId);
    _applications = widget.repository.listApplications();
  }

  void _refresh() => setState(_reload);

  Future<void> _create() async {
    final tags = await _tags;
    if (!mounted) return;
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _ProjectDialog(repository: widget.repository, tags: tags),
    );
    if (created == true && mounted) _refresh();
  }

  Future<void> _apply(StudyProject project) async {
    var applicationMessage = '';
    final message = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('申请加入「${project.title}」'),
        content: TextField(
          key: const Key('projectApplicationMessageField'),
          maxLength: 500,
          maxLines: 4,
          onChanged: (value) => applicationMessage = value,
          decoration: const InputDecoration(labelText: '申请说明'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, applicationMessage.trim()),
            child: const Text('提交申请'),
          ),
        ],
      ),
    );
    if (message == null || message.isEmpty) return;
    await _run(() => widget.repository.apply(project.id, message), '申请已提交');
  }

  Future<void> _report(StudyProject project) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _ProjectReportDialog(),
    );
    if (reason == null || !mounted) return;
    try {
      await widget.repository.reportProject(project.id, reason);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('举报已提交，感谢反馈')));
      }
    } on ProjectFailure catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _run(Future<void> Function() action, [String? success]) async {
    try {
      await action();
      if (mounted) {
        _refresh();
        if (success != null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(success)));
        }
      }
    } on ProjectFailure catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1000),
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '组队',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    const Text('发布组队需求、寻找队友并确认成员，后续沟通请使用你们信任的工具。'),
                  ],
                ),
              ),
              FilledButton.icon(
                key: const Key('addProjectButton'),
                onPressed: _create,
                icon: const Icon(Icons.add),
                label: const Text('发布组队'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String?>(
                  initialValue: _status,
                  decoration: const InputDecoration(labelText: '项目状态'),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('全部')),
                    DropdownMenuItem(value: 'recruiting', child: Text('招募中')),
                    DropdownMenuItem(value: 'in_progress', child: Text('进行中')),
                    DropdownMenuItem(value: 'closed', child: Text('已结束')),
                  ],
                  onChanged: (value) {
                    _status = value;
                    _refresh();
                  },
                ),
              ),
              SizedBox(
                width: 220,
                child: FutureBuilder<List<ProjectTag>>(
                  future: _tags,
                  builder: (context, snapshot) =>
                      DropdownButtonFormField<String?>(
                        isExpanded: true,
                        initialValue: _tagId,
                        decoration: const InputDecoration(labelText: '标签筛选'),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('全部标签'),
                          ),
                          ...(snapshot.data ?? const <ProjectTag>[]).map(
                            (tag) => DropdownMenuItem(
                              value: tag.id,
                              child: Text(tag.name),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          _tagId = value;
                          _refresh();
                        },
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          FutureBuilder<List<StudyProject>>(
            future: _projects,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return const Text('项目加载失败');
              }
              final projects = snapshot.data!;
              if (projects.isEmpty) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('暂无符合条件的项目')),
                  ),
                );
              }
              return Column(
                children: projects
                    .map(
                      (project) => _ProjectCard(
                        project: project,
                        onApply: () => _apply(project),
                        onReport: () => _report(project),
                        onStatus: (status) => _run(
                          () => widget.repository.setProjectStatus(
                            project.id,
                            status,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 28),
          Text('我的申请与收到的申请', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          FutureBuilder<List<ProjectApplication>>(
            future: _applications,
            builder: (context, snapshot) {
              final applications =
                  snapshot.data ?? const <ProjectApplication>[];
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (applications.isEmpty) return const Text('暂无申请记录');
              return Column(
                children: applications
                    .map(
                      (application) => Card(
                        child: ListTile(
                          title: Text(application.projectTitle),
                          subtitle: Text(
                            '${application.direction == 'incoming' ? application.applicantName : '我的申请'}'
                            ' · ${application.message} · ${_applicationStatus(application.status)}',
                          ),
                          trailing: application.status != 'pending'
                              ? null
                              : application.direction == 'incoming'
                              ? Wrap(
                                  spacing: 8,
                                  children: [
                                    TextButton(
                                      onPressed: () => _run(
                                        () => widget.repository.respond(
                                          application.id,
                                          'reject',
                                        ),
                                      ),
                                      child: const Text('拒绝'),
                                    ),
                                    FilledButton(
                                      key: Key(
                                        'accept-project-${application.id}',
                                      ),
                                      onPressed: () => _run(
                                        () => widget.repository.respond(
                                          application.id,
                                          'accept',
                                        ),
                                      ),
                                      child: const Text('接受'),
                                    ),
                                  ],
                                )
                              : TextButton(
                                  onPressed: () => _run(
                                    () => widget.repository.respond(
                                      application.id,
                                      'withdraw',
                                    ),
                                  ),
                                  child: const Text('撤回'),
                                ),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    ),
  );
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({
    required this.project,
    required this.onApply,
    required this.onReport,
    required this.onStatus,
  });
  final StudyProject project;
  final VoidCallback onApply;
  final VoidCallback onReport;
  final ValueChanged<String> onStatus;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  project.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Chip(label: Text(_projectStatus(project.status))),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '发起人：${project.ownerName} · 成员 ${project.memberCount}/${project.capacity}',
          ),
          const SizedBox(height: 10),
          Text(project.description),
          if (project.tags.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: project.tags
                  .map((tag) => Chip(label: Text(tag.name)))
                  .toList(),
            ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: project.ownedByMe
                ? PopupMenuButton<String>(
                    key: Key('project-status-${project.id}'),
                    onSelected: onStatus,
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'recruiting', child: Text('设为招募中')),
                      PopupMenuItem(value: 'in_progress', child: Text('设为进行中')),
                      PopupMenuItem(value: 'closed', child: Text('结束项目')),
                    ],
                    child: const Chip(label: Text('管理项目')),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: '举报组队帖',
                        icon: const Icon(Icons.flag_outlined),
                        onPressed: onReport,
                      ),
                      if (project.status == 'recruiting' &&
                          project.myApplicationStatus == null)
                        FilledButton.tonal(
                          key: Key('apply-project-${project.id}'),
                          onPressed: onApply,
                          child: const Text('申请加入'),
                        )
                      else if (project.myApplicationStatus != null)
                        Chip(
                          label: Text(
                            _applicationStatus(project.myApplicationStatus!),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    ),
  );
}

class _ProjectReportDialog extends StatefulWidget {
  const _ProjectReportDialog();

  @override
  State<_ProjectReportDialog> createState() => _ProjectReportDialogState();
}

class _ProjectReportDialogState extends State<_ProjectReportDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('举报组队帖'),
    content: TextField(
      controller: _reason,
      autofocus: true,
      maxLength: 500,
      maxLines: 3,
      decoration: const InputDecoration(labelText: '请说明举报原因（至少 5 个字）'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          if (_reason.text.trim().length < 5) return;
          Navigator.pop(context, _reason.text.trim());
        },
        child: const Text('提交举报'),
      ),
    ],
  );
}

class _ProjectDialog extends StatefulWidget {
  const _ProjectDialog({required this.repository, required this.tags});
  final ProjectRepository repository;
  final List<ProjectTag> tags;

  @override
  State<_ProjectDialog> createState() => _ProjectDialogState();
}

class _ProjectDialogState extends State<_ProjectDialog> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final Set<String> _tagIds = {};
  int _capacity = 4;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.repository.createProject(
        title: _title.text.trim(),
        description: _description.text.trim(),
        capacity: _capacity,
        tagIds: _tagIds.toList(),
      );
      if (mounted) Navigator.pop(context, true);
    } on ProjectFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('发布组队'),
    content: SizedBox(
      width: 520,
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const Key('projectTitleField'),
                controller: _title,
                maxLength: 100,
                validator: (value) =>
                    value == null || value.trim().isEmpty ? '请填写项目名称' : null,
                decoration: const InputDecoration(labelText: '项目名称'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                key: const Key('projectDescriptionField'),
                controller: _description,
                maxLength: 3000,
                maxLines: 5,
                validator: (value) =>
                    value == null || value.trim().isEmpty ? '请填写项目简介' : null,
                decoration: const InputDecoration(labelText: '项目简介'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                initialValue: _capacity,
                decoration: const InputDecoration(labelText: '团队人数上限'),
                items: List.generate(
                  10,
                  (index) => DropdownMenuItem(
                    value: index + 1,
                    child: Text('${index + 1} 人'),
                  ),
                ),
                onChanged: (value) => setState(() => _capacity = value!),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '领域与目标标签',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: widget.tags
                    .map(
                      (tag) => FilterChip(
                        key: Key('project-tag-${tag.id}'),
                        label: Text(tag.name),
                        selected: _tagIds.contains(tag.id),
                        onSelected: (selected) => setState(() {
                          if (selected && _tagIds.length < 8) {
                            _tagIds.add(tag.id);
                          } else if (!selected) {
                            _tagIds.remove(tag.id);
                          }
                        }),
                      ),
                    )
                    .toList(),
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
        key: const Key('saveProjectButton'),
        onPressed: _saving ? null : _save,
        child: Text(_saving ? '发布中…' : '发布'),
      ),
    ],
  );
}

String _projectStatus(String status) =>
    const {
      'recruiting': '招募中',
      'in_progress': '进行中',
      'closed': '已结束',
    }[status] ??
    status;
String _applicationStatus(String status) =>
    const {
      'pending': '待处理',
      'accepted': '已接受',
      'rejected': '已拒绝',
      'withdrawn': '已撤回',
    }[status] ??
    status;
