import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'features/academic/academic_repository.dart';
import 'features/academic/assignments_page.dart';
import 'features/academic/courses_page.dart';
import 'features/auth/auth_page.dart';
import 'features/auth/auth_repository.dart';
import 'features/community/community_page.dart';
import 'features/community/forum_repository.dart';
import 'features/home/home_page.dart';
import 'features/map/campus_map_page.dart';
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

  @override
  State<FStudyApp> createState() => _FStudyAppState();
}

class _FStudyAppState extends State<FStudyApp> {
  AuthSession? _session;
  AcademicRepository? _academicRepository;
  PlanRepository? _planRepository;
  ProfileRepository? _profileRepository;
  SocialRepository? _socialRepository;
  ProjectRepository? _projectRepository;
  ForumRepository? _forumRepository;
  bool _restoring = true;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      routes: [
        GoRoute(
          path: '/login',
          builder: (context, state) => AuthPage(
            repository: widget.repository,
            onAuthenticated: _onAuthenticated,
          ),
        ),
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) =>
              AppShell(navigationShell: navigationShell, onLogout: _logout),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/',
                  builder: (context, state) => HomePage(session: _session!),
                  routes: [
                    GoRoute(
                      path: 'map',
                      builder: (context, state) => const CampusMapPage(),
                    ),
                  ],
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
                  builder: (context, state) =>
                      ProfilePage(repository: _profileRepository!),
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
        if (_session == null && !onLogin) return '/login';
        if (_session != null && onLogin) return '/';
        return null;
      },
    );
    _restoreSession();
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
  }

  void _onAuthenticated(AuthSession session) {
    setState(() => _setSession(session));
    _router.go('/');
  }

  Future<void> _logout() async {
    await widget.repository.logout();
    if (!mounted) return;
    setState(() => _setSession(null));
    _router.go('/login');
  }

  @override
  void dispose() {
    _router.dispose();
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
    useMaterial3: true,
  );
}
