import 'package:flutter/material.dart';

// [2026-10-14 已停用] 验证码与北邮学校密码验证相关代码已注释，保留以便日后恢复。
// 注册现在需要邀请码与邮箱，不再验证学生身份。
// import 'dart:convert';

import 'auth_repository.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({
    required this.repository,
    required this.onAuthenticated,
    this.casCode,
    this.casState,
    super.key,
  });

  final AuthRepository repository;
  final ValueChanged<AuthSession> onAuthenticated;
  // [2026-10-14 已停用] 北邮跳转认证回调参数，当前流程不使用。
  final String? casCode;
  final String? casState;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _inviteCode = TextEditingController();
  final _appPassword = TextEditingController();
  bool _registering = false;
  bool _submitting = false;
  bool _obscurePassword = true;
  String? _error;

  // [2026-10-14 已停用] 学校密码与验证码状态。
  // final _schoolPassword = TextEditingController();
  // final _captcha = TextEditingController();
  // CasPasswordChallenge? _casPasswordChallenge;
  // bool _requestingCasChallenge = false;
  // [2026-10-14 已停用] 北邮跳转认证回调状态。
  // bool _completingCas = false;
  // bool _casHandled = false;
  // final _department = TextEditingController();

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _inviteCode.dispose();
    _appPassword.dispose();
    super.dispose();
  }

  // [2026-10-14 已停用] 北邮跳转认证回调处理。
  // @override
  // void didChangeDependencies() {
  //   super.didChangeDependencies();
  //   if (_casHandled) return;
  //   final code = widget.casCode;
  //   final state = widget.casState;
  //   if (code == null && state == null) return;
  //   _casHandled = true;
  //   if (code == null || state == null || code.length > 128 || state.length > 128) {
  //     _error = '北邮认证回调无效，请重新开始';
  //     return;
  //   }
  //   WidgetsBinding.instance.addPostFrameCallback(
  //     (_) => _completeBrowserCas(code, state),
  //   );
  // }
  //
  // Future<void> _completeBrowserCas(String code, String state) async {
  //   if (!mounted) return;
  //   setState(() {
  //     _completingCas = true;
  //     _error = null;
  //   });
  //   try {
  //     final session = await widget.repository.completeBrowserCas(
  //       code: code,
  //       state: state,
  //       displayName: _displayName.text.trim().isEmpty ? null : _displayName.text.trim(),
  //       appPassword: _appPassword.text.isEmpty ? null : _appPassword.text,
  //       departmentId: _department.text.trim().isEmpty ? null : _department.text.trim(),
  //     );
  //     widget.onAuthenticated(session);
  //   } on AuthFailure catch (error) {
  //     if (!mounted) return;
  //     setState(() {
  //       _completingCas = false;
  //       _registering = error.code == 'cas_registration_required';
  //       _error = error.message;
  //     });
  //   }
  // }

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
              username: _username.text.trim(),
              email: _email.text.trim(),
              appPassword: _appPassword.text,
              departmentId: null,
              inviteCode: _inviteCode.text.trim(),
            )
          : await widget.repository.login(
              username: _username.text.trim(),
              appPassword: _appPassword.text.trim(),
            );
      widget.onAuthenticated(session);
    } on AuthFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // [2026-10-14 已停用] 学校密码 + 验证码挑战流程。
  // Future<void> _beginCasPasswordChallenge() async {
  //   if (!_formKey.currentState!.validate()) return;
  //   setState(() {
  //     _requestingCasChallenge = true;
  //     _error = null;
  //   });
  //   try {
  //     final challenge = await widget.repository.beginCasPasswordChallenge(
  //       _studentId.text.trim(),
  //     );
  //     if (mounted) setState(() => _casPasswordChallenge = challenge);
  //   } on AuthFailure catch (error) {
  //     if (mounted) setState(() => _error = error.message);
  //   } finally {
  //     if (mounted) setState(() => _requestingCasChallenge = false);
  //   }
  // }
  //
  // Future<void> _verifyCasPasswordChallenge() async {
  //   if (!_formKey.currentState!.validate()) return;
  //   setState(() {
  //     _submitting = true;
  //     _error = null;
  //   });
  //   try {
  //     final session = await widget.repository.verifyCasPasswordChallenge(
  //       challengeId: _casPasswordChallenge!.id,
  //       studentId: _studentId.text.trim(),
  //       schoolPassword: _schoolPassword.text,
  //       captcha: _captcha.text.trim().isEmpty ? null : _captcha.text.trim(),
  //       displayName: _displayName.text.trim(),
  //       appPassword: _appPassword.text,
  //     );
  //     widget.onAuthenticated(session);
  //   } on AuthFailure catch (error) {
  //     // 验证码错误时刷新验证码并保留表单，其余错误清空挑战。
  //     if (mounted) setState(() => _error = error.message);
  //   } finally {
  //     _schoolPassword.clear();
  //     if (mounted) setState(() => _submitting = false);
  //   }
  // }

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
                margin: EdgeInsets.zero,
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
                          _registering ? '使用邀请码创建账户' : '登录你的课业空间',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                        const SizedBox(height: 26),
                        SegmentedButton<bool>(
                          key: const Key('authModeSelector'),
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
                        TextFormField(
                          key: const Key('usernameField'),
                          controller: _username,
                          validator: (value) {
                            if (!RegExp(r'^[A-Za-z0-9_]{3,20}$')
                                .hasMatch(value?.trim() ?? '')) {
                              return '请输入 3–20 位字母、数字或下划线';
                            }
                            return null;
                          },
                          autocorrect: false,
                          textCapitalization: TextCapitalization.none,
                          decoration: const InputDecoration(
                            labelText: '用户名',
                            helperText: '登录时使用，不区分大小写。',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                        ),
                        const SizedBox(height: 14),
                        if (_registering) ...[
                          TextFormField(
                            key: const Key('emailField'),
                            controller: _email,
                            validator: (value) {
                              if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                  .hasMatch(value?.trim() ?? '')) {
                                return '请输入有效的邮箱';
                              }
                              return null;
                            },
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              labelText: '邮箱',
                              helperText: '用于账户记录，暂不发送验证邮件。',
                              prefixIcon: Icon(Icons.alternate_email),
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            key: const Key('inviteCodeField'),
                            controller: _inviteCode,
                            validator: _required,
                            autocorrect: false,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              labelText: '邀请码',
                              helperText: '每位同学每月可生成 5 个邀请码。',
                              prefixIcon: Icon(
                                Icons.confirmation_number_outlined,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                        // [2026-10-14 已停用] 学校密码与验证码输入框。
                        // if (_registering) ...[
                        //   TextFormField(key: const Key('schoolPasswordField'), controller: _schoolPassword, ...),
                        //   if (_casPasswordChallenge?.captchaImage != null) Image.memory(...),
                        //   TextFormField(key: const Key('casCaptchaField'), controller: _captcha, ...),
                        // ],
                        TextFormField(
                          key: const Key('appPasswordField'),
                          controller: _appPassword,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return '请填写密码';
                            }
                            if (_registering && value.length < 10) {
                              return '本系统密码至少 10 位';
                            }
                            return null;
                          },
                          obscureText: _obscurePassword,
                          onFieldSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                            labelText: _registering ? '设置 FStudy 密码' : '本系统密码',
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
                              ? SizedBox.square(
                                  dimension: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: colors.onPrimary,
                                  ),
                                )
                              : Text(_registering ? '注册' : '登录'),
                        ),
                        // [2026-10-14 已停用] 北邮统一身份认证跳转登录按钮。
                        // OutlinedButton.icon(key: Key('buptCasLoginButton'), onPressed: _startBrowserCas, ...),
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
