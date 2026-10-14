import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'notification_repository.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({
    required this.repository,
    required this.onUnreadCountChanged,
    super.key,
  });

  final NotificationRepository repository;
  final ValueChanged<int> onUnreadCountChanged;

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  late Future<NotificationOverview> _overview;
  bool _markingAll = false;

  @override
  void initState() {
    super.initState();
    _overview = _load();
  }

  Future<NotificationOverview> _load() async {
    final result = await widget.repository.list();
    if (mounted) widget.onUnreadCountChanged(result.unreadCount);
    return result;
  }

  void _reload() => _overview = _load();

  Future<void> _markAllRead() async {
    setState(() => _markingAll = true);
    try {
      final updated = await widget.repository.markRead();
      if (!mounted) return;
      setState(() {
        _overview = Future.value(updated);
      });
      widget.onUnreadCountChanged(updated.unreadCount);
    } on NotificationFailure catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  Future<void> _open(AppNotification notification) async {
    if (!notification.isRead) {
      try {
        final updated = await widget.repository.markRead(id: notification.id);
        if (!mounted) return;
        setState(() {
          _overview = Future.value(updated);
        });
        widget.onUnreadCountChanged(updated.unreadCount);
      } on NotificationFailure catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(error.message)));
        }
        return;
      }
    }
    if (mounted) context.go(notification.targetPath);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        key: const Key('notificationsBackButton'),
        tooltip: '返回',
        onPressed: () => context.go('/'),
        icon: const Icon(Icons.arrow_back),
      ),
      title: const Text('通知'),
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: FutureBuilder<NotificationOverview>(
          future: _overview,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('通知加载失败'),
                    TextButton(
                      onPressed: () => setState(_reload),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              );
            }
            final overview = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '通知',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    TextButton.icon(
                      key: const Key('markAllNotificationsReadButton'),
                      onPressed: overview.unreadCount == 0 || _markingAll
                          ? null
                          : _markAllRead,
                      icon: _markingAll
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.done_all),
                      label: const Text('全部已读'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (overview.notifications.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: Text('暂时没有通知')),
                    ),
                  )
                else
                  ...overview.notifications.map(
                    (notification) => Card(
                      child: ListTile(
                        key: Key('notification-${notification.id}'),
                        leading: CircleAvatar(
                          backgroundColor: notification.isRead
                              ? null
                              : Theme.of(context).colorScheme.primaryContainer,
                          child: Icon(_iconFor(notification.kind)),
                        ),
                        title: Text(notification.title),
                        subtitle: Text(
                          '${notification.body}\n${_timeLabel(notification.createdAt)}',
                        ),
                        isThreeLine: true,
                        trailing: notification.isRead
                            ? const Icon(Icons.chevron_right)
                            : Icon(
                                Icons.circle,
                                size: 10,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        onTap: () => _open(notification),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

IconData _iconFor(String kind) => switch (kind) {
  'friend_request' => Icons.person_add_alt_1_outlined,
  'availability_invite' => Icons.event_available_outlined,
  'project_application' => Icons.groups_outlined,
  'forum_reply' => Icons.forum_outlined,
  _ => Icons.notifications_outlined,
};

String _timeLabel(DateTime time) {
  final local = time.toLocal();
  final year = local.year.toString().padLeft(4, '0');
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$year-$month-$day $hour:$minute';
}
