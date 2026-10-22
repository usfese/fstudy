import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';

import 'features/academic/academic_repository.dart';
import 'features/academic/assignments_page.dart';
import 'features/academic/courses_page.dart';
import 'features/academic/recent_inputs.dart';
import 'features/auth/auth_page.dart';
import 'features/auth/auth_repository.dart';
import 'features/community/community_page.dart';
import 'features/community/forum_repository.dart';
import 'features/home/home_page.dart';
import 'features/map/campus_map_page.dart';
import 'features/notifications/notification_repository.dart';
import 'features/notifications/notifications_page.dart';
import 'features/plans/plan_repository.dart';
import 'features/plans/plans_page.dart';
import 'features/profile/profile_page.dart';
import 'features/profile/profile_repository.dart';
import 'features/projects/project_repository.dart';
import 'features/social/discover_page.dart';
import 'features/social/availability_page.dart';
import 'features/social/friends_page.dart';
import 'features/social/social_repository.dart';
import 'features/social/tag_settings_page.dart';
import 'navigation/app_shell.dart';

class FStudyApp extends StatefulWidget {
  const FStudyApp({
    required this.repository,
    this.academicRepositoryFactory,
    this.planRepositoryFactory,
    this.profileRepositoryFactory,
    this.socialRepositoryFactory,
    this.projectRepositoryFactory,
    this.forumRepositoryFactory,
    this.notificationRepositoryFactory,
    super.key,
  });

  final AuthRepository repository;
  final AcademicRepository Function(AuthSession session)?
  academicRepositoryFactory;
  final PlanRepository Function(AuthSession session)? planRepositoryFactory;
  final ProfileRepository Function(AuthSession session)?
  profileRepositoryFactory;
  final SocialRepository Function(AuthSession session)? socialRepositoryFactory;
  final ProjectRepository Function(AuthSession session)?
  projectRepositoryFactory;
  final ForumRepository Function(AuthSession session)? forumRepositoryFactory;
  final NotificationRepository Function(AuthSession session)?
  notificationRepositoryFactory;

  @override
  State<FStudyApp> createState() => _FStudyAppState();
}

class _FStudyAppState extends State<FStudyApp> {
  late final SemanticsHandle _semanticsHandle;
  static const _themeStorageKey = 'fstudy_theme_mode';
  static const _storage = FlutterSecureStorage();
  ThemeMode _themeMode = ThemeMode.light;
  AuthSession? _session;
  AcademicRepository? _academicRepository;
  PlanRepository? _planRepository;
  ProfileRepository? _profileRepository;
  SocialRepository? _socialRepository;
  ProjectRepository? _projectRepository;
  ForumRepository? _forumRepository;
  NotificationRepository? _notificationRepository;
  bool _restoring = true;
  int _unreadNotificationCount = 0;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    // Flutter Web otherwise waits for an assistive technology to request semantics,
    // leaving browser keyboard-navigation extensions with only the canvas host.
    _semanticsHandle = WidgetsBinding.instance.ensureSemantics();
    _router = GoRouter(
      routes: [
        GoRoute(
          path: '/login',
          builder: (context, state) {
            final callbackParams = Uri.splitQueryString(state.uri.fragment);
            return AuthPage(
              repository: widget.repository,
              onAuthenticated: _onAuthenticated,
              casCode:
                  callbackParams['cas_code'] ??
                  state.uri.queryParameters['cas_code'],
              casState:
                  callbackParams['cas_state'] ??
                  state.uri.queryParameters['cas_state'],
            );
          },
        ),
        GoRoute(
          path: '/notifications',
          builder: (context, state) {
            if (_session == null || _notificationRepository == null) {
              return const Scaffold(body: Center(child: Text('请先登录后查看通知')));
            }
            return NotificationsPage(
              repository: _notificationRepository!,
              onUnreadCountChanged: (count) => setState(() {
                _unreadNotificationCount = count;
              }),
            );
          },
        ),
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) => AppShell(
            navigationShell: navigationShell,
            unreadCount: _unreadNotificationCount,
            onOpenNotifications: () => context.go('/notifications'),
            onThemeModeChanged: _setThemeMode,
            onLogout: _logout,
          ),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/',
                  builder: (context, state) => HomePage(session: _session!),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/schedule',
                  builder: (context, state) =>
                      CoursesPage(repository: _academicRepository!),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/map',
                  builder: (context, state) => const CampusMapPage(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/assignments',
                  builder: (context, state) =>
                      AssignmentsPage(repository: _academicRepository!),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/plans',
                  builder: (context, state) =>
                      PlansPage(repository: _planRepository!),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/discover',
                  builder: (context, state) =>
                      DiscoverPage(repository: _socialRepository!),
                  routes: [
                    GoRoute(
                      path: 'friends',
                      builder: (context, state) =>
                          FriendsPage(repository: _socialRepository!),
                    ),
                    GoRoute(
                      path: 'availability',
                      builder: (context, state) =>
                          AvailabilityPage(repository: _socialRepository!),
                    ),
                  ],
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/community',
                  builder: (context, state) => CommunityPage(
                    forumRepository: _forumRepository!,
                    projectRepository: _projectRepository!,
                    initialTab: state.uri.queryParameters['tab'] == 'teams'
                        ? 1
                        : 0,
                  ),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/profile',
                  builder: (context, state) => ProfilePage(
                    repository: _profileRepository!,
                    themeMode: _themeMode,
                    onThemeModeChanged: _setThemeMode,
                    onLogout: _logout,
                  ),
                  routes: [
                    GoRoute(
                      path: 'tags',
                      builder: (context, state) =>
                          TagSettingsPage(repository: _socialRepository!),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        GoRoute(
          path: '/projects',
          redirect: (context, state) => '/community?tab=teams',
        ),
      ],
      redirect: (context, state) {
        if (_restoring) return null;
        final onLogin = state.matchedLocation == '/login';
        final hasCasReturn =
            state.uri.queryParameters.containsKey('cas_code') ||
            state.uri.queryParameters.containsKey('cas_state');
        if (_session == null && !onLogin) return '/login';
        if (_session != null && onLogin && !hasCasReturn) return '/';
        return null;
      },
    );
    _restoreThemeMode();
    _restoreSession();
  }

  Future<void> _restoreThemeMode() async {
    String? value;
    try {
      value = await _storage.read(key: _themeStorageKey);
    } catch (_) {
      return;
    }
    if (!mounted || value == null) return;
    setState(
      () => _themeMode = value == 'dark' ? ThemeMode.dark : ThemeMode.light,
    );
  }

  Future<void> _setThemeMode(ThemeMode mode) async {
    setState(() => _themeMode = mode);
    try {
      await _storage.write(
        key: _themeStorageKey,
        value: mode == ThemeMode.dark ? 'dark' : 'light',
      );
    } catch (_) {
      // Keep the current-session choice even if platform storage is unavailable.
    }
  }

  Future<void> _restoreSession() async {
    final session = await widget.repository.restoreSession();
    if (!mounted) return;
    setState(() {
      _restoring = false;
      _setSession(session);
    });
    _router.refresh();
  }

  void _setSession(AuthSession? session) {
    _session = session;
    if (session == null) _unreadNotificationCount = 0;
    _academicRepository = session == null
        ? null
        : widget.academicRepositoryFactory?.call(session) ??
              DioAcademicRepository(accessToken: session.accessToken);
    _planRepository = session == null
        ? null
        : widget.planRepositoryFactory?.call(session) ??
              DioPlanRepository(accessToken: session.accessToken);
    _profileRepository = session == null
        ? null
        : widget.profileRepositoryFactory?.call(session) ??
              DioProfileRepository(accessToken: session.accessToken);
    _socialRepository = session == null
        ? null
        : widget.socialRepositoryFactory?.call(session) ??
              DioSocialRepository(accessToken: session.accessToken);
    _projectRepository = session == null
        ? null
        : widget.projectRepositoryFactory?.call(session) ??
              DioProjectRepository(accessToken: session.accessToken);
    _forumRepository = session == null
        ? null
        : widget.forumRepositoryFactory?.call(session) ??
              DioForumRepository(accessToken: session.accessToken);
    _notificationRepository = session == null
        ? null
        : widget.notificationRepositoryFactory?.call(session) ??
              DioNotificationRepository(accessToken: session.accessToken);
    if (_notificationRepository != null) _refreshUnreadNotificationCount();
  }

  Future<void> _refreshUnreadNotificationCount() async {
    final repository = _notificationRepository;
    if (repository == null) return;
    try {
      final overview = await repository.list();
      if (mounted && repository == _notificationRepository) {
        setState(() => _unreadNotificationCount = overview.unreadCount);
      }
    } catch (_) {
      // The rest of the app remains usable if notification fetch is unavailable.
    }
  }

  void _onAuthenticated(AuthSession session) {
    setState(() => _setSession(session));
    _router.go('/');
  }

  Future<void> _logout() async {
    await widget.repository.logout();
    RecentInputs.clear();
    if (!mounted) return;
    setState(() => _setSession(null));
    _router.go('/login');
  }

  @override
  void dispose() {
    _router.dispose();
    _semanticsHandle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_restoring) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _theme(),
        home: const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    return MaterialApp.router(
      title: 'FStudy',
      debugShowCheckedModeBanner: false,
      theme: _theme(),
      darkTheme: _darkTheme(),
      themeMode: _themeMode,
      routerConfig: _router,
    );
  }

  ThemeData _theme() => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF3559C7),
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: const Color(0xFFF5F7FC),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      filled: true,
      fillColor: Colors.white,
    ),
    cardTheme: _cardTheme(
      light: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF3559C7),
        brightness: Brightness.light,
      ),
    ),
    useMaterial3: true,
  );

  ThemeData _darkTheme() => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF8EA7FF),
      brightness: Brightness.dark,
    ),
    scaffoldBackgroundColor: const Color(0xFF0F1117),
    cardTheme: _cardTheme(
      light: false,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF8EA7FF),
        brightness: Brightness.dark,
      ),
    ),
    useMaterial3: true,
  );

  static CardThemeData _cardTheme({
    required bool light,
    required ColorScheme colorScheme,
  }) => CardThemeData(
    elevation: 0,
    surfaceTintColor: Colors.transparent,
    color: light
        ? colorScheme.surfaceContainerLowest
        : colorScheme.surfaceContainerLow,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: colorScheme.outlineVariant),
    ),
  );
}
