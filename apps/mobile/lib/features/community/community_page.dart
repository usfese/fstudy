import 'package:flutter/material.dart';

import '../projects/project_repository.dart';
import '../projects/projects_page.dart';
import 'forum_repository.dart';

class CommunityPage extends StatelessWidget {
  const CommunityPage({
    required this.forumRepository,
    required this.projectRepository,
    this.initialTab = 0,
    super.key,
  });

  final ForumRepository forumRepository;
  final ProjectRepository projectRepository;
  final int initialTab;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    initialIndex: initialTab,
    child: Column(
      children: [
        const Material(
          child: TabBar(
            tabs: [
              Tab(icon: Icon(Icons.forum_outlined), text: '讨论'),
              Tab(icon: Icon(Icons.groups_outlined), text: '组队'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            children: [
              ForumPage(repository: forumRepository),
              ProjectsPage(repository: projectRepository),
            ],
          ),
        ),
      ],
    ),
  );
}

class ForumPage extends StatefulWidget {
  const ForumPage({required this.repository, super.key});
  final ForumRepository repository;

  @override
  State<ForumPage> createState() => _ForumPageState();
}

class _ForumPageState extends State<ForumPage> {
  late Future<List<ForumPost>> _posts;
  String? _category;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _posts = widget.repository.listPosts(category: _category);
  }

  void _refresh() => setState(_reload);

  Future<void> _createPost() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _PostDialog(repository: widget.repository),
    );
    if (created == true && mounted) _refresh();
  }

  Future<void> _openThread(ForumPost post) async {
    await showDialog<void>(
      context: context,
      builder: (_) =>
          _ThreadDialog(repository: widget.repository, postId: post.id),
    );
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1000),
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '校园讨论',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    const Text('公开交流课程、校园生活与经验；请勿发布私人联系方式。'),
                  ],
                ),
              ),
              FilledButton.icon(
                key: const Key('addForumPostButton'),
                onPressed: _createPost,
                icon: const Icon(Icons.add),
                label: const Text('发布讨论'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<String?>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: '讨论分类'),
              items: const [
                DropdownMenuItem(value: null, child: Text('全部分类')),
                DropdownMenuItem(value: 'general', child: Text('综合')),
                DropdownMenuItem(value: 'course', child: Text('课程')),
                DropdownMenuItem(value: 'campus', child: Text('校园')),
                DropdownMenuItem(value: 'experience', child: Text('经验分享')),
              ],
              onChanged: (value) {
                _category = value;
                _refresh();
              },
            ),
          ),
          const SizedBox(height: 16),
          FutureBuilder<List<ForumPost>>(
            future: _posts,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) return const Text('讨论加载失败');
              final posts = snapshot.data!;
              if (posts.isEmpty) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('暂无讨论，来发布第一篇吧')),
                  ),
                );
              }
              return Column(
                children: posts
                    .map(
                      (post) => Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          key: Key('forum-post-${post.id}'),
                          onTap: () => _openThread(post),
                          title: Text(post.title),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              '${_categoryName(post.category)} · ${post.authorName}\n${post.body}',
                            ),
                          ),
                          isThreeLine: true,
                          trailing: Text('${post.replyCount} 回复'),
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

class _PostDialog extends StatefulWidget {
  const _PostDialog({required this.repository});
  final ForumRepository repository;

  @override
  State<_PostDialog> createState() => _PostDialogState();
}

class _PostDialogState extends State<_PostDialog> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _body = TextEditingController();
  String _category = 'general';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.repository.createPost(
        category: _category,
        title: _title.text.trim(),
        body: _body.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } on ForumFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('发布讨论'),
    content: SizedBox(
      width: 520,
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(labelText: '分类'),
                items: const [
                  DropdownMenuItem(value: 'general', child: Text('综合')),
                  DropdownMenuItem(value: 'course', child: Text('课程')),
                  DropdownMenuItem(value: 'campus', child: Text('校园')),
                  DropdownMenuItem(value: 'experience', child: Text('经验分享')),
                ],
                onChanged: (value) => setState(() => _category = value!),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('forumPostTitleField'),
                controller: _title,
                maxLength: 100,
                validator: (value) =>
                    value == null || value.trim().isEmpty ? '请填写标题' : null,
                decoration: const InputDecoration(labelText: '标题'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('forumPostBodyField'),
                controller: _body,
                maxLength: 5000,
                maxLines: 6,
                validator: (value) =>
                    value == null || value.trim().isEmpty ? '请填写正文' : null,
                decoration: const InputDecoration(labelText: '正文'),
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        key: const Key('saveForumPostButton'),
        onPressed: _saving ? null : _save,
        child: Text(_saving ? '发布中…' : '发布'),
      ),
    ],
  );
}

class _ThreadDialog extends StatefulWidget {
  const _ThreadDialog({required this.repository, required this.postId});
  final ForumRepository repository;
  final String postId;

  @override
  State<_ThreadDialog> createState() => _ThreadDialogState();
}

class _ThreadDialogState extends State<_ThreadDialog> {
  late Future<ForumThread> _thread;
  String _reply = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _thread = widget.repository.getThread(widget.postId);
  }

  Future<void> _send() async {
    final body = _reply.trim();
    if (body.isEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.repository.createReply(widget.postId, body);
      if (mounted) {
        setState(() {
          _reply = '';
          _thread = widget.repository.getThread(widget.postId);
        });
      }
    } on ForumFailure catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    content: SizedBox(
      width: 620,
      height: 560,
      child: FutureBuilder<ForumThread>(
        future: _thread,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final thread = snapshot.data!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                thread.post.title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(
                '${_categoryName(thread.post.category)} · ${thread.post.authorName}',
              ),
              const SizedBox(height: 14),
              Text(thread.post.body),
              const Divider(height: 28),
              Expanded(
                child: thread.replies.isEmpty
                    ? const Center(child: Text('暂无回复'))
                    : ListView(
                        children: thread.replies
                            .map(
                              (reply) => ListTile(
                                title: Text(reply.authorName),
                                subtitle: Text(reply.body),
                              ),
                            )
                            .toList(),
                      ),
              ),
              TextField(
                key: ValueKey('forumReplyField-${thread.replies.length}'),
                maxLength: 2000,
                maxLines: 3,
                onChanged: (value) => _reply = value,
                decoration: const InputDecoration(labelText: '公开回复'),
              ),
            ],
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
      FilledButton(
        key: const Key('sendForumReplyButton'),
        onPressed: _saving ? null : _send,
        child: Text(_saving ? '发送中…' : '发送回复'),
      ),
    ],
  );
}

String _categoryName(String category) =>
    const {
      'general': '综合',
      'course': '课程',
      'campus': '校园',
      'experience': '经验分享',
    }[category] ??
    category;
