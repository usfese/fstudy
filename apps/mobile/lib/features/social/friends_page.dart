import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'social_repository.dart';

class FriendsPage extends StatefulWidget {
  const FriendsPage({required this.repository, super.key});
  final SocialRepository repository;

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  late Future<FriendsOverview> _overview;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _overview = widget.repository.listFriends();

  Future<void> _act(String requestId, String action) async {
    try {
      await widget.repository.respondToFriendRequest(requestId, action);
      if (mounted) {
        setState(() {
          _reload();
        });
      }
    } on SocialFailure catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<FriendsOverview>(
    future: _overview,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return const Center(child: Text('好友列表加载失败'));
      }
      final data = snapshot.data!;
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '好友',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => context.go('/discover'),
                    icon: const Icon(Icons.person_search_outlined),
                    label: const Text('发现同学'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    key: const Key('sharedAvailabilityButton'),
                    onPressed: () => context.go('/discover/availability'),
                    icon: const Icon(Icons.event_available_outlined),
                    label: const Text('共同空闲'),
                  ),
                ],
              ),
              if (data.incoming.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text('收到的请求', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                ...data.incoming.map(
                  (request) => Card(
                    child: ListTile(
                      title: Text(request.displayName),
                      subtitle: Text(request.departmentId ?? '未填写院系'),
                      trailing: Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: () => _act(request.id, 'reject'),
                            child: const Text('拒绝'),
                          ),
                          FilledButton(
                            key: Key('accept-${request.id}'),
                            onPressed: () => _act(request.id, 'accept'),
                            child: const Text('接受'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              if (data.outgoing.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text('已发出的请求', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                ...data.outgoing.map(
                  (request) => Card(
                    child: ListTile(
                      title: Text(request.displayName),
                      subtitle: const Text('等待对方处理'),
                      trailing: TextButton(
                        onPressed: () => _act(request.id, 'cancel'),
                        child: const Text('取消'),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Text('好友列表', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (data.friends.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(28),
                    child: Center(child: Text('还没有好友')),
                  ),
                )
              else
                ...data.friends.map(
                  (friend) => Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(friend.displayName.characters.first),
                      ),
                      title: Text(friend.displayName),
                      subtitle: Text(
                        [
                          if (friend.departmentId != null) friend.departmentId!,
                          if (friend.bio.isNotEmpty) friend.bio,
                        ].join(' · '),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}
