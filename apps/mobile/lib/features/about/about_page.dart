import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

const fstudyRepositoryUrl = 'https://github.com/usfese/fstudy';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  Future<void> _openRepository(BuildContext context) async {
    final opened = await launchUrl(
      Uri.parse(fstudyRepositoryUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('无法打开 GitHub 仓库，请稍后重试')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          key: const Key('aboutPage'),
          padding: const EdgeInsets.all(24),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => context.go('/profile'),
                icon: const Icon(Icons.arrow_back),
                label: const Text('返回'),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    Icons.school_rounded,
                    size: 34,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '关于 FStudy',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '面向北邮学生的课业与轻社交应用',
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const _AboutSection(
              icon: Icons.auto_stories_outlined,
              title: '把校园生活收进一个地方',
              body:
                  'FStudy 将课表、作业、自定义安排、校园地图、同学发现、讨论区与组队整合在同一份应用中。'
                  '课程和作业由你手动维护，不抓取学校系统，也不需要提供学校密码。',
            ),
            const SizedBox(height: 12),
            const _AboutSection(
              icon: Icons.privacy_tip_outlined,
              title: '简单、克制的账户设计',
              body:
                  '注册采用邀请制，只需要用户名和密码；邮箱会被记录但不做验证，也不对外展示。'
                  '应用不验证学生身份，每个账户都由使用者自行声明。',
            ),
            const SizedBox(height: 12),
            const _AboutSection(
              icon: Icons.layers_outlined,
              title: '同一套代码，多端运行',
              body:
                  '客户端使用 Flutter 构建，支持 Web/PWA 与 Android；服务端使用 Hono + TypeScript，'
                  '可运行在本地 Node.js + SQLite，或部署到 Cloudflare Workers + D1。',
            ),
            const SizedBox(height: 24),
            Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                key: const Key('githubRepositoryTile'),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                leading: const Icon(Icons.code),
                title: const Text('GitHub 仓库'),
                subtitle: const SelectableText(fstudyRepositoryUrl),
                trailing: const Icon(Icons.open_in_new),
                onTap: () => _openRepository(context),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '欢迎在 GitHub 上查看源码、提交 Issue 或参与改进。',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: colorScheme.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    body,
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
