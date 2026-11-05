import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstudy/features/auth/auth_repository.dart';

class _MemoryAuthStorage implements AuthStorage {
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

ResponseBody _json(Object body, int status) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

DioAuthRepository _repository(
  _MemoryAuthStorage storage,
  _FakeAdapter adapter,
) {
  final dio = Dio(
    BaseOptions(
      baseUrl: 'https://api.test',
      headers: {'content-type': 'application/json'},
    ),
  )..httpClientAdapter = adapter;
  return DioAuthRepository(dio: dio, storage: storage);
}

Map<String, dynamic> _user(String displayName) => {
  'id': 'user-id',
  'username': 'student01',
  'displayName': displayName,
  'departmentId': 'computer',
};

void main() {
  group('DioAuthRepository session persistence', () {
    test('login stores both the token and a user snapshot', () async {
      final storage = _MemoryAuthStorage();
      final repository = _repository(
        storage,
        _FakeAdapter((options) async {
          expect(options.path, '/v1/auth/login');
          return _json({'accessToken': 'token-1', 'user': _user('测试同学')}, 200);
        }),
      );

      final session = await repository.login(
        username: 'student01',
        appPassword: 'correct-horse-battery',
      );

      expect(session.accessToken, 'token-1');
      expect(session.user.displayName, '测试同学');
      expect(storage.values['fstudy_access_token'], 'token-1');
      final cached = jsonDecode(
        storage.values['fstudy_access_user']!,
      ) as Map<String, dynamic>;
      expect(cached['displayName'], '测试同学');
      expect(cached['username'], 'student01');
    });

    test(
      'restoreSession keeps the cached login when the API is unreachable',
      () async {
        final storage = _MemoryAuthStorage()
          ..values['fstudy_access_token'] = 'token-1'
          ..values['fstudy_access_user'] = jsonEncode(_user('缓存同学'));
        final repository = _repository(
          storage,
          _FakeAdapter((options) async {
            throw DioException.connectionError(
              requestOptions: options,
              reason: 'offline during deploy',
            );
          }),
        );

        final session = await repository.restoreSession();

        expect(session, isNotNull);
        expect(session!.accessToken, 'token-1');
        expect(session.user.displayName, '缓存同学');
        expect(storage.values['fstudy_access_token'], 'token-1');
        expect(storage.values.containsKey('fstudy_access_user'), isTrue);
      },
    );

    test('restoreSession returns cached login before validation and clears it on 401', () async {
      final storage = _MemoryAuthStorage()
        ..values['fstudy_access_token'] = 'expired-token'
        ..values['fstudy_access_user'] = jsonEncode(_user('过期同学'));
      final repository = _repository(
        storage,
        _FakeAdapter(
          (options) async => _json({
            'error': {'code': 'invalid_session', 'message': '登录已失效'},
          }, 401),
        ),
      );
      final event = repository.sessionChanges.first;

      final session = await repository.restoreSession();

      expect(session, isNotNull);
      expect(session!.user.displayName, '过期同学');
      expect(await event, isNull);
      expect(storage.values, isEmpty);
    });

    test('restoreSession refreshes the cached user after validation', () async {
      final storage = _MemoryAuthStorage()
        ..values['fstudy_access_token'] = 'token-1'
        ..values['fstudy_access_user'] = jsonEncode(_user('旧名字'));
      final repository = _repository(
        storage,
        _FakeAdapter((options) async => _json({'user': _user('新名字')}, 200)),
      );
      final event = repository.sessionChanges.first;

      final session = await repository.restoreSession();

      expect(session!.user.displayName, '旧名字');
      final updated = await event;
      expect(updated!.user.displayName, '新名字');
      final cached = jsonDecode(
        storage.values['fstudy_access_user']!,
      ) as Map<String, dynamic>;
      expect(cached['displayName'], '新名字');
      expect(storage.values['fstudy_access_token'], 'token-1');
    });

    test('restoreSession does not wait for the validation request', () async {
      final storage = _MemoryAuthStorage()
        ..values['fstudy_access_token'] = 'token-1'
        ..values['fstudy_access_user'] = jsonEncode(_user('缓存同学'));
      final response = Completer<ResponseBody>();
      final repository = _repository(
        storage,
        _FakeAdapter((options) => response.future),
      );

      final session = await repository.restoreSession();

      expect(session!.user.displayName, '缓存同学');
      response.complete(_json({'user': _user('缓存同学')}, 200));
      await pumpEventQueue();
    });

    test('logout wins over an in-flight background validation', () async {
      final storage = _MemoryAuthStorage()
        ..values['fstudy_access_token'] = 'token-1'
        ..values['fstudy_access_user'] = jsonEncode(_user('缓存同学'));
      final me = Completer<ResponseBody>();
      final repository = _repository(
        storage,
        _FakeAdapter((options) {
          if (options.path == '/v1/me') return me.future;
          return Future.value(_json(const <String, dynamic>{}, 200));
        }),
      );

      final session = await repository.restoreSession();
      expect(session, isNotNull);
      await pumpEventQueue();

      await repository.logout();
      me.complete(_json({'user': _user('迟到的同学')}, 200));
      await pumpEventQueue();

      expect(storage.values, isEmpty);
    });

    test(
      'restoreSession does not call the API when no token is stored',
      () async {
        final storage = _MemoryAuthStorage();
        var called = false;
        final repository = _repository(
          storage,
          _FakeAdapter((options) async {
            called = true;
            return _json({'user': _user('不应该出现')}, 200);
          }),
        );

        final session = await repository.restoreSession();

        expect(session, isNull);
        expect(called, isFalse);
      },
    );

    test(
      'logout clears the local session even when the server is down',
      () async {
        final storage = _MemoryAuthStorage()
          ..values['fstudy_access_token'] = 'token-1'
          ..values['fstudy_access_user'] = jsonEncode(_user('测试同学'));
        final repository = _repository(
          storage,
          _FakeAdapter((options) async {
            throw DioException.connectionError(
              requestOptions: options,
              reason: 'server unavailable',
            );
          }),
        );

        await repository.logout();

        expect(storage.values, isEmpty);
      },
    );
  });
}
