import 'package:flutter/material.dart';

import 'auth_repository.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({
    required this.repository,
    required this.onAuthenticated,
    super.key,
  });

  final AuthRepository repository;
  final ValueChanged<AuthSession> onAuthenticated;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _studentId = TextEditingController();
  final _schoolPassword = TextEditingController(text: 'dev-password');
  final _appPassword = TextEditingController();
  final _displayName = TextEditingController();
  final _department = TextEditingController(text: 'computer');
  bool _registering = false;
  bool _submitting = false;
  bool _obscurePassword = true;
  String? _error;

  @override
  void dispose() {
    _studentId.dispose();
    _schoolPassword.dispose();
    _appPassword.dispose();
    _displayName.dispose();
    _department.dispose();
    super.dispose();
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? '请填写此项' : null;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final session = _registering
          ? await widget.repository.register(
              studentId: _studentId.text.trim(),
              schoolPassword: _schoolPassword.text,
              appPassword: _appPassword.text,
              displayName: _displayName.text.trim(),
              departmentId: _department.text.trim().isEmpty
                  ? null
                  : _department.text.trim(),
            )
          : await widget.repository.login(
              studentId: _studentId.text.trim(),
              appPassword: _appPassword.text,
            );
      widget.onAuthenticated(session);
    } on AuthFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                elevation: 0,
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: colors.primaryContainer,
                          child: Icon(
                            Icons.school_rounded,
                            color: colors.primary,
                            size: 30,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'FStudy',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _registering ? '创建北邮学生账户' : '登录你的课业空间',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                        const SizedBox(height: 26),
                        SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(value: false, label: Text('登录')),
                            ButtonSegment(value: true, label: Text('注册')),
                          ],
                          selected: {_registering},
                          onSelectionChanged: (value) => setState(() {
                            _registering = value.first;
                            _error = null;
                          }),
                        ),
                        const SizedBox(height: 20),
                        if (_registering) ...[
                          TextFormField(
                            key: const Key('displayNameField'),
                            controller: _displayName,
                            validator: _required,
                            decoration: const InputDecoration(
                              labelText: '显示名称',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _department,
                            decoration: const InputDecoration(
                              labelText: '院系代码（测试）',
                              prefixIcon: Icon(Icons.apartment_outlined),
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                        TextFormField(
                          key: const Key('studentIdField'),
                          controller: _studentId,
                          validator: (value) {
                            if (!RegExp(r'^\d{8,12}$')
                                .hasMatch(value?.trim() ?? '')) {
                              return '请输入 8–12 位数字学号';
                            }
                            return null;
                          },
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '学号',
                            prefixIcon: Icon(Icons.badge_outlined),
                          ),
                        ),
                        const SizedBox(height: 14),
                        if (_registering) ...[
                          TextFormField(
                            key: const Key('schoolPasswordField'),
                            controller: _schoolPassword,
                            validator: _required,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: '学校认证密码',
                              helperText: '本地测试固定为 dev-password',
                              prefixIcon: Icon(Icons.verified_user_outlined),
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                        TextFormField(
                          key: const Key('appPasswordField'),
                          controller: _appPassword,
                          validator: (value) {
                            if (value == null || value.isEmpty) return '请填写密码';
                            if (_registering && value.length < 10) {
                              return '本系统密码至少 10 位';
                            }
                            return null;
                          },
                          obscureText: _obscurePassword,
                          onFieldSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                            labelText: _registering ? '设置本系统密码' : '本系统密码',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 14),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: colors.error),
                          ),
                        ],
                        const SizedBox(height: 20),
                        FilledButton(
                          key: const Key('submitAuthButton'),
                          onPressed: _submitting ? null : _submit,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(50),
                          ),
                          child: _submitting
                              ? const SizedBox.square(
                                  dimension: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(_registering ? '验证并注册' : '登录'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
