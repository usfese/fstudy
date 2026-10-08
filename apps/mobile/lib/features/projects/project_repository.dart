import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

const _configuredApiUrl = String.fromEnvironment('API_BASE_URL');
String get _defaultApiUrl =>
    kIsWeb ? 'http://127.0.0.1:8787' : 'http://10.0.2.2:8787';

class ProjectFailure implements Exception {
  const ProjectFailure(this.message);
  final String message;
}

class ProjectTag {
  const ProjectTag({
    required this.id,
    required this.category,
    required this.name,
  });
  factory ProjectTag.fromJson(Map<String, dynamic> json) => ProjectTag(
    id: json['id'] as String,
    category: json['category'] as String,
    name: json['name'] as String,
  );
  final String id;
  final String category;
  final String name;
}

class StudyProject {
  const StudyProject({
    required this.id,
    required this.ownerName,
    required this.title,
    required this.description,
    required this.status,
    required this.capacity,
    required this.memberCount,
    required this.ownedByMe,
    required this.myApplicationStatus,
    required this.tags,
  });
  factory StudyProject.fromJson(Map<String, dynamic> json) => StudyProject(
    id: json['id'] as String,
    ownerName: json['ownerName'] as String,
    title: json['title'] as String,
    description: json['description'] as String,
    status: json['status'] as String,
    capacity: json['capacity'] as int,
    memberCount: json['memberCount'] as int,
    ownedByMe: json['ownedByMe'] as bool,
    myApplicationStatus: json['myApplicationStatus'] as String?,
    tags: (json['tags'] as List)
        .map((tag) => ProjectTag.fromJson(tag as Map<String, dynamic>))
        .toList(),
  );
  final String id;
  final String ownerName;
  final String title;
  final String description;
  final String status;
  final int capacity;
  final int memberCount;
  final bool ownedByMe;
  final String? myApplicationStatus;
  final List<ProjectTag> tags;
}

class ProjectApplication {
  const ProjectApplication({
    required this.id,
    required this.projectTitle,
    required this.applicantName,
    required this.message,
    required this.status,
    required this.direction,
  });
  factory ProjectApplication.fromJson(Map<String, dynamic> json) =>
      ProjectApplication(
        id: json['id'] as String,
        projectTitle: json['projectTitle'] as String,
        applicantName: json['applicantName'] as String,
        message: json['message'] as String,
        status: json['status'] as String,
        direction: json['direction'] as String,
      );
  final String id;
  final String projectTitle;
  final String applicantName;
  final String message;
  final String status;
  final String direction;
}

abstract interface class ProjectRepository {
  Future<List<ProjectTag>> listTags();
  Future<List<StudyProject>> listProjects({String? status, String? tagId});
  Future<void> createProject({
    required String title,
    required String description,
    required int capacity,
    required List<String> tagIds,
  });
  Future<void> setProjectStatus(String id, String status);
  Future<void> apply(String projectId, String message);
  Future<List<ProjectApplication>> listApplications();
  Future<void> respond(String applicationId, String action);
}

class DioProjectRepository implements ProjectRepository {
  DioProjectRepository({required String accessToken, Dio? dio})
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
  Future<List<ProjectTag>> listTags() async {
    final data = await _get('/v1/tags');
    return (data['tags'] as List)
        .map((tag) => ProjectTag.fromJson(tag as Map<String, dynamic>))
        .where((tag) => tag.category == 'field' || tag.category == 'goal')
        .toList();
  }

  @override
  Future<List<StudyProject>> listProjects({
    String? status,
    String? tagId,
  }) async {
    final data = await _request(
      () => _dio.get<Map<String, dynamic>>(
        '/v1/projects',
        queryParameters: {'status': ?status, 'tagId': ?tagId},
      ),
    );
    return (data['projects'] as List)
        .map(
          (project) => StudyProject.fromJson(project as Map<String, dynamic>),
        )
        .toList();
  }

  @override
  Future<void> createProject({
    required String title,
    required String description,
    required int capacity,
    required List<String> tagIds,
  }) async => _void(
    () => _dio.post<Map<String, dynamic>>(
      '/v1/projects',
      data: {
        'title': title,
        'description': description,
        'capacity': capacity,
        'tagIds': tagIds,
      },
    ),
  );

  @override
  Future<void> setProjectStatus(String id, String status) async => _void(
    () => _dio.patch<Map<String, dynamic>>(
      '/v1/projects/$id/status',
      data: {'status': status},
    ),
  );

  @override
  Future<void> apply(String projectId, String message) async => _void(
    () => _dio.post<Map<String, dynamic>>(
      '/v1/projects/$projectId/applications',
      data: {'message': message},
    ),
  );

  @override
  Future<List<ProjectApplication>> listApplications() async {
    final data = await _get('/v1/project-applications');
    return (data['applications'] as List)
        .map(
          (item) => ProjectApplication.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  @override
  Future<void> respond(String applicationId, String action) async => _void(
    () => _dio.patch<Map<String, dynamic>>(
      '/v1/project-applications/$applicationId',
      data: {'action': action},
    ),
  );

  Future<Map<String, dynamic>> _get(String path) =>
      _request(() => _dio.get<Map<String, dynamic>>(path));
  Future<void> _void(
    Future<Response<Map<String, dynamic>>> Function() request,
  ) async {
    await _request(request);
  }

  Future<Map<String, dynamic>> _request(
    Future<Response<Map<String, dynamic>>> Function() request,
  ) async {
    try {
      return (await request()).data!;
    } on DioException catch (error) {
      final data = error.response?.data;
      if (data is Map && data['error'] is Map) {
        final message = (data['error'] as Map)['message'];
        if (message is String) throw ProjectFailure(message);
      }
      throw const ProjectFailure('请求失败，请确认本地 API 已启动');
    }
  }
}
