import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

const _configuredApiUrl = String.fromEnvironment('API_BASE_URL');

String get _defaultApiUrl =>
    kIsWeb ? 'http://127.0.0.1:8787' : 'http://10.0.2.2:8787';

class ProfileFailure implements Exception {
  const ProfileFailure(this.message);
  final String message;
}

class UserProfile {
  const UserProfile({
    required this.displayName,
    required this.bio,
    required this.departmentId,
    required this.discoverable,
    required this.scheduleVisibility,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    displayName: json['displayName'] as String,
    bio: json['bio'] as String,
    departmentId: json['departmentId'] as String?,
    discoverable: json['discoverable'] as bool,
    scheduleVisibility: json['scheduleVisibility'] as String,
  );

  final String displayName;
  final String bio;
  final String? departmentId;
  final bool discoverable;
  final String scheduleVisibility;
}

abstract interface class ProfileRepository {
  Future<UserProfile> getProfile();
  Future<UserProfile> updateProfile(UserProfile profile);
}

class DioProfileRepository implements ProfileRepository {
  DioProfileRepository({required String accessToken, Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: _configuredApiUrl.isEmpty
                  ? _defaultApiUrl
                  : _configuredApiUrl,
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
              headers: {
                'content-type': 'application/json',
                'authorization': 'Bearer $accessToken',
              },
            ),
          );

  final Dio _dio;

  @override
  Future<UserProfile> getProfile() async {
    final data = await _request(() => _dio.get<Map<String, dynamic>>('/v1/me'));
    return UserProfile.fromJson(data['user'] as Map<String, dynamic>);
  }

  @override
  Future<UserProfile> updateProfile(UserProfile profile) async {
    final data = await _request(
      () => _dio.patch<Map<String, dynamic>>(
        '/v1/me',
        data: {
          'displayName': profile.displayName,
          'bio': profile.bio,
          'departmentId': profile.departmentId,
          'discoverable': profile.discoverable,
          'scheduleVisibility': profile.scheduleVisibility,
        },
      ),
    );
    return UserProfile.fromJson(data['user'] as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> _request(
    Future<Response<Map<String, dynamic>>> Function() request,
  ) async {
    try {
      final response = await request();
      return response.data!;
    } on DioException catch (error) {
      final data = error.response?.data;
      if (data is Map && data['error'] is Map) {
        final message = (data['error'] as Map)['message'];
        if (message is String) throw ProfileFailure(message);
      }
      throw const ProfileFailure('请求失败，请确认本地 API 已启动');
    }
  }
}
