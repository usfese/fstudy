import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';

const _configuredApiUrl = String.fromEnvironment('API_BASE_URL');

String get _defaultApiUrl {
  if (kIsWeb) return 'http://127.0.0.1:8787';
  return 'http://10.0.2.2:8787';
}

class AuthUser {
  const AuthUser({
    required this.id,
    required this.displayName,
    required this.departmentId,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
    id: json['id'] as String,
    displayName: json['displayName'] as String,
    departmentId: json['departmentId'] as String?,
  );

  final String id;
  final String displayName;
  final String? departmentId;
}

class AuthSession {
  const AuthSession({required this.accessToken, required this.user});

  final String accessToken;
  final AuthUser user;
}

class CasPasswordChallenge {
  const CasPasswordChallenge({required this.id, required this.captchaImage});
  final String id;
  final String? captchaImage;
}

class AuthFailure implements Exception {
  const AuthFailure(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

abstract interface class AuthRepository {
  Future<AuthSession?> restoreSession();

  Future<AuthSession> login({
    required String studentId,
    required String appPassword,
  });

  Future<AuthSession> register({
    required String studentId,
    required String schoolPassword,
    required String appPassword,
    required String displayName,
    required String? departmentId,
  });

  Future<void> startBrowserCas();
  Future<AuthSession> completeBrowserCas({
    required String code,
    required String state,
    String? displayName,
    String? appPassword,
    String? departmentId,
  });

  Future<CasPasswordChallenge> beginCasPasswordChallenge(String studentId);
  Future<CasPasswordChallenge> refreshCasPasswordChallenge({
    required String challengeId,
    required String studentId,
  });
  Future<AuthSession> verifyCasPasswordChallenge({
    required String challengeId,
    required String studentId,
    required String schoolPassword,
    required String? captcha,
    required String displayName,
    required String appPassword,
  });

  Future<void> logout();
}

class DioAuthRepository implements AuthRepository {
  DioAuthRepository({Dio? dio, FlutterSecureStorage? storage})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: _configuredApiUrl.isEmpty
                  ? _defaultApiUrl
                  : _configuredApiUrl,
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
              headers: {'content-type': 'application/json'},
            ),
          ),
      _storage = storage ?? const FlutterSecureStorage();

  static const _tokenKey = 'fstudy_access_token';
  final Dio _dio;
  final FlutterSecureStorage _storage;

  @override
  Future<AuthSession?> restoreSession() async {
    try {
      final token = await _storage.read(key: _tokenKey);
      if (token == null) return null;
      final response = await _dio.get<Map<String, dynamic>>(
        '/v1/me',
        options: Options(headers: {'authorization': 'Bearer $token'}),
      );
      final user = AuthUser.fromJson(
        response.data!['user'] as Map<String, dynamic>,
      );
      return AuthSession(accessToken: token, user: user);
    } catch (_) {
      await _storage.delete(key: _tokenKey);
      return null;
    }
  }

  @override
  Future<AuthSession> login({
    required String studentId,
    required String appPassword,
  }) => _authenticate('/v1/auth/login', {
    'studentId': studentId,
    'appPassword': appPassword,
  });

  @override
  Future<AuthSession> register({
    required String studentId,
    required String schoolPassword,
    required String appPassword,
    required String displayName,
    required String? departmentId,
  }) => _authenticate('/v1/auth/register', {
    'studentId': studentId,
    'schoolPassword': schoolPassword,
    'appPassword': appPassword,
    'displayName': displayName,
    'departmentId': departmentId,
  });

  @override
  Future<void> startBrowserCas() async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/v1/auth/cas/start',
      );
      final url = Uri.parse(response.data!['authorizationUrl'] as String);
      final opened = await launchUrl(
        url,
        mode: kIsWeb
            ? LaunchMode.platformDefault
            : LaunchMode.externalApplication,
        webOnlyWindowName: '_self',
      );
      if (!opened) throw const AuthFailure('无法打开北邮统一身份认证页面');
    } on AuthFailure {
      rethrow;
    } on DioException catch (error) {
      final data = error.response?.data;
      if (data is Map && data['error'] is Map) {
        final errorBody = data['error'] as Map;
        final message = errorBody['message'];
        if (message is String) {
          throw AuthFailure(message, code: errorBody['code'] as String?);
        }
      }
      throw const AuthFailure('无法连接认证服务，请稍后重试');
    }
  }

  @override
  Future<AuthSession> completeBrowserCas({
    required String code,
    required String state,
    String? displayName,
    String? appPassword,
    String? departmentId,
  }) => _authenticate('/v1/auth/cas/complete', {
    'code': code,
    'state': state,
    'displayName': ?displayName,
    'appPassword': ?appPassword,
    'departmentId': departmentId,
  });

  @override
  Future<CasPasswordChallenge> beginCasPasswordChallenge(String studentId) =>
      _requestCasChallenge('/v1/auth/cas/password/challenge', {
        'studentId': studentId,
      });

  @override
  Future<CasPasswordChallenge> refreshCasPasswordChallenge({
    required String challengeId,
    required String studentId,
  }) => _requestCasChallenge('/v1/auth/cas/password/refresh', {
    'challengeId': challengeId,
    'studentId': studentId,
  });

  Future<CasPasswordChallenge> _requestCasChallenge(
    String path,
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(path, data: data);
      return CasPasswordChallenge(
        id: response.data!['challengeId'] as String,
        captchaImage: response.data!['captchaImage'] as String?,
      );
    } on DioException catch (error) {
      throw _authFailure(error);
    }
  }

  @override
  Future<AuthSession> verifyCasPasswordChallenge({
    required String challengeId,
    required String studentId,
    required String schoolPassword,
    required String? captcha,
    required String displayName,
    required String appPassword,
  }) => _authenticate('/v1/auth/cas/password/verify', {
    'challengeId': challengeId,
    'studentId': studentId,
    'schoolPassword': schoolPassword,
    'captcha': ?captcha,
    'displayName': displayName,
    'appPassword': appPassword,
    'departmentId': null,
  });

  AuthFailure _authFailure(DioException error) {
    final data = error.response?.data;
    if (data is Map && data['error'] is Map) {
      final errorBody = data['error'] as Map;
      final message = errorBody['message'];
      if (message is String) {
        return AuthFailure(message, code: errorBody['code'] as String?);
      }
    }
    return const AuthFailure('无法连接认证服务，请稍后重试');
  }

  Future<AuthSession> _authenticate(
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(path, data: body);
      final data = response.data!;
      final session = AuthSession(
        accessToken: data['accessToken'] as String,
        user: AuthUser.fromJson(data['user'] as Map<String, dynamic>),
      );
      await _storage.write(key: _tokenKey, value: session.accessToken);
      return session;
    } on DioException catch (error) {
      final data = error.response?.data;
      if (data is Map && data['error'] is Map) {
        final message = (data['error'] as Map)['message'];
        if (message is String) {
          throw AuthFailure(
            message,
            code: (data['error'] as Map)['code'] as String?,
          );
        }
      }
      throw const AuthFailure('无法连接服务器，请确认本地 API 已启动');
    }
  }

  @override
  Future<void> logout() async {
    final token = await _storage.read(key: _tokenKey);
    if (token != null) {
      try {
        await _dio.post<Map<String, dynamic>>(
          '/v1/auth/logout',
          options: Options(headers: {'authorization': 'Bearer $token'}),
        );
      } catch (_) {
        // Local logout must still succeed when the server is unavailable.
      }
    }
    await _storage.delete(key: _tokenKey);
  }
}
