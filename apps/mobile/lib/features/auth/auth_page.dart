import 'package:flutter/material.dart';

import 'dart:convert';

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
  final String? casCode;
  final String? casState;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _studentId = TextEditingController();
  final _schoolPassword = TextEditingController();
  final _appPassword = TextEditingController();
  final _displayName = TextEditingController();
  final _department = TextEditingController();
  bool _registering = false;
  bool _submitting = false;
  bool _obscurePassword = true;
  String? _error;
  bool _completingCas = false;
  bool _casHandled = false;
  CasPasswordChallenge? _casPasswordChallenge;
  final _captcha = TextEditingController();
  bool _requestingCasChallenge = false;

  @override
  void dispose() {
    _studentId.dispose();
    _schoolPassword.dispose();
    _captcha.dispose();
    _appPassword.dispose();
    _displayName.dispose();
    _department.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_casHandled) return;
    final code = widget.casCode;
    final state = widget.casState;
    if (code == null && state == null) return;
    _casHandled = true;
    if (code == null ||
        state == null ||
        code.length > 128 ||
        state.length > 128) {
      _error = '北邮认证回调无效，请重新开始';
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _completeBrowserCas(code, state),
    );
  }

  Future<void> _completeBrowserCas(String code, String state) async {
    if (!mounted) return;
    setState(() {
      _completingCas = true;
      _error = null;
    });
    try {
      final session = await widget.repository.completeBrowserCas(
        code: code,
        state: state,
        displayName: _displayName.text.trim().isEmpty
            ? null
            : _displayName.text.trim(),
        appPassword: _appPassword.text.isEmpty ? null : _appPassword.text,
        departmentId: _department.text.trim().isEmpty
            ? null
            : _department.text.trim(),
      );
      widget.onAuthenticated(session);
    } on AuthFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _completingCas = false;
        _registering = error.code == 'cas_registration_required';
        _error = error.message;
      });
    }
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? '请填写此项' : null;

  Future<void> _submit() async {
    if (_registering && widget.casCode == null) {
      if (_casPasswordChallenge == null) {
        await _beginCasPasswordChallenge();
      } else {
        await _verifyCasPasswordChallenge();
      }
      return;
    }
    if (widget.casCode != null && widget.casState != null) {
      if (_registering && !_formKey.currentState!.validate()) return;
      await _completeBrowserCas(widget.casCode!, widget.casState!);
      return;
    }
    if (_registering) {
      await _startBrowserCas();
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final session = await widget.repository.login(
        studentId: _studentId.text.trim(),
        appPassword: _appPassword.text.trim(),
      );
      widget.onAuthenticated(session);
    } on AuthFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _beginCasPasswordChallenge() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _requestingCasChallenge = true;
      _error = null;
    });
    try {
      final challenge = await widget.repository.beginCasPasswordChallenge(
        _studentId.text.trim(),
      );
      if (mounted) setState(() => _casPasswordChallenge = challenge);
    } on AuthFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _requestingCasChallenge = false);
    }
  }

  Future<void> _verifyCasPasswordChallenge() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final session = await widget.repository.verifyCasPasswordChallenge(
        challengeId: _casPasswordChallenge!.id,
        studentId: _studentId.text.trim(),
        schoolPassword: _schoolPassword.text,
        captcha: _captcha.text.trim().isEmpty ? null : _captcha.text.trim(),
        displayName: _displayName.text.trim(),
        appPassword: _appPassword.text,
      );
      widget.onAuthenticated(session);
    } on AuthFailure catch (error) {
      if (mounted) {
        var nextChallenge = _casPasswordChallenge;
        var message = error.message;
        if (error.code == 'school_auth_captcha_invalid' &&
            nextChallenge != null) {
          try {
            nextChallenge = await widget.repository.refreshCasPasswordChallenge(
              challengeId: nextChallenge.id,
              studentId: _studentId.text.trim(),
            );
            _captcha.clear();
          } on AuthFailure catch (refreshError) {
            nextChallenge = null;
            message = refreshError.message;
          }
        } else if (error.code == 'cas_challenge_expired' ||
            error.code == 'cas_challenge_identity_mismatch') {
          nextChallenge = null;
          _captcha.clear();
        }
        setState(() {
          _error = message;
          _casPasswordChallenge = nextChallenge;
        });
      }
    } finally {
      _schoolPassword.clear();
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
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
                          _registering ? '使用北邮统一身份认证创建账户' : '登录你的课业空间',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                        const SizedBox(height: 26),
                        if (widget.casCode == null)
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
                        if (widget.casCode == null) ...[
                          const SizedBox(height: 20),
                        ],
                        if (widget.casCode == null) ...[
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
                        ],
                        const SizedBox(height: 14),
                        if (_registering &&
                            widget.casCode == null &&
                            _casPasswordChallenge == null)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Text(
                              '重要：北邮密码会经 HTTPS 通过 FStudy 后端转交北邮 CAS，仅用于本次验证；FStudy 不会保存密码。验证码会加密暂存于服务端，最多 5 分钟、单次使用。',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        if (_registering) ...[
                          TextFormField(
                            key: const Key('displayNameField'),
                            controller: _displayName,
                            validator: _required,
                            decoration: const InputDecoration(
                              labelText: 'FStudy 显示名称',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                        if (_registering && widget.casCode == null) ...[
                          TextFormField(
                            key: const Key('schoolPasswordField'),
                            controller: _schoolPassword,
                            validator: _required,
                            obscureText: true,
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration: const InputDecoration(
                              labelText: '北邮统一身份认证密码',
                              helperText:
                                  '仅用于向北邮 CAS 验证；FStudy 不保存密码、Cookie 或票据。',
                              prefixIcon: Icon(Icons.verified_user_outlined),
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                        if (_registering &&
                            widget.casCode == null &&
                            _casPasswordChallenge != null) ...[
                          if (_casPasswordChallenge!.captchaImage != null)
                            Center(
                              child: Image.memory(
                                base64Decode(
                                  _casPasswordChallenge!.captchaImage!
                                      .split(',')
                                      .last,
                                ),
                                key: const Key('casCaptchaImage'),
                                errorBuilder: (_, error, stack) =>
                                    const Text('验证码图片无法显示，请重新获取'),
                              ),
                            ),
                          TextFormField(
                            key: const Key('casCaptchaField'),
                            controller: _captcha,
                            validator: _required,
                            decoration: const InputDecoration(
                              labelText: '北邮验证码',
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                        if (widget.casCode == null ||
                            widget.casCode != null && _registering)
                          TextFormField(
                            key: const Key('appPasswordField'),
                            controller: _appPassword,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return '请填写密码';
                              }
                              if (widget.casCode != null &&
                                  _registering &&
                                  value.length < 10) {
                                return '本系统密码至少 10 位';
                              }
                              return null;
                            },
                            obscureText: _obscurePassword,
                            onFieldSubmitted: (_) => _submit(),
                            decoration: InputDecoration(
                              labelText: widget.casCode != null && _registering
                                  ? '设置 FStudy 密码'
                                  : '本系统密码',
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
                              : Text(
                                  _completingCas
                                      ? '正在完成登录…'
                                      : widget.casCode != null
                                      ? (_registering ? '完成注册' : '完成登录')
                                      : _registering
                                      ? (_casPasswordChallenge == null
                                            ? '获取北邮验证码'
                                            : '验证并创建账户')
                                      : '登录',
                                ),
                        ),
                        if (widget.casCode == null && !_registering) ...[
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            key: const Key('buptCasLoginButton'),
                            onPressed: _submitting || _requestingCasChallenge
                                ? null
                                : (_registering ? _submit : _startBrowserCas),
                            icon: const Icon(Icons.open_in_browser),
                            label: Text(
                              _registering
                                  ? (_casPasswordChallenge == null
                                        ? '获取北邮验证码'
                                        : '验证并创建账户')
                                  : '使用北邮统一身份认证登录',
                            ),
                          ),
                        ],
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

  Future<void> _startBrowserCas() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.repository.startBrowserCas();
    } on AuthFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}
