import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

const _configuredApiUrl = String.fromEnvironment('API_BASE_URL');

String get _defaultApiUrl =>
    kIsWeb ? 'http://127.0.0.1:8787' : 'http://10.0.2.2:8787';

class PlanFailure implements Exception {
  const PlanFailure(this.message);
  final String message;
}

class Plan {
  const Plan({
    required this.id,
    required this.title,
    required this.notes,
    required this.startsAt,
    required this.endsAt,
    required this.reminderMinutes,
    required this.completedAt,
  });

  factory Plan.fromJson(Map<String, dynamic> json) => Plan(
    id: json['id'] as String,
    title: json['title'] as String,
    notes: json['notes'] as String,
    startsAt: DateTime.parse(json['startsAt'] as String),
    endsAt: DateTime.parse(json['endsAt'] as String),
    reminderMinutes: json['reminderMinutes'] as int?,
    completedAt: json['completedAt'] == null
        ? null
        : DateTime.parse(json['completedAt'] as String),
  );

  final String id;
  final String title;
  final String notes;
  final DateTime startsAt;
  final DateTime endsAt;
  final int? reminderMinutes;
  final DateTime? completedAt;
}

abstract interface class PlanRepository {
  Future<List<Plan>> listPlans();
  Future<void> createPlan({
    required String title,
    required String notes,
    required DateTime startsAt,
    required DateTime endsAt,
    required int? reminderMinutes,
  });
  Future<void> setPlanCompleted(String id, bool completed);
}

class DioPlanRepository implements PlanRepository {
  DioPlanRepository({required String accessToken, Dio? dio})
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
  Future<List<Plan>> listPlans() async {
    final data = await _request(
      () => _dio.get<Map<String, dynamic>>('/v1/plans'),
    );
    return (data['plans'] as List)
        .map((value) => Plan.fromJson(value as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> createPlan({
    required String title,
    required String notes,
    required DateTime startsAt,
    required DateTime endsAt,
    required int? reminderMinutes,
  }) async {
    await _request(
      () => _dio.post<Map<String, dynamic>>(
        '/v1/plans',
        data: {
          'title': title,
          'notes': notes,
          'startsAt': startsAt.toUtc().toIso8601String(),
          'endsAt': endsAt.toUtc().toIso8601String(),
          'reminderMinutes': reminderMinutes,
        },
      ),
    );
  }

  @override
  Future<void> setPlanCompleted(String id, bool completed) async {
    await _request(
      () => _dio.patch<Map<String, dynamic>>(
        '/v1/plans/$id/completion',
        data: {'completed': completed},
      ),
    );
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
        if (message is String) throw PlanFailure(message);
      }
      throw const PlanFailure('请求失败，请确认本地 API 已启动');
    }
  }
}
