import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'profile_repository.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    required this.repository,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.onLogout,
    super.key,
  });
  final ProfileRepository repository;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final Future<void> Function() onLogout;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late Future<UserProfile> _profile;
  final _form = GlobalKey<FormState>();
  final _displayName = TextEditingController();
  final _bio = TextEditingController();
  final _department = TextEditingController();
  bool _discoverable = false;
  String _scheduleVisibility = 'busy_only';
  bool _initialized = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _profile = widget.repository.getProfile();
  }

  @override
  void dispose() {
    _displayName.dispose();
    _bio.dispose();
    _department.dispose();
    super.dispose();
  }

  void _initialize(UserProfile profile) {
    if (_initialized) return;
    _initialized = true;
    _displayName.text = profile.displayName;
    _bio.text = profile.bio;
    _department.text = profile.departmentId ?? '';
    _discoverable = profile.discoverable;
    _scheduleVisibility = profile.scheduleVisibility;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final updated = await widget.repository.updateProfile(
        UserProfile(
          displayName: _displayName.text.trim(),
          bio: _bio.text.trim(),
          departmentId: _department.text.trim().isEmpty
              ? null
              : _department.text.trim(),
          discoverable: _discoverable,
          scheduleVisibility: _scheduleVisibility,
        ),
      );
      if (!mounted) return;
      setState(() {
        _profile = Future.value(updated);
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('资料与隐私设置已保存')));
    } on ProfileFailure catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserProfile>(
      future: _profile,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Center(child: Text('个人资料加载失败'));
        }
        _initialize(snapshot.data!);
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Form(
              key: _form,
              child: ListView(
                key: const Key('profileSettingsList'),
                padding: const EdgeInsets.all(24),
                children: [
                  Text(
                    '个人资料',
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (snapshot.data!.username != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      '@${snapshot.data!.username}',
                      key: const Key('profileUsername'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    '控制其他同学如何发现你，以及能看到多少课表信息。',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    key: const Key('profileDisplayNameField'),
                    controller: _displayName,
                    validator: (value) => value == null || value.trim().isEmpty
                        ? '请填写显示名称'
                        : null,
                    decoration: const InputDecoration(labelText: '显示名称'),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _department,
                    decoration: const InputDecoration(labelText: '院系代码'),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _bio,
                    maxLength: 300,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: '个人简介'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('允许被推荐和发现'),
                    subtitle: const Text('关闭后不会出现在同学推荐中'),
                    value: _discoverable,
                    onChanged: (value) => setState(() => _discoverable = value),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    key: const Key('scheduleVisibilityField'),
                    initialValue: _scheduleVisibility,
                    decoration: const InputDecoration(labelText: '课表可见性'),
                    items: const [
                      DropdownMenuItem(value: 'private', child: Text('完全私密')),
                      DropdownMenuItem(
                        value: 'busy_only',
                        child: Text('仅显示忙闲状态'),
                      ),
                      DropdownMenuItem(
                        value: 'course_name',
                        child: Text('显示课程名称'),
                      ),
                      DropdownMenuItem(value: 'full', child: Text('显示完整课程信息')),
                    ],
                    onChanged: (value) =>
                        setState(() => _scheduleVisibility = value!),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      key: const Key('manageTagsButton'),
                      leading: const Icon(Icons.interests_outlined),
                      title: const Text('个人标签'),
                      subtitle: const Text('管理兴趣、领域、目标和推荐偏好'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.go('/profile/tags'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    margin: EdgeInsets.zero,
                    child: SwitchListTile(
                      key: const Key('darkModeSwitch'),
                      secondary: const Icon(Icons.dark_mode_outlined),
                      title: const Text('夜间模式'),
                      subtitle: const Text('此设置保存在当前设备'),
                      value: widget.themeMode == ThemeMode.dark,
                      onChanged: (enabled) => widget.onThemeModeChanged(
                        enabled ? ThemeMode.dark : ThemeMode.light,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      key: const Key('saveProfileButton'),
                      onPressed: _saving ? null : _save,
                      icon: const Icon(Icons.save_outlined),
                      label: Text(_saving ? '保存中…' : '保存设置'),
                    ),
                  ),
                  const SizedBox(height: 32),
                  _InviteCard(repository: widget.repository),
                  const SizedBox(height: 12),
                  Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      key: const Key('aboutProjectButton'),
                      leading: const Icon(Icons.info_outline),
                      title: const Text('关于 FStudy'),
                      subtitle: const Text('项目介绍与 GitHub 仓库'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.go('/profile/about'),
                    ),
                  ),
                  const SizedBox(height: 48),
                  const Divider(),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const Key('logoutButton'),
                      onPressed: _confirmLogout,
                      icon: const Icon(Icons.logout),
                      label: const Text('退出登录'),
                      style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认退出登录？'),
        content: const Text('退出后需要重新登录才能使用课表和社区。'),
        actions: [
          TextButton(
            key: const Key('cancelLogoutButton'),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续使用'),
          ),
          FilledButton.tonal(
            key: const Key('confirmLogoutButton'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('退出登录'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.onLogout();
  }
}

class _InviteCard extends StatefulWidget {
  const _InviteCard({required this.repository});

  final ProfileRepository repository;

  @override
  State<_InviteCard> createState() => _InviteCardState();
}

class _InviteCardState extends State<_InviteCard> {
  InviteOverview? _overview;
  String? _error;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final overview = await widget.repository.getInvites();
      if (mounted) setState(() => _overview = overview);
    } on ProfileFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _create() async {
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final issued = await widget.repository.createInvite();
      if (!mounted) return;
      setState(() {
        _overview = InviteOverview(
          remainingThisMonth: issued.remainingThisMonth,
          quota: _overview!.quota,
        );
      });
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('新的邀请码'),
          content: SelectableText(
            issued.code,
            key: const Key('issuedInviteCode'),
            style: Theme.of(dialogContext).textTheme.titleLarge,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('完成'),
            ),
          ],
        ),
      );
    } on ProfileFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final overview = _overview;
    final canCreate =
        !_creating && overview != null && overview.remainingThisMonth > 0;
    return Card(
      key: const Key('inviteCard'),
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: const Icon(Icons.group_add_outlined),
        title: const Text('邀请同学'),
        subtitle: Text(
          _error ??
              (overview == null
                  ? '正在读取邀请额度…'
                  : '本月还可生成 ${overview.remainingThisMonth} / ${overview.quota} 个邀请码'),
        ),
        trailing: FilledButton(
          key: const Key('createInviteButton'),
          onPressed: canCreate ? _create : null,
          child: Text(_creating ? '生成中…' : '生成'),
        ),
      ),
    );
  }
}
