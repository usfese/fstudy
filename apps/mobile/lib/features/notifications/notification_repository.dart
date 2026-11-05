import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/cache/cached_api.dart';
import '../../core/cache/client_cache.dart';

const _configuredApiUrl = String.fromEnvironment('API_BASE_URL');

String get _defaultApiUrl =>
    kIsWeb ? 'http://127.0.0.1:8787' : 'http://10.0.2.2:8787';

class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.targetPath,
    required this.createdAt,
    required this.readAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: json['id'] as String,
        kind: json['kind'] as String,
        title: json['title'] as String,
        body: json['body'] as String,
        targetPath: json['targetPath'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        readAt: json['readAt'] == null
            ? null
            : DateTime.parse(json['readAt'] as String),
      );

  final String id;
  final String kind;
  final String title;
  final String body;
  final String targetPath;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isRead => readAt != null;
}

class NotificationOverview {
  const NotificationOverview({
    required this.unreadCount,
    required this.notifications,
  });

  final int unreadCount;
  final List<AppNotification> notifications;
}

class NotificationFailure implements Exception {
  const NotificationFailure(this.message);
  final String message;
}

abstract interface class NotificationRepository {
  Future<NotificationOverview> list();
  Future<NotificationOverview> markRead({String? id});
}

class DioNotificationRepository
    with CachedApi
    implements NotificationRepository {
  DioNotificationRepository({required String accessToken, Dio? dio, this.cache})
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
  final ClientCache? cache;

  @override
  Future<NotificationOverview> list() async {
    final data = await cachedGet(
      '/v1/notifications',
      () => _request(() => _dio.get<Map<String, dynamic>>('/v1/notifications')),
      ttl: const Duration(seconds: 10),
    );
    return _overview(data);
  }

  @override
  Future<NotificationOverview> markRead({String? id}) async {
    final data = await _request(
      () => _dio.post<Map<String, dynamic>>(
        '/v1/notifications/read',
        data: {'id': ?id},
      ),
    );
    await storeCached('/v1/notifications', data);
    return _overview(data);
  }

  NotificationOverview _overview(Map<String, dynamic> data) =>
      NotificationOverview(
        unreadCount: data['unreadCount'] as int,
        notifications: (data['notifications'] as List)
            .map(
              (item) => AppNotification.fromJson(item as Map<String, dynamic>),
            )
            .toList(),
      );

  Future<Map<String, dynamic>> _request(
    Future<Response<Map<String, dynamic>>> Function() call,
  ) async {
    try {
      final response = await call();
      return response.data!;
    } on DioException catch (error) {
      final body = error.response?.data;
      if (body is Map && body['error'] is Map) {
        final message = (body['error'] as Map)['message'];
        if (message is String) throw NotificationFailure(message);
      }
      throw const NotificationFailure('通知暂时无法加载，请稍后重试');
    }
  }
}
