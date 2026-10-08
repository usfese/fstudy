import 'package:flutter/material.dart';

import 'social_repository.dart';

class DiscoverPage extends StatefulWidget {
  const DiscoverPage({required this.repository, super.key});
  final SocialRepository repository;

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  late Future<List<DiscoveredUser>> _users;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _users = widget.repository.discoverUsers();

  Future<void> _sendRequest(DiscoveredUser user) async {
    try {
      await widget.repository.sendFriendRequest(user.id);
      if (mounted) {
        setState(() {
          _reload();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已向 ${user.displayName} 发送好友请求')),
        );
      }
    } on SocialFailure catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<DiscoveredUser>>(
      future: _users,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: FilledButton.tonal(
              onPressed: () => setState(() {
                _reload();
              }),
              child: const Text('加载失败，点击重试'),
            ),
          );
        }
        final users = snapshot.data!;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  '发现同学',
                  style: Theme.of(context).textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  '按共同标签和院系推荐，仅展示对方公开的信息。',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                if (users.isEmpty)
                  const _EmptyDiscovery()
                else
                  ...users.map(
                    (user) =>
                        _UserCard(user: user, onAdd: () => _sendRequest(user)),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EmptyDiscovery extends StatelessWidget {
  const _EmptyDiscovery();

  @override
  Widget build(BuildContext context) => const Card(
    child: Padding(
      padding: EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(Icons.people_outline, size: 56),
          SizedBox(height: 12),
          Text('暂时没有可推荐的同学'),
          SizedBox(height: 6),
          Text('可先在“我的”中完善标签，并开启允许被推荐和发现。'),
        ],
      ),
    ),
  );
}

class _UserCard extends StatelessWidget {
  const _UserCard({required this.user, required this.onAdd});
  final DiscoveredUser user;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(child: Text(user.displayName.characters.first)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.displayName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        [
                          if (user.departmentId != null) user.departmentId!,
                          if (user.sameDepartment) '同院系',
                          if (user.commonTagCount > 0)
                            '${user.commonTagCount} 个共同标签',
                        ].join(' · '),
                      ),
                    ],
                  ),
                ),
                _RelationshipAction(user: user, onAdd: onAdd),
              ],
            ),
            if (user.bio.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(user.bio),
            ],
            if (user.tags.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: user.tags
                    .map(
                      (tag) => Chip(
                        avatar: tag.common
                            ? const Icon(Icons.link, size: 16)
                            : null,
                        label: Text(tag.name),
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RelationshipAction extends StatelessWidget {
  const _RelationshipAction({required this.user, required this.onAdd});
  final DiscoveredUser user;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => switch (user.relationship) {
    'friends' => const Chip(label: Text('已是好友')),
    'outgoing' => const Chip(label: Text('等待接受')),
    'incoming' => const Chip(label: Text('对方已申请')),
    _ => FilledButton.tonalIcon(
      key: Key('add-friend-${user.id}'),
      onPressed: onAdd,
      icon: const Icon(Icons.person_add_outlined),
      label: const Text('加好友'),
    ),
  };
}
