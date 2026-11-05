import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstudy/core/cache/client_cache.dart';
import 'package:fstudy/features/academic/academic_repository.dart';

class _MemoryCacheStorage implements CacheStorage {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => handler(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body) => ResponseBody.fromString(
  jsonEncode(body),
  200,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

Map<String, dynamic> _course(String id, String name) => {
  'id': id,
  'name': name,
  'teacher': null,
  'color': '#3559C7',
  'meetings': <dynamic>[],
};

Map<String, dynamic> _courses(List<Map<String, dynamic>> courses) => {
  'courses': courses,
};

DioAcademicRepository _repository(Dio dio, ClientCache cache) =>
    DioAcademicRepository(accessToken: 'token', dio: dio, cache: cache);

Dio _dio(_FakeAdapter adapter) => Dio(
  BaseOptions(
    baseUrl: 'https://api.test',
    headers: {'content-type': 'application/json'},
  ),
)..httpClientAdapter = adapter;

void main() {
  group('ClientCache', () {
    test(
      'persists entries across cache instances for the same account',
      () async {
        final storage = _MemoryCacheStorage();
        final now = DateTime.utc(2026, 1, 1, 8);
        final first = ClientCache(
          userId: 'user-1',
          storage: storage,
          now: () => now,
        );
        await first.write('GET /v1/courses', _courses([_course('c1', '课表')]));
        await pumpEventQueue();

        final second = ClientCache(
          userId: 'user-1',
          storage: storage,
          now: () => now,
        );
        final entry = await second.read('GET /v1/courses');

        expect(entry, isNotNull);
        expect(entry!.data['courses'][0]['name'], '课表');
        expect(
          second.isFresh('GET /v1/courses', const Duration(seconds: 30)),
          isTrue,
        );

        final otherUser = ClientCache(
          userId: 'user-2',
          storage: storage,
          now: () => now,
        );
        expect(await otherUser.read('GET /v1/courses'), isNull);
      },
    );

    test('invalidatePath only removes matching endpoint data', () async {
      final cache = ClientCache(
        userId: 'user-1',
        storage: _MemoryCacheStorage(),
      );
      await cache.write('GET /v1/courses', _courses([_course('c1', '课表')]));
      await cache.write('GET /v1/assignments', {'assignments': <dynamic>[]});

      await cache.invalidatePath('/v1/courses');

      expect(await cache.read('GET /v1/courses'), isNull);
      expect(await cache.read('GET /v1/assignments'), isNotNull);
    });
  });

  group('CachedApi stale-while-revalidate', () {
    test('serves the cache while refreshing it in the background', () async {
      var now = DateTime.utc(2026, 1, 1, 8);
      final storage = _MemoryCacheStorage();
      final cache = ClientCache(
        userId: 'user-1',
        storage: storage,
        now: () => now,
      );
      var calls = 0;
      final refresh = Completer<ResponseBody>();
      final repository = _repository(
        _dio(
          _FakeAdapter((options) {
            calls++;
            if (calls == 1) {
              return Future.value(_json(_courses([_course('c1', '旧课')])));
            }
            return refresh.future;
          }),
        ),
        cache,
      );

      final first = await repository.listCourses();
      expect(first.single.name, '旧课');

      var notifications = 0;
      repository.cacheChanges!.addListener(() => notifications++);
      now = now.add(const Duration(seconds: 31));

      final second = await repository.listCourses();
      expect(second.single.name, '旧课');
      await pumpEventQueue();
      expect(calls, 2);

      refresh.complete(_json(_courses([_course('c1', '新课')])));
      await pumpEventQueue();

      expect(notifications, greaterThan(0));
      final third = await repository.listCourses();
      expect(third.single.name, '新课');
      expect(calls, 2);
    });

    test('mutations invalidate the cached list', () async {
      final cache = ClientCache(
        userId: 'user-1',
        storage: _MemoryCacheStorage(),
      );
      var calls = 0;
      final repository = _repository(
        _dio(
          _FakeAdapter((options) {
            if (options.path == '/v1/courses' && options.method == 'GET') {
              calls++;
              return Future.value(
                _json(_courses([_course('c$calls', '课程$calls')])),
              );
            }
            return Future.value(_json(const <String, dynamic>{}));
          }),
        ),
        cache,
      );

      expect((await repository.listCourses()).single.name, '课程1');
      expect((await repository.listCourses()).single.name, '课程1');
      expect(calls, 1);

      await repository.createCourse(
        name: '新课程',
        teacher: null,
        meetings: const [],
      );

      expect((await repository.listCourses()).single.name, '课程2');
      expect(calls, 2);
    });

    test('an older background refresh cannot overwrite newer data', () async {
      var now = DateTime.utc(2026, 1, 1, 8);
      final cache = ClientCache(
        userId: 'user-1',
        storage: _MemoryCacheStorage(),
        now: () => now,
      );
      final oldRefresh = Completer<ResponseBody>();
      var gets = 0;
      final repository = _repository(
        _dio(
          _FakeAdapter((options) {
            if (options.method != 'GET') {
              return Future.value(_json(const <String, dynamic>{}));
            }
            gets++;
            if (gets == 1) {
              return Future.value(_json(_courses([_course('c1', '旧课')])));
            }
            if (gets == 2) return oldRefresh.future;
            return Future.value(_json(_courses([_course('c1', '新课')])));
          }),
        ),
        cache,
      );

      await repository.listCourses();
      now = now.add(const Duration(seconds: 31));
      final cached = await repository.listCourses();
      expect(cached.single.name, '旧课');
      await pumpEventQueue();
      expect(gets, 2);

      await repository.createCourse(
        name: '新课程',
        teacher: null,
        meetings: const [],
      );
      expect((await repository.listCourses()).single.name, '新课');
      expect(gets, 3);

      oldRefresh.complete(_json(_courses([_course('c1', '旧课')])));
      await pumpEventQueue();

      expect((await repository.listCourses()).single.name, '新课');
      expect(gets, 3);
    });

    test('a failed revalidation keeps cached data', () async {
      var now = DateTime.utc(2026, 1, 1, 8);
      final cache = ClientCache(
        userId: 'user-1',
        storage: _MemoryCacheStorage(),
        now: () => now,
      );
      var calls = 0;
      final repository = _repository(
        _dio(
          _FakeAdapter((options) {
            calls++;
            if (calls == 1) {
              return Future.value(_json(_courses([_course('c1', '旧课')])));
            }
            return Future<ResponseBody>.error(
              DioException.connectionError(
                requestOptions: options,
                reason: 'offline',
              ),
            );
          }),
        ),
        cache,
      );

      await repository.listCourses();
      now = now.add(const Duration(seconds: 31));

      final cached = await repository.listCourses();
      expect(cached.single.name, '旧课');
      await pumpEventQueue();
      expect((await repository.listCourses()).single.name, '旧课');
    });
  });
}
