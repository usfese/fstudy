import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstudy/app.dart';
import 'package:fstudy/features/auth/auth_repository.dart';
import 'package:fstudy/features/academic/academic_repository.dart';
import 'package:fstudy/features/community/forum_repository.dart';
import 'package:fstudy/features/plans/plan_repository.dart';
import 'package:fstudy/features/profile/profile_repository.dart';
import 'package:fstudy/features/projects/project_repository.dart';
import 'package:fstudy/features/notifications/notification_repository.dart';
import 'package:fstudy/features/social/social_repository.dart';

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.session});

  final AuthSession? session;
  bool loggedOut = false;
  bool casStarted = false;

  @override
  Future<AuthSession?> restoreSession() async => session;

  @override
  Future<AuthSession> login({
    required String username,
    required String appPassword,
  }) {
    throw UnimplementedError();
  }

  String? registeredUsername;
  String? registeredEmail;
  String? registeredInviteCode;

  @override
  Future<AuthSession> register({
    required String username,
    required String email,
    required String appPassword,
    required String? departmentId,
    required String inviteCode,
  }) async {
    registeredUsername = username;
    registeredEmail = email;
    registeredInviteCode = inviteCode;
    return session ?? testSession;
  }

  @override
  Future<void> startBrowserCas() async {
    casStarted = true;
  }

  @override
  Future<AuthSession> completeBrowserCas({
    required String code,
    required String state,
    String? displayName,
    String? appPassword,
    String? departmentId,
  }) async => session ?? testSession;

  // [2026-10-14 已停用] 验证码 / 学校密码验证相关代码，保留以便日后恢复，勿直接启用：
  // @override
  // Future<CasPasswordChallenge> beginCasPasswordChallenge(
  // String studentId,
  // ) async => const CasPasswordChallenge(
  // id: 'test-challenge',
  // captchaImage: 'data:image/png;base64,AA==',
  // );
  //
  // @override
  // Future<CasPasswordChallenge> refreshCasPasswordChallenge({
  // required String challengeId,
  // required String studentId,
  // }) async => const CasPasswordChallenge(
  // id: 'refreshed-challenge',
  // captchaImage: 'data:image/png;base64,AA==',
  // );

  // @override
  // Future<AuthSession> verifyCasPasswordChallenge({
  // required String challengeId,
  // required String studentId,
  // required String schoolPassword,
  // required String? captcha,
  // required String displayName,
  // required String appPassword,
  // }) async => session ?? testSession;

  @override
  Future<void> logout() async => loggedOut = true;
}

class FakeAcademicRepository implements AcademicRepository {
  final List<Course> courses = [];
  final List<Assignment> assignments = [];
  DateTime? semesterStartDate;

  @override
  Future<DateTime?> getSemesterStartDate() async => semesterStartDate;

  @override
  Future<void> setSemesterStartDate(DateTime? date) async {
    semesterStartDate = date;
  }

  @override
  Future<List<Course>> listCourses() async => courses;

  @override
  Future<void> createCourse({
    required String name,
    required String? teacher,
    required CourseMeeting meeting,
  }) async {
    courses.add(
      Course(
        id: 'course-${courses.length}',
        name: name,
        teacher: teacher,
        color: '#3559C7',
        meetings: [meeting],
      ),
    );
  }

  @override
  Future<List<Assignment>> listAssignments() async => assignments;

  @override
  Future<void> createAssignment({
    required String title,
    required String notes,
    required String? courseId,
    required DateTime? dueAt,
  }) async {
    assignments.add(
      Assignment(
        id: 'assignment-${assignments.length}',
        courseId: courseId,
        title: title,
        notes: notes,
        dueAt: dueAt,
        completedAt: null,
      ),
    );
  }

  @override
  Future<void> setAssignmentCompleted(String id, bool completed) async {
    final index = assignments.indexWhere((assignment) => assignment.id == id);
    final assignment = assignments[index];
    assignments[index] = Assignment(
      id: assignment.id,
      courseId: assignment.courseId,
      title: assignment.title,
      notes: assignment.notes,
      dueAt: assignment.dueAt,
      completedAt: completed ? DateTime(2026, 10, 8) : null,
    );
  }
}

class FakePlanRepository implements PlanRepository {
  final List<Plan> plans = [];

  @override
  Future<List<Plan>> listPlans() async => plans;

  @override
  Future<void> createPlan({
    required String title,
    required String notes,
    required DateTime startsAt,
    required DateTime endsAt,
    required int? reminderMinutes,
  }) async {
    plans.add(
      Plan(
        id: 'plan-${plans.length}',
        title: title,
        notes: notes,
        startsAt: startsAt,
        endsAt: endsAt,
        reminderMinutes: reminderMinutes,
        completedAt: null,
      ),
    );
  }

  @override
  Future<void> setPlanCompleted(String id, bool completed) async {
    final index = plans.indexWhere((plan) => plan.id == id);
    final plan = plans[index];
    plans[index] = Plan(
      id: plan.id,
      title: plan.title,
      notes: plan.notes,
      startsAt: plan.startsAt,
      endsAt: plan.endsAt,
      reminderMinutes: plan.reminderMinutes,
      completedAt: completed ? DateTime(2026, 10, 8) : null,
    );
  }
}

class FakeProfileRepository implements ProfileRepository {
  UserProfile profile = const UserProfile(
    displayName: '测试同学',
    bio: '',
    departmentId: 'computer',
    discoverable: false,
    scheduleVisibility: 'busy_only',
  );

  @override
  Future<UserProfile> getProfile() async => profile;

  @override
  Future<UserProfile> updateProfile(UserProfile value) async {
    profile = value;
    return profile;
  }

  int inviteRemaining = 5;

  @override
  Future<InviteOverview> getInvites() async =>
      InviteOverview(remainingThisMonth: inviteRemaining, quota: 5);

  @override
  Future<IssuedInvite> createInvite() async {
    inviteRemaining -= 1;
    return IssuedInvite(
      code: 'ABCD-EFGH-JKMN',
      remainingThisMonth: inviteRemaining,
    );
  }
}

class FakeSocialRepository implements SocialRepository {
  final List<SocialTag> availableTags = [
    const SocialTag(
      id: 'interest-photography',
      category: 'interest',
      name: '摄影',
    ),
    const SocialTag(id: 'field-ai', category: 'field', name: '人工智能'),
    const SocialTag(id: 'goal-study', category: 'goal', name: '找学习搭子'),
  ];
  List<SocialTag> myTags = [];
  List<DiscoveredUser> users = [];
  FriendsOverview overview = const FriendsOverview(
    friends: [],
    incoming: [],
    outgoing: [],
  );
  List<FreeSlot> freeSlots = const [];
  List<AvailabilityInvite> invites = [];

  @override
  Future<List<SocialTag>> listAvailableTags() async => availableTags;

  @override
  Future<List<SocialTag>> listMyTags() async => myTags;

  @override
  Future<SocialTag> createTag({
    required String name,
    required String category,
  }) async {
    for (final tag in availableTags) {
      if (tag.category == category &&
          tag.name.toLowerCase() == name.toLowerCase()) {
        return tag;
      }
    }
    final tag = SocialTag(
      id: '$category-${availableTags.length}',
      category: category,
      name: name,
    );
    availableTags.add(tag);
    return tag;
  }

  @override
  Future<void> replaceMyTags(List<SocialTag> tags) async {
    myTags = List.of(tags);
  }

  @override
  Future<List<DiscoveredUser>> discoverUsers() async => users;

  @override
  Future<void> sendFriendRequest(String targetUserId) async {
    final index = users.indexWhere((user) => user.id == targetUserId);
    final user = users[index];
    users[index] = DiscoveredUser(
      id: user.id,
      displayName: user.displayName,
      departmentId: user.departmentId,
      bio: user.bio,
      sameDepartment: user.sameDepartment,
      commonTagCount: user.commonTagCount,
      tags: user.tags,
      relationship: 'outgoing',
    );
  }

  @override
  Future<FriendsOverview> listFriends() async => overview;

  @override
  Future<void> respondToFriendRequest(String requestId, String action) async {
    final request = overview.incoming.firstWhere(
      (item) => item.id == requestId,
    );
    overview = FriendsOverview(
      friends: action == 'accept'
          ? [
              ...overview.friends,
              FriendItem(
                id: request.userId,
                displayName: request.displayName,
                departmentId: request.departmentId,
                bio: '',
              ),
            ]
          : overview.friends,
      incoming: overview.incoming
          .where((item) => item.id != requestId)
          .toList(),
      outgoing: overview.outgoing,
    );
  }

  @override
  Future<List<FreeSlot>> queryAvailability({
    required String friendId,
    required DateTime date,
    required int weekNumber,
    required int dayStartMinute,
    required int dayEndMinute,
  }) async => freeSlots;

  @override
  Future<List<AvailabilityInvite>> listAvailabilityInvites() async => invites;

  @override
  Future<void> createAvailabilityInvite({
    required String friendId,
    required DateTime startsAt,
    required DateTime endsAt,
    required String title,
  }) async {
    invites = [
      ...invites,
      AvailabilityInvite(
        id: 'invite-${invites.length}',
        direction: 'outgoing',
        userId: friendId,
        displayName: '乙同学',
        startsAt: startsAt,
        endsAt: endsAt,
        title: title,
        status: 'pending',
      ),
    ];
  }

  @override
  Future<void> respondToAvailabilityInvite(
    String inviteId,
    String action,
  ) async {
    invites = invites
        .map(
          (invite) => invite.id != inviteId
              ? invite
              : AvailabilityInvite(
                  id: invite.id,
                  direction: invite.direction,
                  userId: invite.userId,
                  displayName: invite.displayName,
                  startsAt: invite.startsAt,
                  endsAt: invite.endsAt,
                  title: invite.title,
                  status: action == 'accept'
                      ? 'accepted'
                      : action == 'reject'
                      ? 'rejected'
                      : 'canceled',
                ),
        )
        .toList();
  }
}

class FakeProjectRepository implements ProjectRepository {
  final List<ProjectTag> tags = const [
    ProjectTag(id: 'field-ai', category: 'field', name: '人工智能'),
    ProjectTag(id: 'goal-project', category: 'goal', name: '找项目队友'),
  ];
  List<StudyProject> projects = [];
  List<ProjectApplication> applications = [];

  @override
  Future<List<ProjectTag>> listTags() async => tags;

  @override
  Future<List<StudyProject>> listProjects({
    String? status,
    String? tagId,
  }) async => projects
      .where(
        (project) =>
            (status == null || project.status == status) &&
            (tagId == null || project.tags.any((tag) => tag.id == tagId)),
      )
      .toList();

  @override
  Future<void> createProject({
    required String title,
    required String description,
    required int capacity,
    required List<String> tagIds,
  }) async {
    projects = [
      StudyProject(
        id: 'project-${projects.length}',
        ownerName: '测试同学',
        title: title,
        description: description,
        status: 'recruiting',
        capacity: capacity,
        memberCount: 1,
        ownedByMe: true,
        myApplicationStatus: null,
        tags: tags.where((tag) => tagIds.contains(tag.id)).toList(),
      ),
      ...projects,
    ];
  }

  @override
  Future<void> setProjectStatus(String id, String status) async {
    projects = projects
        .map(
          (project) => project.id != id
              ? project
              : StudyProject(
                  id: project.id,
                  ownerName: project.ownerName,
                  title: project.title,
                  description: project.description,
                  status: status,
                  capacity: project.capacity,
                  memberCount: project.memberCount,
                  ownedByMe: project.ownedByMe,
                  myApplicationStatus: project.myApplicationStatus,
                  tags: project.tags,
                ),
        )
        .toList();
  }

  @override
  Future<void> apply(String projectId, String message) async {
    projects = projects
        .map(
          (project) => project.id != projectId
              ? project
              : StudyProject(
                  id: project.id,
                  ownerName: project.ownerName,
                  title: project.title,
                  description: project.description,
                  status: project.status,
                  capacity: project.capacity,
                  memberCount: project.memberCount,
                  ownedByMe: project.ownedByMe,
                  myApplicationStatus: 'pending',
                  tags: project.tags,
                ),
        )
        .toList();
    applications = [
      ...applications,
      ProjectApplication(
        id: 'application-${applications.length}',
        projectTitle: projects
            .firstWhere((project) => project.id == projectId)
            .title,
        applicantName: '测试同学',
        message: message,
        status: 'pending',
        direction: 'outgoing',
      ),
    ];
  }

  @override
  Future<List<ProjectApplication>> listApplications() async => applications;

  @override
  Future<void> respond(String applicationId, String action) async {
    applications = applications
        .map(
          (application) => application.id != applicationId
              ? application
              : ProjectApplication(
                  id: application.id,
                  projectTitle: application.projectTitle,
                  applicantName: application.applicantName,
                  message: application.message,
                  status: action == 'accept'
                      ? 'accepted'
                      : action == 'reject'
                      ? 'rejected'
                      : 'withdrawn',
                  direction: application.direction,
                ),
        )
        .toList();
    if (action == 'accept') {
      projects = projects
          .map(
            (project) =>
                project.title !=
                    applications
                        .firstWhere(
                          (application) => application.id == applicationId,
                        )
                        .projectTitle
                ? project
                : StudyProject(
                    id: project.id,
                    ownerName: project.ownerName,
                    title: project.title,
                    description: project.description,
                    status: project.status,
                    capacity: project.capacity,
                    memberCount: project.memberCount + 1,
                    ownedByMe: project.ownedByMe,
                    myApplicationStatus: project.myApplicationStatus,
                    tags: project.tags,
                  ),
          )
          .toList();
    }
  }

  @override
  Future<void> reportProject(String projectId, String reason) async {}
}

class FakeForumRepository implements ForumRepository {
  List<ForumPost> posts = [];
  final Map<String, List<ForumReply>> replies = {};
  final List<String> reports = [];

  @override
  Future<List<ForumPost>> listPosts({String? category}) async => posts
      .where((post) => category == null || post.category == category)
      .toList();

  @override
  Future<void> createPost({
    required String category,
    required String title,
    required String body,
  }) async {
    posts = [
      ForumPost(
        id: 'post-${posts.length}',
        authorName: '测试同学',
        category: category,
        title: title,
        body: body,
        replyCount: 0,
      ),
      ...posts,
    ];
  }

  @override
  Future<ForumThread> getThread(String postId) async => ForumThread(
    post: posts.firstWhere((post) => post.id == postId),
    replies: replies[postId] ?? const [],
  );

  @override
  Future<void> createReply(String postId, String body) async {
    final current = replies[postId] ?? [];
    replies[postId] = [
      ...current,
      ForumReply(id: 'reply-${current.length}', authorName: '测试同学', body: body),
    ];
    posts = posts
        .map(
          (post) => post.id != postId
              ? post
              : ForumPost(
                  id: post.id,
                  authorName: post.authorName,
                  category: post.category,
                  title: post.title,
                  body: post.body,
                  replyCount: post.replyCount + 1,
                ),
        )
        .toList();
  }

  @override
  Future<void> reportContent({
    required String targetType,
    required String targetId,
    required String reason,
  }) async {
    reports.add('$targetType:$targetId:$reason');
  }
}

class FakeNotificationRepository implements NotificationRepository {
  List<AppNotification> notifications = [];

  @override
  Future<NotificationOverview> list() async => NotificationOverview(
    unreadCount: notifications.where((item) => !item.isRead).length,
    notifications: notifications,
  );

  @override
  Future<NotificationOverview> markRead({String? id}) async {
    final now = DateTime.now();
    notifications = notifications
        .map(
          (item) => id == null || item.id == id
              ? AppNotification(
                  id: item.id,
                  kind: item.kind,
                  title: item.title,
                  body: item.body,
                  targetPath: item.targetPath,
                  createdAt: item.createdAt,
                  readAt: item.readAt ?? now,
                )
              : item,
        )
        .toList();
    return list();
  }
}

const testSession = AuthSession(
  accessToken: 'token',
  user: AuthUser(id: 'user-id', displayName: '测试同学', departmentId: 'computer'),
);

Widget testApp(
  FakeAcademicRepository academicRepository, {
  FakePlanRepository? planRepository,
  FakeProfileRepository? profileRepository,
  FakeSocialRepository? socialRepository,
  FakeProjectRepository? projectRepository,
  FakeForumRepository? forumRepository,
  FakeNotificationRepository? notificationRepository,
}) => FStudyApp(
  repository: FakeAuthRepository(session: testSession),
  academicRepositoryFactory: (_) => academicRepository,
  planRepositoryFactory: (_) => planRepository ?? FakePlanRepository(),
  profileRepositoryFactory: (_) => profileRepository ?? FakeProfileRepository(),
  socialRepositoryFactory: (_) => socialRepository ?? FakeSocialRepository(),
  projectRepositoryFactory: (_) => projectRepository ?? FakeProjectRepository(),
  forumRepositoryFactory: (_) => forumRepository ?? FakeForumRepository(),
  notificationRepositoryFactory: (_) =>
      notificationRepository ?? FakeNotificationRepository(),
);

void main() {
  testWidgets('shows the login form on a signed-out launch', (tester) async {
    await tester.pumpWidget(FStudyApp(repository: FakeAuthRepository()));
    await tester.pumpAndSettle();

    expect(find.text('FStudy'), findsOneWidget);
    expect(find.byKey(const Key('usernameField')), findsOneWidget);
    expect(find.byKey(const Key('appPasswordField')), findsOneWidget);
    expect(find.text('登录你的课业空间'), findsOneWidget);

    final usernameField = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const Key('usernameField')),
        matching: find.byType(EditableText),
      ),
    );
    expect(usernameField.autofillHints, contains(AutofillHints.username));
    final passwordField = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const Key('appPasswordField')),
        matching: find.byType(EditableText),
      ),
    );
    expect(passwordField.autofillHints, contains(AutofillHints.password));
  });

  // [2026-10-14 已停用] 验证码 / 学校密码验证相关代码，保留以便日后恢复，勿直接启用：
  // testWidgets(
  // 'CAS browser login starts without showing a school password field',
  // (tester) async {
  // final repository = FakeAuthRepository();
  // await tester.pumpWidget(FStudyApp(repository: repository));
  // await tester.pumpAndSettle();

  // await tester.tap(find.byKey(const Key('buptCasLoginButton')));
  // await tester.pumpAndSettle();

  // expect(repository.casStarted, isTrue);
  // expect(find.byKey(const Key('schoolPasswordField')), findsNothing);
  // },
  // );

  testWidgets('logging out returns to the login form', (tester) async {
    final repository = FakeAuthRepository(
      session: const AuthSession(
        accessToken: 'token',
        user: AuthUser(
          id: 'user-id',
          displayName: '测试同学',
          departmentId: 'computer',
        ),
      ),
    );
    final profile = FakeProfileRepository();
    await tester.pumpWidget(
      FStudyApp(
        repository: repository,
        academicRepositoryFactory: (_) => FakeAcademicRepository(),
        profileRepositoryFactory: (_) => profile,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    expect(find.text('个人资料'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('logoutButton')),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const Key('logoutButton')));
    await tester.pumpAndSettle();
    expect(find.text('确认退出登录？'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirmLogoutButton')));
    await tester.pumpAndSettle();

    expect(repository.loggedOut, isTrue);
    expect(find.text('登录你的课业空间'), findsOneWidget);
  });

  testWidgets('dark mode can be selected from profile settings', (
    tester,
  ) async {
    await tester.pumpWidget(testApp(FakeAcademicRepository()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('darkModeSwitch')),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const Key('darkModeSwitch')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('darkModeSwitch')), findsOneWidget);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp).last).themeMode,
      ThemeMode.dark,
    );
  });

  testWidgets('notification bell opens inbox and marks notifications read', (
    tester,
  ) async {
    final notifications = FakeNotificationRepository()
      ..notifications = [
        AppNotification(
          id: 'n-1',
          kind: 'friend_request',
          title: '收到好友申请',
          body: '甲同学向你发送了好友申请',
          targetPath: '/discover/friends',
          createdAt: DateTime(2026, 10, 10),
          readAt: null,
        ),
      ];
    await tester.pumpWidget(
      testApp(FakeAcademicRepository(), notificationRepository: notifications),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notificationsButton')));
    await tester.pumpAndSettle();

    expect(find.text('收到好友申请'), findsOneWidget);
    expect(find.text('全部已读'), findsOneWidget);
    await tester.tap(find.byKey(const Key('markAllNotificationsReadButton')));
    await tester.pumpAndSettle();
    expect((await notifications.list()).unreadCount, 0);
  });

  testWidgets('the schedule card opens a schedule page', (tester) async {
    final repository = FakeAuthRepository(
      session: const AuthSession(
        accessToken: 'token',
        user: AuthUser(
          id: 'user-id',
          displayName: '测试同学',
          departmentId: 'computer',
        ),
      ),
    );
    await tester.pumpWidget(
      FStudyApp(
        repository: repository,
        academicRepositoryFactory: (_) => FakeAcademicRepository(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('本周课表'));
    await tester.pumpAndSettle();

    expect(find.text('还没有课程'), findsOneWidget);
  });

  testWidgets('campus map opens with searchable campus locations', (
    tester,
  ) async {
    await tester.pumpWidget(testApp(FakeAcademicRepository()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('campusMapNavigationDestination')));
    await tester.pumpAndSettle();

    expect(find.text('校区地图'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('campusMapSearchField')),
      '甲子钟',
    );
    await tester.pumpAndSettle();
    expect(find.text('甲子钟'), findsWidgets);
    expect(find.text('雁南园'), findsNothing);
  });

  testWidgets('campus map route is available from primary navigation', (
    tester,
  ) async {
    await tester.pumpWidget(testApp(FakeAcademicRepository()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('campusMapNavigationDestination')));
    await tester.pumpAndSettle();

    expect(find.text('打开北邮官方沙河校区平面图'), findsOneWidget);
    final rail = find.byType(NavigationRail);
    final selectedIndex = rail.evaluate().isNotEmpty
        ? tester.widget<NavigationRail>(rail).selectedIndex
        : tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex;
    expect(selectedIndex, 2);
  });

  testWidgets('a newly created course appears without a page refresh', (
    tester,
  ) async {
    final academicRepository = FakeAcademicRepository();
    await tester.pumpWidget(
      FStudyApp(
        repository: FakeAuthRepository(
          session: const AuthSession(
            accessToken: 'token',
            user: AuthUser(
              id: 'user-id',
              displayName: '测试同学',
              departmentId: 'computer',
            ),
          ),
        ),
        academicRepositoryFactory: (_) => academicRepository,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('本周课表'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addCourseButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('courseNameField')), '计算机网络');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.text('计算机网络'), findsOneWidget);
  });

  testWidgets('a newly created assignment appears without a page refresh', (
    tester,
  ) async {
    final academicRepository = FakeAcademicRepository();
    await tester.pumpWidget(
      FStudyApp(
        repository: FakeAuthRepository(
          session: const AuthSession(
            accessToken: 'token',
            user: AuthUser(
              id: 'user-id',
              displayName: '测试同学',
              departmentId: 'computer',
            ),
          ),
        ),
        academicRepositoryFactory: (_) => academicRepository,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('待交作业'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addAssignmentButton')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('assignmentTitleField')),
      '完成实验报告',
    );
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.text('完成实验报告'), findsOneWidget);
  });

  testWidgets('weekly schedule filters an odd-week course on an even week', (
    tester,
  ) async {
    final repository = FakeAcademicRepository()
      ..courses.add(
        const Course(
          id: 'networks',
          name: '计算机网络',
          teacher: null,
          color: '#3559C7',
          meetings: [
            CourseMeeting(
              weekday: 1,
              startMinute: 480,
              endMinute: 570,
              startWeek: 1,
              endWeek: 16,
              weekParity: 'odd',
            ),
          ],
        ),
      );
    await tester.pumpWidget(testApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('本周课表'));
    await tester.pumpAndSettle();
    expect(find.text('计算机网络'), findsOneWidget);

    await tester.tap(find.byKey(const Key('scheduleWeekSelector')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('第 2 周').last);
    await tester.pumpAndSettle();

    expect(find.text('第 2 周没有课程'), findsOneWidget);
  });

  testWidgets(
    'semester start date selects and labels the current teaching week',
    (tester) async {
      final repository = FakeAcademicRepository()
        ..semesterStartDate = DateTime(2026, 10, 12)
        ..courses.add(
          const Course(
            id: 'networks',
            name: '计算机网络',
            teacher: null,
            color: '#3559C7',
            meetings: [
              CourseMeeting(
                weekday: 1,
                startMinute: 480,
                endMinute: 570,
                startWeek: 1,
                endWeek: 16,
                weekParity: 'all',
              ),
            ],
          ),
        );
      await tester.pumpWidget(testApp(repository));
      await tester.pumpAndSettle();
      await tester.tap(find.text('本周课表'));
      await tester.pumpAndSettle();

      expect(find.text('2026年10月12日（星期一）'), findsOneWidget);
      expect(
        tester
            .widget<DropdownButton<int>>(
              find.byKey(const Key('scheduleWeekSelector')),
            )
            .value,
        DateTime.now().difference(DateTime(2026, 10, 12)).inDays ~/ 7 + 1,
      );
    },
  );

  testWidgets('a user can set the semester start date from the schedule', (
    tester,
  ) async {
    final repository = FakeAcademicRepository();
    await tester.pumpWidget(testApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('本周课表'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('setSemesterStartDateButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(repository.semesterStartDate?.weekday, DateTime.monday);
    expect(find.textContaining('星期一'), findsOneWidget);
  });

  testWidgets('an assignment can be associated with a course', (tester) async {
    final repository = FakeAcademicRepository()
      ..courses.add(
        const Course(
          id: 'networks',
          name: '计算机网络',
          teacher: null,
          color: '#3559C7',
          meetings: [],
        ),
      );
    await tester.pumpWidget(testApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('待交作业'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addAssignmentButton')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('assignmentTitleField')),
      '完成实验报告',
    );
    await tester.tap(find.byKey(const Key('assignmentCourseField')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('计算机网络').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(repository.assignments.single.courseId, 'networks');
    expect(find.text('计算机网络'), findsOneWidget);
  });

  testWidgets('assignment completion updates immediately', (tester) async {
    final repository = FakeAcademicRepository()
      ..assignments.add(
        const Assignment(
          id: 'homework',
          courseId: null,
          title: '完成实验报告',
          notes: '',
          dueAt: null,
          completedAt: null,
        ),
      );
    await tester.pumpWidget(testApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('待交作业'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    expect(repository.assignments.single.completedAt, isNotNull);
    final title = tester.widget<Text>(find.text('完成实验报告'));
    expect(title.style?.decoration, TextDecoration.lineThrough);
  });

  testWidgets('navigation preserves schedule state between sections', (
    tester,
  ) async {
    final repository = FakeAcademicRepository()
      ..courses.add(
        const Course(
          id: 'networks',
          name: '计算机网络',
          teacher: null,
          color: '#3559C7',
          meetings: [
            CourseMeeting(
              weekday: 1,
              startMinute: 480,
              endMinute: 570,
              startWeek: 1,
              endWeek: 16,
              weekParity: 'all',
            ),
          ],
        ),
      );
    await tester.pumpWidget(testApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('课表'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scheduleWeekSelector')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('第 2 周').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('作业'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('课表'));
    await tester.pumpAndSettle();

    expect(find.text('第 2 周'), findsOneWidget);
  });

  testWidgets('a custom plan with a reminder appears immediately', (
    tester,
  ) async {
    final planRepository = FakePlanRepository();
    await tester.pumpWidget(
      testApp(FakeAcademicRepository(), planRepository: planRepository),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('安排'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addPlanButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('planTitleField')), '复习计算机网络');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.text('复习计算机网络'), findsOneWidget);
    expect(find.textContaining('提前 15 分钟提醒'), findsOneWidget);
  });

  testWidgets('a custom plan can be completed immediately', (tester) async {
    final planRepository = FakePlanRepository()
      ..plans.add(
        Plan(
          id: 'review',
          title: '复习计算机网络',
          notes: '',
          startsAt: DateTime(2026, 10, 8, 20),
          endsAt: DateTime(2026, 10, 8, 21),
          reminderMinutes: null,
          completedAt: null,
        ),
      );
    await tester.pumpWidget(
      testApp(FakeAcademicRepository(), planRepository: planRepository),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('安排'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    expect(planRepository.plans.single.completedAt, isNotNull);
    final title = tester.widget<Text>(find.text('复习计算机网络'));
    expect(title.style?.decoration, TextDecoration.lineThrough);
  });

  testWidgets('registration asks for an email and an invite code', (
    tester,
  ) async {
    final repository = FakeAuthRepository();
    await tester.pumpWidget(FStudyApp(repository: repository));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('inviteCodeField')), findsNothing);

    await tester.tap(find.text('注册'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('usernameField')), 'student01');
    await tester.enterText(
      find.byKey(const Key('emailField')),
      'student@example.edu',
    );
    await tester.enterText(
      find.byKey(const Key('inviteCodeField')),
      'ABCD-EFGH-JKMN',
    );
    await tester.enterText(
      find.byKey(const Key('appPasswordField')),
      'correct-horse-battery',
    );
    await tester.ensureVisible(find.byKey(const Key('submitAuthButton')));
    await tester.tap(find.byKey(const Key('submitAuthButton')));
    await tester.pumpAndSettle();

    expect(repository.registeredUsername, 'student01');
    expect(repository.registeredEmail, 'student@example.edu');
    expect(repository.registeredInviteCode, 'ABCD-EFGH-JKMN');
  });

  testWidgets(
    'profile can generate an invite code and shows the remaining quota',
    (tester) async {
      final profileRepository = FakeProfileRepository();
      await tester.pumpWidget(
        testApp(FakeAcademicRepository(), profileRepository: profileRepository),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('createInviteButton')),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(find.text('本月还可生成 5 / 5 个邀请码'), findsOneWidget);

      await tester.tap(find.byKey(const Key('createInviteButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('issuedInviteCode')), findsOneWidget);
      expect(find.text('ABCD-EFGH-JKMN'), findsOneWidget);
      expect(find.text('本月还可生成 4 / 5 个邀请码'), findsOneWidget);
    },
  );

  testWidgets('profile and schedule privacy settings can be saved', (
    tester,
  ) async {
    final profileRepository = FakeProfileRepository();
    await tester.pumpWidget(
      testApp(FakeAcademicRepository(), profileRepository: profileRepository),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('profileDisplayNameField')),
      '新名字',
    );
    await tester.tap(find.byType(Switch));
    await tester.tap(find.byKey(const Key('scheduleVisibilityField')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('显示课程名称').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('saveProfileButton')),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const Key('saveProfileButton')));
    await tester.pumpAndSettle();

    expect(profileRepository.profile.displayName, '新名字');
    expect(profileRepository.profile.discoverable, isTrue);
    expect(profileRepository.profile.scheduleVisibility, 'course_name');
    expect(find.text('资料与隐私设置已保存'), findsOneWidget);
  });

  testWidgets('selected tags and recommendation preferences are saved', (
    tester,
  ) async {
    final socialRepository = FakeSocialRepository();
    await tester.pumpWidget(
      testApp(FakeAcademicRepository(), socialRepository: socialRepository),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('manageTagsButton')),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const Key('manageTagsButton')));
    await tester.pumpAndSettle();
    final tagList = find
        .descendant(
          of: find.byKey(const Key('tagSettingsList')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.tap(find.byKey(const Key('tag-field-ai')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, '核心'));
    await tester.scrollUntilVisible(
      find.byKey(const Key('saveTagsButton')),
      300,
      scrollable: tagList,
    );
    await tester.tap(find.byKey(const Key('saveTagsButton')));
    await tester.pumpAndSettle();

    expect(socialRepository.myTags.single.id, 'field-ai');
    expect(socialRepository.myTags.single.isCore, isTrue);
    expect(socialRepository.myTags.single.visible, isTrue);
    expect(socialRepository.myTags.single.usedForRecommendation, isTrue);
    expect(find.text('标签设置已保存'), findsOneWidget);
  });

  testWidgets('searches and creates a global tag', (tester) async {
    final socialRepository = FakeSocialRepository();
    await tester.pumpWidget(
      testApp(FakeAcademicRepository(), socialRepository: socialRepository),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('manageTagsButton')),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const Key('manageTagsButton')));
    await tester.pumpAndSettle();
    final tagList = find
        .descendant(
          of: find.byKey(const Key('tagSettingsList')),
          matching: find.byType(Scrollable),
        )
        .first;

    await tester.enterText(find.byKey(const Key('tagSearchField')), '摄影');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tag-interest-photography')), findsOneWidget);
    expect(find.byKey(const Key('tag-field-ai')), findsNothing);

    await tester.tap(find.byKey(const Key('createTagButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('newTagNameField')), '校园摄影');
    await tester.tap(find.byKey(const Key('confirmCreateTagButton')));
    await tester.pumpAndSettle();

    expect(
      socialRepository.availableTags.any((tag) => tag.name == '校园摄影'),
      isTrue,
    );
    expect(find.text('标签已创建并选中'), findsOneWidget);
    expect(find.byKey(const Key('tag-interest-3')), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('saveTagsButton')),
      300,
      scrollable: tagList,
    );
    await tester.tap(find.byKey(const Key('saveTagsButton')));
    await tester.pumpAndSettle();
    expect(socialRepository.myTags.any((tag) => tag.name == '校园摄影'), isTrue);
  });

  testWidgets('discovery displays public profile and common tags', (
    tester,
  ) async {
    final socialRepository = FakeSocialRepository()
      ..users = [
        const DiscoveredUser(
          id: 'student-2',
          displayName: '乙同学',
          departmentId: 'computer',
          bio: '一起学习',
          sameDepartment: true,
          commonTagCount: 1,
          tags: [
            SocialTag(
              id: 'field-ai',
              category: 'field',
              name: '人工智能',
              common: true,
            ),
          ],
          relationship: 'none',
        ),
      ];
    await tester.pumpWidget(
      testApp(FakeAcademicRepository(), socialRepository: socialRepository),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('发现'));
    await tester.pumpAndSettle();

    expect(find.text('乙同学'), findsOneWidget);
    expect(find.text('一起学习'), findsOneWidget);
    expect(find.textContaining('1 个共同标签'), findsOneWidget);
    expect(find.text('人工智能'), findsOneWidget);
  });

  testWidgets('a friend request is sent from discovery immediately', (
    tester,
  ) async {
    final repository = FakeSocialRepository()
      ..users = [
        const DiscoveredUser(
          id: 'student-2',
          displayName: '乙同学',
          departmentId: 'computer',
          bio: '',
          sameDepartment: true,
          commonTagCount: 0,
          tags: [],
          relationship: 'none',
        ),
      ];
    await tester.pumpWidget(
      testApp(FakeAcademicRepository(), socialRepository: repository),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('发现'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-friend-student-2')));
    await tester.pumpAndSettle();

    expect(repository.users.single.relationship, 'outgoing');
    expect(find.text('等待接受'), findsOneWidget);
  });

  testWidgets('an incoming friend request can be accepted', (tester) async {
    final repository = FakeSocialRepository()
      ..overview = const FriendsOverview(
        friends: [],
        incoming: [
          FriendRequestItem(
            id: 'request-1',
            userId: 'student-2',
            displayName: '乙同学',
            departmentId: 'computer',
          ),
        ],
        outgoing: [],
      );
    await tester.pumpWidget(
      testApp(FakeAcademicRepository(), socialRepository: repository),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('好友'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('accept-request-1')));
    await tester.pumpAndSettle();

    expect(repository.overview.incoming, isEmpty);
    expect(repository.overview.friends.single.displayName, '乙同学');
    expect(find.text('乙同学'), findsOneWidget);
  });

  testWidgets('shared availability can be queried and invited', (tester) async {
    final repository = FakeSocialRepository()
      ..overview = const FriendsOverview(
        friends: [
          FriendItem(
            id: 'student-2',
            displayName: '乙同学',
            departmentId: 'computer',
            bio: '',
          ),
        ],
        incoming: [],
        outgoing: [],
      )
      ..freeSlots = const [FreeSlot(startMinute: 600, endMinute: 720)];
    await tester.pumpWidget(
      testApp(FakeAcademicRepository(), socialRepository: repository),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('好友'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sharedAvailabilityButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('availabilityFriendField')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('乙同学').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('queryAvailabilityButton')));
    await tester.pumpAndSettle();

    expect(find.text('10:00–12:00'), findsOneWidget);
    await tester.tap(find.byKey(const Key('invite-600-720')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '发送邀请'));
    await tester.pumpAndSettle();

    expect(repository.invites.single.title, '一起学习');
    expect(find.text('邀请已发送'), findsOneWidget);
  });

  testWidgets('an incoming availability invite can be accepted', (
    tester,
  ) async {
    final repository = FakeSocialRepository()
      ..invites = [
        AvailabilityInvite(
          id: 'invite-1',
          direction: 'incoming',
          userId: 'student-2',
          displayName: '乙同学',
          startsAt: DateTime(2026, 10, 12, 10),
          endsAt: DateTime(2026, 10, 12, 12),
          title: '一起学习',
          status: 'pending',
        ),
      ];
    await tester.pumpWidget(
      testApp(FakeAcademicRepository(), socialRepository: repository),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('好友'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sharedAvailabilityButton')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('accept-invite-invite-1')),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const Key('accept-invite-invite-1')));
    await tester.pumpAndSettle();

    expect(repository.invites.single.status, 'accepted');
    expect(find.textContaining('已接受'), findsOneWidget);
  });

  testWidgets('a newly published project appears immediately', (tester) async {
    final repository = FakeProjectRepository();
    await tester.pumpWidget(
      testApp(FakeAcademicRepository(), projectRepository: repository),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('communityNavigationDestination')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('组队'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addProjectButton')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('projectTitleField')),
      '校园课表助手',
    );
    await tester.enterText(
      find.byKey(const Key('projectDescriptionField')),
      '寻找后端同学',
    );
    await tester.ensureVisible(find.byKey(const Key('project-tag-field-ai')));
    await tester.tap(find.byKey(const Key('project-tag-field-ai')));
    await tester.ensureVisible(find.byKey(const Key('saveProjectButton')));
    await tester.tap(find.byKey(const Key('saveProjectButton')));
    await tester.pumpAndSettle();

    expect(repository.projects.single.title, '校园课表助手');
    expect(repository.projects.single.tags.single.name, '人工智能');
    expect(find.text('校园课表助手'), findsOneWidget);
  });

  testWidgets('a project can be applied to and updates immediately', (
    tester,
  ) async {
    final repository = FakeProjectRepository()
      ..projects = const [
        StudyProject(
          id: 'project-1',
          ownerName: '项目负责人',
          title: '校园课表助手',
          description: '寻找后端同学',
          status: 'recruiting',
          capacity: 4,
          memberCount: 1,
          ownedByMe: false,
          myApplicationStatus: null,
          tags: [],
        ),
      ];
    await tester.pumpWidget(
      testApp(FakeAcademicRepository(), projectRepository: repository),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('communityNavigationDestination')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('组队'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('apply-project-project-1')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('projectApplicationMessageField')),
      '我熟悉后端开发',
    );
    await tester.tap(find.widgetWithText(FilledButton, '提交申请'));
    await tester.pumpAndSettle();

    expect(repository.applications.single.message, '我熟悉后端开发');
    expect(repository.projects.single.myApplicationStatus, 'pending');
    expect(find.text('待处理'), findsWidgets);
  });

  testWidgets('a project owner can accept an application', (tester) async {
    final repository = FakeProjectRepository()
      ..projects = const [
        StudyProject(
          id: 'project-1',
          ownerName: '测试同学',
          title: '校园课表助手',
          description: '寻找队友',
          status: 'recruiting',
          capacity: 4,
          memberCount: 1,
          ownedByMe: true,
          myApplicationStatus: null,
          tags: [],
        ),
      ]
      ..applications = const [
        ProjectApplication(
          id: 'application-1',
          projectTitle: '校园课表助手',
          applicantName: '申请同学',
          message: '我熟悉后端开发',
          status: 'pending',
          direction: 'incoming',
        ),
      ];
    await tester.pumpWidget(
      testApp(FakeAcademicRepository(), projectRepository: repository),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('communityNavigationDestination')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('组队'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('accept-project-application-1')),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.ensureVisible(
      find.byKey(const Key('accept-project-application-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('accept-project-application-1')));
    await tester.pumpAndSettle();

    expect(repository.applications.single.status, 'accepted');
    expect(repository.projects.single.memberCount, 2);
    expect(find.textContaining('成员 2/4'), findsOneWidget);
  });

  testWidgets('a discussion post appears immediately in the community', (
    tester,
  ) async {
    final repository = FakeForumRepository();
    await tester.pumpWidget(
      testApp(FakeAcademicRepository(), forumRepository: repository),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('communityNavigationDestination')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addForumPostButton')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('forumPostTitleField')),
      '高数复习建议',
    );
    await tester.enterText(
      find.byKey(const Key('forumPostBodyField')),
      '应该先看哪一章？',
    );
    await tester.ensureVisible(find.byKey(const Key('saveForumPostButton')));
    await tester.tap(find.byKey(const Key('saveForumPostButton')));
    await tester.pumpAndSettle();

    expect(repository.posts.single.title, '高数复习建议');
    expect(find.text('高数复习建议'), findsOneWidget);
  });

  testWidgets('a public reply updates the discussion immediately', (
    tester,
  ) async {
    final repository = FakeForumRepository()
      ..posts = const [
        ForumPost(
          id: 'post-1',
          authorName: '发帖同学',
          category: 'course',
          title: '高数复习建议',
          body: '应该先看哪一章？',
          replyCount: 0,
        ),
      ];
    await tester.pumpWidget(
      testApp(FakeAcademicRepository(), forumRepository: repository),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('communityNavigationDestination')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('forum-post-post-1')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('forumReplyField-0')),
      '建议先复习极限。',
    );
    await tester.tap(find.byKey(const Key('sendForumReplyButton')));
    await tester.pumpAndSettle();

    expect(repository.replies['post-1']!.single.body, '建议先复习极限。');
    expect(find.text('建议先复习极限。'), findsOneWidget);
  });

  testWidgets('a student can report a public discussion post', (tester) async {
    final repository = FakeForumRepository()
      ..posts = const [
        ForumPost(
          id: 'post-2',
          authorName: '发帖同学',
          category: 'campus',
          title: '需要举报的帖子',
          body: '公开帖子正文',
          replyCount: 0,
        ),
      ];
    await tester.pumpWidget(
      testApp(FakeAcademicRepository(), forumRepository: repository),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('communityNavigationDestination')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('forum-post-post-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reportForumPostButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '内容包含违规信息');
    await tester.tap(find.widgetWithText(FilledButton, '提交举报'));
    await tester.pumpAndSettle();

    expect(repository.reports, ['forum_post:post-2:内容包含违规信息']);
    expect(find.text('举报已提交，感谢反馈'), findsOneWidget);
  });
}
