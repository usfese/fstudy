import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

const _configuredApiUrl = String.fromEnvironment('API_BASE_URL');

String get _defaultApiUrl =>
    kIsWeb ? 'http://127.0.0.1:8787' : 'http://10.0.2.2:8787';

class AcademicFailure implements Exception {
  const AcademicFailure(this.message);
  final String message;
}

class CourseMeeting {
  const CourseMeeting({
    required this.weekday,
    required this.startMinute,
    required this.endMinute,
    required this.startWeek,
    required this.endWeek,
    required this.weekParity,
    this.campus,
    this.building,
    this.room,
  });

  factory CourseMeeting.fromJson(Map<String, dynamic> json) => CourseMeeting(
    weekday: json['weekday'] as int,
    startMinute: json['startMinute'] as int,
    endMinute: json['endMinute'] as int,
    startWeek: json['startWeek'] as int,
    endWeek: json['endWeek'] as int,
    weekParity: json['weekParity'] as String,
    campus: json['campus'] as String?,
    building: json['building'] as String?,
    room: json['room'] as String?,
  );

  final int weekday;
  final int startMinute;
  final int endMinute;
  final int startWeek;
  final int endWeek;
  final String weekParity;
  final String? campus;
  final String? building;
  final String? room;
}

class Course {
  const Course({
    required this.id,
    required this.name,
    required this.teacher,
    required this.color,
    required this.meetings,
  });

  factory Course.fromJson(Map<String, dynamic> json) => Course(
    id: json['id'] as String,
    name: json['name'] as String,
    teacher: json['teacher'] as String?,
    color: json['color'] as String,
    meetings: (json['meetings'] as List)
        .map((value) => CourseMeeting.fromJson(value as Map<String, dynamic>))
        .toList(),
  );

  final String id;
  final String name;
  final String? teacher;
  final String color;
  final List<CourseMeeting> meetings;
}

class Assignment {
  const Assignment({
    required this.id,
    required this.courseId,
    required this.title,
    required this.notes,
    required this.dueAt,
    required this.completedAt,
  });

  factory Assignment.fromJson(Map<String, dynamic> json) => Assignment(
    id: json['id'] as String,
    courseId: json['courseId'] as String?,
    title: json['title'] as String,
    notes: json['notes'] as String,
    dueAt: json['dueAt'] == null
        ? null
        : DateTime.parse(json['dueAt'] as String),
    completedAt: json['completedAt'] == null
        ? null
        : DateTime.parse(json['completedAt'] as String),
  );

  final String id;
  final String? courseId;
  final String title;
  final String notes;
  final DateTime? dueAt;
  final DateTime? completedAt;
}

abstract interface class AcademicRepository {
  Future<DateTime?> getSemesterStartDate();
  Future<void> setSemesterStartDate(DateTime? date);
  Future<List<Course>> listCourses();
  Future<void> createCourse({
    required String name,
    required String? teacher,
    required List<CourseMeeting> meetings,
  });
  Future<void> updateCourse({
    required String id,
    required String name,
    required String? teacher,
    required String color,
    required List<CourseMeeting> meetings,
  });
  Future<void> deleteCourse(String id);
  Future<void> clearCourses();
  Future<List<Assignment>> listAssignments();
  Future<void> createAssignment({
    required String title,
    required String notes,
    required String? courseId,
    required DateTime? dueAt,
  });
  Future<void> updateAssignment({
    required String id,
    required String title,
    required String notes,
    required String? courseId,
    required DateTime? dueAt,
  });
  Future<void> deleteAssignment(String id);
  Future<void> setAssignmentCompleted(String id, bool completed);
}

class DioAcademicRepository implements AcademicRepository {
  DioAcademicRepository({required String accessToken, Dio? dio})
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
  Future<DateTime?> getSemesterStartDate() async {
    final data = await _request(
      () => _dio.get<Map<String, dynamic>>('/v1/me/academic-settings'),
    );
    final value = data['semesterStartDate'];
    return value is String ? DateTime.parse(value) : null;
  }

  @override
  Future<void> setSemesterStartDate(DateTime? date) async {
    await _request(
      () => _dio.put<Map<String, dynamic>>(
        '/v1/me/academic-settings',
        data: {'semesterStartDate': date?.toIso8601String().split('T').first},
      ),
    );
  }

  @override
  Future<List<Course>> listCourses() async {
    final data = await _request(
      () => _dio.get<Map<String, dynamic>>('/v1/courses'),
    );
    return (data['courses'] as List)
        .map((value) => Course.fromJson(value as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> createCourse({
    required String name,
    required String? teacher,
    required List<CourseMeeting> meetings,
  }) async {
    await _request(
      () => _dio.post<Map<String, dynamic>>(
        '/v1/courses',
        data: {
          'name': name,
          'teacher': teacher,
          'color': '#3559C7',
          'meetings': meetings.map(_meetingJson).toList(),
        },
      ),
    );
  }

  @override
  Future<void> updateCourse({
    required String id,
    required String name,
    required String? teacher,
    required String color,
    required List<CourseMeeting> meetings,
  }) async {
    await _request(
      () => _dio.put<Map<String, dynamic>>(
        '/v1/courses/$id',
        data: {
          'name': name,
          'teacher': teacher,
          'color': color,
          'meetings': meetings.map(_meetingJson).toList(),
        },
      ),
    );
  }

  @override
  Future<void> deleteCourse(String id) async {
    await _request(() => _dio.delete<Map<String, dynamic>>('/v1/courses/$id'));
  }

  @override
  Future<void> clearCourses() async {
    await _request(() => _dio.delete<Map<String, dynamic>>('/v1/courses'));
  }

  Map<String, dynamic> _meetingJson(CourseMeeting meeting) => {
    'weekday': meeting.weekday,
    'startMinute': meeting.startMinute,
    'endMinute': meeting.endMinute,
    'startWeek': meeting.startWeek,
    'endWeek': meeting.endWeek,
    'weekParity': meeting.weekParity,
    'campus': meeting.campus,
    'building': meeting.building,
    'room': meeting.room,
  };

  @override
  Future<List<Assignment>> listAssignments() async {
    final data = await _request(
      () => _dio.get<Map<String, dynamic>>('/v1/assignments'),
    );
    return (data['assignments'] as List)
        .map((value) => Assignment.fromJson(value as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> createAssignment({
    required String title,
    required String notes,
    required String? courseId,
    required DateTime? dueAt,
  }) async {
    await _request(
      () => _dio.post<Map<String, dynamic>>(
        '/v1/assignments',
        data: {
          'title': title,
          'notes': notes,
          'courseId': courseId,
          'dueAt': dueAt?.toUtc().toIso8601String(),
        },
      ),
    );
  }

  @override
  Future<void> updateAssignment({
    required String id,
    required String title,
    required String notes,
    required String? courseId,
    required DateTime? dueAt,
  }) async {
    await _request(
      () => _dio.put<Map<String, dynamic>>(
        '/v1/assignments/$id',
        data: {
          'title': title,
          'notes': notes,
          'courseId': courseId,
          'dueAt': dueAt?.toUtc().toIso8601String(),
        },
      ),
    );
  }

  @override
  Future<void> deleteAssignment(String id) async {
    await _request(
      () => _dio.delete<Map<String, dynamic>>('/v1/assignments/$id'),
    );
  }

  @override
  Future<void> setAssignmentCompleted(String id, bool completed) async {
    await _request(
      () => _dio.patch<Map<String, dynamic>>(
        '/v1/assignments/$id/completion',
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
        if (message is String) throw AcademicFailure(message);
      }
      throw const AcademicFailure('请求失败，请确认本地 API 已启动');
    }
  }
}
