import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

const _configuredApiUrl = String.fromEnvironment('API_BASE_URL');

String get _defaultApiUrl =>
    kIsWeb ? 'http://127.0.0.1:8787' : 'http://10.0.2.2:8787';

class SocialFailure implements Exception {
  const SocialFailure(this.message);
  final String message;
}

class SocialTag {
  const SocialTag({
    required this.id,
    required this.category,
    required this.name,
    this.isCore = false,
    this.visible = true,
    this.usedForRecommendation = true,
    this.common = false,
  });

  factory SocialTag.fromJson(Map<String, dynamic> json) => SocialTag(
    id: json['id'] as String,
    category: json['category'] as String,
    name: json['name'] as String,
    isCore: json['isCore'] as bool? ?? false,
    visible: json['visible'] as bool? ?? true,
    usedForRecommendation: json['usedForRecommendation'] as bool? ?? true,
    common: json['common'] as bool? ?? false,
  );

  final String id;
  final String category;
  final String name;
  final bool isCore;
  final bool visible;
  final bool usedForRecommendation;
  final bool common;

  SocialTag copyWith({
    bool? isCore,
    bool? visible,
    bool? usedForRecommendation,
  }) => SocialTag(
    id: id,
    category: category,
    name: name,
    isCore: isCore ?? this.isCore,
    visible: visible ?? this.visible,
    usedForRecommendation: usedForRecommendation ?? this.usedForRecommendation,
    common: common,
  );
}

class DiscoveredUser {
  const DiscoveredUser({
    required this.id,
    required this.displayName,
    required this.departmentId,
    required this.bio,
    required this.sameDepartment,
    required this.commonTagCount,
    required this.tags,
    required this.relationship,
  });

  factory DiscoveredUser.fromJson(Map<String, dynamic> json) => DiscoveredUser(
    id: json['id'] as String,
    displayName: json['displayName'] as String,
    departmentId: json['departmentId'] as String?,
    bio: json['bio'] as String,
    sameDepartment: json['sameDepartment'] as bool,
    commonTagCount: json['commonTagCount'] as int,
    tags: (json['tags'] as List)
        .map((tag) => SocialTag.fromJson(tag as Map<String, dynamic>))
        .toList(),
    relationship: json['relationship'] as String? ?? 'none',
  );

  final String id;
  final String displayName;
  final String? departmentId;
  final String bio;
  final bool sameDepartment;
  final int commonTagCount;
  final List<SocialTag> tags;
  final String relationship;
}

class FriendRequestItem {
  const FriendRequestItem({
    required this.id,
    required this.userId,
    required this.displayName,
    required this.departmentId,
  });

  factory FriendRequestItem.fromJson(Map<String, dynamic> json) =>
      FriendRequestItem(
        id: json['id'] as String,
        userId: json['userId'] as String,
        displayName: json['displayName'] as String,
        departmentId: json['departmentId'] as String?,
      );

  final String id;
  final String userId;
  final String displayName;
  final String? departmentId;
}

class FriendItem {
  const FriendItem({
    required this.id,
    required this.displayName,
    required this.departmentId,
    required this.bio,
  });

  factory FriendItem.fromJson(Map<String, dynamic> json) => FriendItem(
    id: json['id'] as String,
    displayName: json['displayName'] as String,
    departmentId: json['departmentId'] as String?,
    bio: json['bio'] as String,
  );

  final String id;
  final String displayName;
  final String? departmentId;
  final String bio;
}

class FriendsOverview {
  const FriendsOverview({
    required this.friends,
    required this.incoming,
    required this.outgoing,
  });

  final List<FriendItem> friends;
  final List<FriendRequestItem> incoming;
  final List<FriendRequestItem> outgoing;
}

class FreeSlot {
  const FreeSlot({required this.startMinute, required this.endMinute});
  factory FreeSlot.fromJson(Map<String, dynamic> json) => FreeSlot(
    startMinute: json['startMinute'] as int,
    endMinute: json['endMinute'] as int,
  );
  final int startMinute;
  final int endMinute;
}

class AvailabilityInvite {
  const AvailabilityInvite({
    required this.id,
    required this.direction,
    required this.userId,
    required this.displayName,
    required this.startsAt,
    required this.endsAt,
    required this.title,
    required this.status,
  });

  factory AvailabilityInvite.fromJson(Map<String, dynamic> json) =>
      AvailabilityInvite(
        id: json['id'] as String,
        direction: json['direction'] as String,
        userId: json['userId'] as String,
        displayName: json['displayName'] as String,
        startsAt: DateTime.parse(json['startsAt'] as String),
        endsAt: DateTime.parse(json['endsAt'] as String),
        title: json['title'] as String,
        status: json['status'] as String,
      );

  final String id;
  final String direction;
  final String userId;
  final String displayName;
  final DateTime startsAt;
  final DateTime endsAt;
  final String title;
  final String status;
}

abstract interface class SocialRepository {
  Future<List<SocialTag>> listAvailableTags();
  Future<List<SocialTag>> listMyTags();
  Future<SocialTag> createTag({required String name, required String category});
  Future<void> replaceMyTags(List<SocialTag> tags);
  Future<List<DiscoveredUser>> discoverUsers();
  Future<void> sendFriendRequest(String targetUserId);
  Future<FriendsOverview> listFriends();
  Future<void> respondToFriendRequest(String requestId, String action);
  Future<List<FreeSlot>> queryAvailability({
    required String friendId,
    required DateTime date,
    required int weekNumber,
    required int dayStartMinute,
    required int dayEndMinute,
  });
  Future<List<AvailabilityInvite>> listAvailabilityInvites();
  Future<void> createAvailabilityInvite({
    required String friendId,
    required DateTime startsAt,
    required DateTime endsAt,
    required String title,
  });
  Future<void> respondToAvailabilityInvite(String inviteId, String action);
}

class DioSocialRepository implements SocialRepository {
  DioSocialRepository({required String accessToken, Dio? dio})
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
  Future<List<SocialTag>> listAvailableTags() async =>
      _tags(await _get('/v1/tags'));

  @override
  Future<List<SocialTag>> listMyTags() async =>
      _tags(await _get('/v1/me/tags'));

  @override
  Future<SocialTag> createTag({
    required String name,
    required String category,
  }) async {
    final data = await _request(
      () => _dio.post<Map<String, dynamic>>(
        '/v1/tags',
        data: {'name': name, 'category': category},
      ),
    );
    return SocialTag.fromJson(data['tag'] as Map<String, dynamic>);
  }

  @override
  Future<void> replaceMyTags(List<SocialTag> tags) async {
    await _request(
      () => _dio.put<Map<String, dynamic>>(
        '/v1/me/tags',
        data: {
          'tags': tags
              .map(
                (tag) => {
                  'tagId': tag.id,
                  'isCore': tag.isCore,
                  'visible': tag.visible,
                  'usedForRecommendation': tag.usedForRecommendation,
                },
              )
              .toList(),
        },
      ),
    );
  }

  @override
  Future<List<DiscoveredUser>> discoverUsers() async {
    final data = await _get('/v1/discover');
    return (data['users'] as List)
        .map((user) => DiscoveredUser.fromJson(user as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> sendFriendRequest(String targetUserId) async {
    await _request(
      () => _dio.post<Map<String, dynamic>>(
        '/v1/friend-requests',
        data: {'targetUserId': targetUserId},
      ),
    );
  }

  @override
  Future<FriendsOverview> listFriends() async {
    final data = await _get('/v1/friends');
    return FriendsOverview(
      friends: (data['friends'] as List)
          .map((value) => FriendItem.fromJson(value as Map<String, dynamic>))
          .toList(),
      incoming: (data['incoming'] as List)
          .map(
            (value) =>
                FriendRequestItem.fromJson(value as Map<String, dynamic>),
          )
          .toList(),
      outgoing: (data['outgoing'] as List)
          .map(
            (value) =>
                FriendRequestItem.fromJson(value as Map<String, dynamic>),
          )
          .toList(),
    );
  }

  @override
  Future<void> respondToFriendRequest(String requestId, String action) async {
    await _request(
      () => _dio.patch<Map<String, dynamic>>(
        '/v1/friend-requests/$requestId',
        data: {'action': action},
      ),
    );
  }

  @override
  Future<List<FreeSlot>> queryAvailability({
    required String friendId,
    required DateTime date,
    required int weekNumber,
    required int dayStartMinute,
    required int dayEndMinute,
  }) async {
    final data = await _request(
      () => _dio.get<Map<String, dynamic>>(
        '/v1/availability',
        queryParameters: {
          'friendId': friendId,
          'date':
              '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
          'weekNumber': weekNumber,
          'dayStartMinute': dayStartMinute,
          'dayEndMinute': dayEndMinute,
          'timezoneOffsetMinutes': date.timeZoneOffset.inMinutes,
        },
      ),
    );
    return (data['freeSlots'] as List)
        .map((slot) => FreeSlot.fromJson(slot as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<AvailabilityInvite>> listAvailabilityInvites() async {
    final data = await _get('/v1/availability-invites');
    return (data['invites'] as List)
        .map(
          (invite) =>
              AvailabilityInvite.fromJson(invite as Map<String, dynamic>),
        )
        .toList();
  }

  @override
  Future<void> createAvailabilityInvite({
    required String friendId,
    required DateTime startsAt,
    required DateTime endsAt,
    required String title,
  }) async {
    await _request(
      () => _dio.post<Map<String, dynamic>>(
        '/v1/availability-invites',
        data: {
          'friendId': friendId,
          'startsAt': startsAt.toUtc().toIso8601String(),
          'endsAt': endsAt.toUtc().toIso8601String(),
          'title': title,
        },
      ),
    );
  }

  @override
  Future<void> respondToAvailabilityInvite(
    String inviteId,
    String action,
  ) async {
    await _request(
      () => _dio.patch<Map<String, dynamic>>(
        '/v1/availability-invites/$inviteId',
        data: {'action': action},
      ),
    );
  }

  List<SocialTag> _tags(Map<String, dynamic> data) => (data['tags'] as List)
      .map((tag) => SocialTag.fromJson(tag as Map<String, dynamic>))
      .toList();

  Future<Map<String, dynamic>> _get(String path) =>
      _request(() => _dio.get<Map<String, dynamic>>(path));

  Future<Map<String, dynamic>> _request(
    Future<Response<Map<String, dynamic>>> Function() request,
  ) async {
    try {
      return (await request()).data!;
    } on DioException catch (error) {
      final data = error.response?.data;
      if (data is Map && data['error'] is Map) {
        final message = (data['error'] as Map)['message'];
        if (message is String) throw SocialFailure(message);
      }
      throw const SocialFailure('请求失败，请确认本地 API 已启动');
    }
  }
}
