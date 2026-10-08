import 'package:flutter/material.dart';

import 'social_repository.dart';

class AvailabilityPage extends StatefulWidget {
  const AvailabilityPage({required this.repository, super.key});
  final SocialRepository repository;

  @override
  State<AvailabilityPage> createState() => _AvailabilityPageState();
}

class _AvailabilityPageState extends State<AvailabilityPage> {
  late Future<FriendsOverview> _friends;
  late Future<List<AvailabilityInvite>> _invites;
  String? _friendId;
  DateTime _date = DateTime.now();
  int _weekNumber = 1;
  int _dayStart = 480;
  int _dayEnd = 1320;
  List<FreeSlot>? _slots;
  bool _querying = false;

  @override
  void initState() {
    super.initState();
    _friends = widget.repository.listFriends();
    _reloadInvites();
  }

  void _reloadInvites() {
    _invites = widget.repository.listAvailabilityInvites();
  }

  Future<void> _query() async {
    if (_friendId == null) return;
    setState(() => _querying = true);
    try {
      final slots = await widget.repository.queryAvailability(
        friendId: _friendId!,
        date: _date,
        weekNumber: _weekNumber,
        dayStartMinute: _dayStart,
        dayEndMinute: _dayEnd,
      );
      if (mounted) setState(() => _slots = slots);
    } on SocialFailure catch (error) {
      if (mounted) _message(error.message);
    } finally {
      if (mounted) setState(() => _querying = false);
    }
  }

  Future<void> _invite(FreeSlot slot) async {
    final controller = TextEditingController(text: '一起学习');
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('发起邀请'),
        content: TextField(
          key: const Key('inviteTitleField'),
          controller: controller,
          decoration: const InputDecoration(labelText: '活动名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('发送邀请'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title == null || title.isEmpty || !mounted) return;
    try {
      await widget.repository.createAvailabilityInvite(
        friendId: _friendId!,
        startsAt: _atMinute(_date, slot.startMinute),
        endsAt: _atMinute(_date, slot.endMinute),
        title: title,
      );
      if (mounted) {
        setState(_reloadInvites);
        _message('邀请已发送');
      }
    } on SocialFailure catch (error) {
      if (mounted) _message(error.message);
    }
  }

  Future<void> _respond(String id, String action) async {
    try {
      await widget.repository.respondToAvailabilityInvite(id, action);
      if (mounted) setState(_reloadInvites);
    } on SocialFailure catch (error) {
      if (mounted) _message(error.message);
    }
  }

  void _message(String value) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 920),
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            '共同空闲',
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text('只显示双方都空闲的时间，不展示对方的课程或安排内容。'),
          const SizedBox(height: 20),
          FutureBuilder<FriendsOverview>(
            future: _friends,
            builder: (context, snapshot) {
              final friends = snapshot.data?.friends ?? const <FriendItem>[];
              return DropdownButtonFormField<String>(
                key: const Key('availabilityFriendField'),
                initialValue: _friendId,
                decoration: const InputDecoration(labelText: '选择好友'),
                items: friends
                    .map(
                      (friend) => DropdownMenuItem(
                        value: friend.id,
                        child: Text(friend.displayName),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _friendId = value),
              );
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              OutlinedButton.icon(
                key: const Key('availabilityDateButton'),
                onPressed: () async {
                  final value = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime.now().subtract(
                      const Duration(days: 365),
                    ),
                    lastDate: DateTime.now().add(const Duration(days: 3650)),
                  );
                  if (value != null) setState(() => _date = value);
                },
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(_dateText(_date)),
              ),
              SizedBox(
                width: 170,
                child: DropdownButtonFormField<int>(
                  key: const Key('availabilityWeekField'),
                  isExpanded: true,
                  initialValue: _weekNumber,
                  decoration: const InputDecoration(labelText: '教学周'),
                  items: List.generate(
                    30,
                    (index) => DropdownMenuItem(
                      value: index + 1,
                      child: Text('第 ${index + 1} 周'),
                    ),
                  ),
                  onChanged: (value) => setState(() => _weekNumber = value!),
                ),
              ),
              SizedBox(
                width: 170,
                child: DropdownButtonFormField<int>(
                  isExpanded: true,
                  initialValue: _dayStart,
                  decoration: const InputDecoration(labelText: '从'),
                  items: _timeChoices
                      .map(
                        (minute) => DropdownMenuItem(
                          value: minute,
                          child: Text(_minuteText(minute)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _dayStart = value!),
                ),
              ),
              SizedBox(
                width: 170,
                child: DropdownButtonFormField<int>(
                  isExpanded: true,
                  initialValue: _dayEnd,
                  decoration: const InputDecoration(labelText: '到'),
                  items: _timeChoices
                      .map(
                        (minute) => DropdownMenuItem(
                          value: minute,
                          child: Text(_minuteText(minute)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _dayEnd = value!),
                ),
              ),
              FilledButton.icon(
                key: const Key('queryAvailabilityButton'),
                onPressed:
                    _friendId == null || _querying || _dayEnd <= _dayStart
                    ? null
                    : _query,
                icon: const Icon(Icons.search),
                label: Text(_querying ? '查询中…' : '查询'),
              ),
            ],
          ),
          if (_slots != null) ...[
            const SizedBox(height: 24),
            Text('可用时间', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (_slots!.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('所选范围内没有共同空闲时间'),
                ),
              )
            else
              ..._slots!.map(
                (slot) => Card(
                  child: ListTile(
                    title: Text(
                      '${_minuteText(slot.startMinute)}–${_minuteText(slot.endMinute)}',
                    ),
                    subtitle: Text('${slot.endMinute - slot.startMinute} 分钟'),
                    trailing: FilledButton.tonal(
                      key: Key('invite-${slot.startMinute}-${slot.endMinute}'),
                      onPressed: () => _invite(slot),
                      child: const Text('邀请'),
                    ),
                  ),
                ),
              ),
          ],
          const SizedBox(height: 28),
          Text('邀请记录', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          FutureBuilder<List<AvailabilityInvite>>(
            future: _invites,
            builder: (context, snapshot) {
              final invites = snapshot.data ?? const <AvailabilityInvite>[];
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (invites.isEmpty) return const Text('暂无邀请');
              return Column(
                children: invites
                    .map(
                      (invite) => Card(
                        child: ListTile(
                          title: Text(invite.title),
                          subtitle: Text(
                            '${invite.displayName} · ${_dateText(invite.startsAt.toLocal())} '
                            '${_minuteText(invite.startsAt.toLocal().hour * 60 + invite.startsAt.toLocal().minute)}–'
                            '${_minuteText(invite.endsAt.toLocal().hour * 60 + invite.endsAt.toLocal().minute)} · '
                            '${_statusText(invite.status)}',
                          ),
                          trailing: invite.status != 'pending'
                              ? null
                              : invite.direction == 'incoming'
                              ? Wrap(
                                  spacing: 8,
                                  children: [
                                    TextButton(
                                      onPressed: () =>
                                          _respond(invite.id, 'reject'),
                                      child: const Text('拒绝'),
                                    ),
                                    FilledButton(
                                      key: Key('accept-invite-${invite.id}'),
                                      onPressed: () =>
                                          _respond(invite.id, 'accept'),
                                      child: const Text('接受'),
                                    ),
                                  ],
                                )
                              : TextButton(
                                  onPressed: () =>
                                      _respond(invite.id, 'cancel'),
                                  child: const Text('取消'),
                                ),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    ),
  );
}

const _timeChoices = [
  360,
  420,
  480,
  540,
  600,
  660,
  720,
  780,
  840,
  900,
  960,
  1020,
  1080,
  1140,
  1200,
  1260,
  1320,
  1380,
  1440,
];

DateTime _atMinute(DateTime date, int minute) =>
    DateTime(date.year, date.month, date.day).add(Duration(minutes: minute));
String _minuteText(int minute) =>
    '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
String _dateText(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
String _statusText(String status) =>
    const {
      'pending': '待处理',
      'accepted': '已接受',
      'rejected': '已拒绝',
      'canceled': '已取消',
    }[status] ??
    status;
