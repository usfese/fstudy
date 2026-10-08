import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_repository.dart';

class HomePage extends StatelessWidget {
  const HomePage({required this.session, super.key});

  final AuthSession session;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              '你好，${session.user.displayName}',
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              '账户连接成功，现在可以开始管理课业。',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _FeatureCard(
                  icon: Icons.calendar_month_outlined,
                  title: '本周课表',
                  detail: '查看并管理手动课程',
                  onTap: () => context.go('/schedule'),
                ),
                _FeatureCard(
                  icon: Icons.task_alt_outlined,
                  title: '待交作业',
                  detail: '集中查看截止时间',
                  onTap: () => context.go('/assignments'),
                ),
                _FeatureCard(
                  icon: Icons.event_note_outlined,
                  title: '自定义安排',
                  detail: '复习、会议与提醒',
                  onTap: () => context.go('/plans'),
                ),
                _FeatureCard(
                  icon: Icons.people_outline,
                  title: '发现同学',
                  detail: '按共同标签寻找搭子',
                  onTap: () => context.go('/discover'),
                ),
                _FeatureCard(
                  icon: Icons.group_outlined,
                  title: '好友',
                  detail: '处理请求与查看好友',
                  onTap: () => context.go('/discover/friends'),
                ),
                _FeatureCard(
                  icon: Icons.forum_outlined,
                  title: '社区',
                  detail: '校园讨论与组队',
                  onTap: () => context.go('/community'),
                ),
                _FeatureCard(
                  icon: Icons.map_outlined,
                  title: '校区地图',
                  detail: '查找校园地点与路线',
                  onTap: () => context.go('/map'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 280,
      child: Card(
        elevation: 0,
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  icon,
                  size: 30,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 18),
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 6),
                Text(detail),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
