import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

const _configuredApiUrl = String.fromEnvironment('API_BASE_URL');
String get _defaultApiUrl =>
    kIsWeb ? 'http://127.0.0.1:8787' : 'http://10.0.2.2:8787';

class ForumFailure implements Exception {
  const ForumFailure(this.message);
  final String message;
}

class ForumPost {
  const ForumPost({
    required this.id,
    required this.authorName,
    required this.category,
    required this.title,
    required this.body,
    required this.replyCount,
  });

  factory ForumPost.fromJson(Map<String, dynamic> json) => ForumPost(
    id: json['id'] as String,
    authorName: json['authorName'] as String,
    category: json['category'] as String,
    title: json['title'] as String,
    body: json['body'] as String,
    replyCount: json['replyCount'] as int,
  );

  final String id;
  final String authorName;
  final String category;
  final String title;
  final String body;
  final int replyCount;
}

class ForumReply {
  const ForumReply({
    required this.id,
    required this.authorName,
    required this.body,
  });

  factory ForumReply.fromJson(Map<String, dynamic> json) => ForumReply(
    id: json['id'] as String,
    authorName: json['authorName'] as String,
    body: json['body'] as String,
  );

  final String id;
  final String authorName;
  final String body;
}

class ForumThread {
  const ForumThread({required this.post, required this.replies});
  final ForumPost post;
  final List<ForumReply> replies;
}

abstract interface class ForumRepository {
  Future<List<ForumPost>> listPosts({String? category});
  Future<void> createPost({
    required String category,
    required String title,
    required String body,
  });
  Future<ForumThread> getThread(String postId);
  Future<void> createReply(String postId, String body);
}

class DioForumRepository implements ForumRepository {
  DioForumRepository({required String accessToken, Dio? dio})
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
  Future<List<ForumPost>> listPosts({String? category}) async {
    final data = await _request(
      () => _dio.get<Map<String, dynamic>>(
        '/v1/forum/posts',
        queryParameters: {'category': ?category},
      ),
    );
    return (data['posts'] as List)
        .map((post) => ForumPost.fromJson(post as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> createPost({
    required String category,
    required String title,
    required String body,
  }) async => _void(
    () => _dio.post<Map<String, dynamic>>(
      '/v1/forum/posts',
      data: {'category': category, 'title': title, 'body': body},
    ),
  );

  @override
  Future<ForumThread> getThread(String postId) async {
    final data = await _request(
      () => _dio.get<Map<String, dynamic>>('/v1/forum/posts/$postId'),
    );
    return ForumThread(
      post: ForumPost.fromJson(data['post'] as Map<String, dynamic>),
      replies: (data['replies'] as List)
          .map((reply) => ForumReply.fromJson(reply as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  Future<void> createReply(String postId, String body) async => _void(
    () => _dio.post<Map<String, dynamic>>(
      '/v1/forum/posts/$postId/replies',
      data: {'body': body},
    ),
  );

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
        if (message is String) throw ForumFailure(message);
      }
      throw const ForumFailure('请求失败，请确认本地 API 已启动');
    }
  }
}
