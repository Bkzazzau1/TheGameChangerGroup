import 'package:flutter/material.dart';

import '../domain/permissions.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';

class DiscussionRoomPage extends StatefulWidget {
  const DiscussionRoomPage({super.key});

  @override
  State<DiscussionRoomPage> createState() => _DiscussionRoomPageState();
}

class _DiscussionChannel {
  const _DiscussionChannel({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
  });

  final String id;
  final String name;
  final String description;
  final IconData icon;
}

class _DiscussionReply {
  const _DiscussionReply({
    required this.author,
    required this.role,
    required this.body,
    required this.time,
  });

  final String author;
  final String role;
  final String body;
  final String time;
}

class _DiscussionThread {
  _DiscussionThread({
    required this.id,
    required this.channelId,
    required this.title,
    required this.body,
    required this.author,
    required this.role,
    required this.time,
    required this.replies,
    this.pinned = false,
    this.resolved = false,
  });

  final String id;
  final String channelId;
  final String title;
  final String body;
  final String author;
  final String role;
  final String time;
  final List<_DiscussionReply> replies;
  bool pinned;
  bool resolved;
}

class _DiscussionRoomPageState extends State<DiscussionRoomPage> {
  final replyController = TextEditingController();
  String selectedChannelId = 'national';
  String? selectedThreadId = 'THR-1001';
  String search = '';

  static const channels = <_DiscussionChannel>[
    _DiscussionChannel(
      id: 'national',
      name: 'National Operations',
      description: 'Cross-team operational coordination',
      icon: Icons.public_rounded,
    ),
    _DiscussionChannel(
      id: 'situation',
      name: 'Situation Room',
      description: 'Incidents, escalation and response',
      icon: Icons.radar_rounded,
    ),
    _DiscussionChannel(
      id: 'field',
      name: 'Field Support',
      description: 'Agent support and field updates',
      icon: Icons.support_agent_rounded,
    ),
    _DiscussionChannel(
      id: 'legal',
      name: 'Legal & Evidence',
      description: 'Evidence, disputes and documentation',
      icon: Icons.gavel_rounded,
    ),
  ];

  late final List<_DiscussionThread> threads = [
    _DiscussionThread(
      id: 'THR-1001',
      channelId: 'national',
      title: 'Morning operational coordination',
      body:
          'Please confirm opening-status coverage, agent availability and any priority support requirement from your assigned geography.',
      author: 'National Operations Desk',
      role: 'Situation Room',
      time: '08:05',
      pinned: true,
      replies: const [
        _DiscussionReply(
          author: 'North West Desk',
          role: 'Zonal Coordination',
          body: 'Coverage check completed. Priority items have been routed to the relevant state desks.',
          time: '08:18',
        ),
        _DiscussionReply(
          author: 'Technical Support',
          role: 'Support Desk',
          body: 'Field support queue is active and device-access requests are being handled by assignment.',
          time: '08:24',
        ),
      ],
    ),
    _DiscussionThread(
      id: 'THR-1002',
      channelId: 'situation',
      title: 'Incident escalation checklist',
      body:
          'For high-priority incidents, include the polling-unit reference, observable facts, evidence reference and current response owner before escalation.',
      author: 'Situation Room Director',
      role: 'Command',
      time: '08:32',
      replies: const [
        _DiscussionReply(
          author: 'State Coordination Desk',
          role: 'State Coordinator',
          body: 'Checklist acknowledged. Open incidents are being reviewed against the required fields.',
          time: '08:41',
        ),
      ],
    ),
    _DiscussionThread(
      id: 'THR-1003',
      channelId: 'field',
      title: 'Agent support requests',
      body:
          'Use this thread for access, assignment, device and communications support affecting field operations.',
      author: 'Field Support Desk',
      role: 'Technical Support',
      time: '08:47',
      replies: const [
        _DiscussionReply(
          author: 'LGA Coordinator',
          role: 'LGA Coordination',
          body: 'One assignment clarification has been forwarded with the agent ID and polling-unit code.',
          time: '08:53',
        ),
      ],
    ),
    _DiscussionThread(
      id: 'THR-1004',
      channelId: 'legal',
      title: 'Evidence review handoff',
      body:
          'Items sent for legal review should retain the original evidence reference, submission ID and reviewer notes.',
      author: 'Legal Desk',
      role: 'Legal Officer',
      time: '09:02',
      replies: const [],
    ),
  ];

  @override
  void dispose() {
    replyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final canCreate = TgcgPermissionPolicy.allows(
      session.role!,
      TgcgCapability.createDiscussionThread,
    );
    final canReply = TgcgPermissionPolicy.allows(
      session.role!,
      TgcgCapability.postDiscussionReply,
    );

    final normalized = search.trim().toLowerCase();
    final visibleThreads = threads.where((thread) {
      if (thread.channelId != selectedChannelId) return false;
      if (normalized.isEmpty) return true;
      return thread.title.toLowerCase().contains(normalized) ||
          thread.body.toLowerCase().contains(normalized) ||
          thread.author.toLowerCase().contains(normalized);
    }).toList(growable: false)
      ..sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        return b.id.compareTo(a.id);
      });

    _DiscussionThread? selected;
    for (final thread in threads) {
      if (thread.id == selectedThreadId) {
        selected = thread;
        break;
      }
    }
    if (selected != null && selected.channelId != selectedChannelId) {
      selected = null;
    }

    final channel = channels.firstWhere((item) => item.id == selectedChannelId);
    final totalReplies = threads.fold<int>(0, (sum, item) => sum + item.replies.length);
    final pinned = threads.where((item) => item.pinned).length;
    final resolved = threads.where((item) => item.resolved).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
      children: [
        TgcgPageHeader(
          eyebrow: 'TEAM COLLABORATION',
          title: 'Discussion Room',
          subtitle:
              '${session.scope.label}: internal operational discussions, handoffs and team coordination.',
          trailing: canCreate
              ? FilledButton.icon(
                  onPressed: () => _openNewThread(context, session),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('New discussion'),
                )
              : const TgcgStatusPill(
                  label: 'READ ONLY',
                  color: TgcgColors.muted,
                  icon: Icons.visibility_outlined,
                ),
        ),
        const SizedBox(height: 18),
        _DiscussionMetrics(
          channels: channels.length,
          threads: threads.length,
          replies: totalReplies,
          pinned: pinned,
          resolved: resolved,
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final channelRail = _ChannelRail(
              channels: channels,
              selectedId: selectedChannelId,
              threadCounts: {
                for (final item in channels)
                  item.id: threads.where((thread) => thread.channelId == item.id).length,
              },
              onSelect: (id) => setState(() {
                selectedChannelId = id;
                selectedThreadId = threads
                    .where((thread) => thread.channelId == id)
                    .map((thread) => thread.id)
                    .firstOrNull;
              }),
            );
            final threadList = _ThreadList(
              channel: channel,
              threads: visibleThreads,
              selectedId: selectedThreadId,
              search: search,
              onSearchChanged: (value) => setState(() => search = value),
              onSelect: (id) => setState(() => selectedThreadId = id),
            );
            final conversation = _ThreadDetail(
              thread: selected,
              canReply: canReply,
              replyController: replyController,
              onReply: selected == null
                  ? null
                  : () => _postReply(context, session, selected!),
              onToggleResolved: selected == null || !canCreate
                  ? null
                  : () => setState(() => selected!.resolved = !selected!.resolved),
            );

            if (constraints.maxWidth < 760) {
              return Column(
                children: [
                  channelRail,
                  const SizedBox(height: 14),
                  threadList,
                  const SizedBox(height: 14),
                  conversation,
                ],
              );
            }
            if (constraints.maxWidth < 1120) {
              return Column(
                children: [
                  channelRail,
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 5, child: threadList),
                      const SizedBox(width: 14),
                      Expanded(flex: 7, child: conversation),
                    ],
                  ),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 260, child: channelRail),
                const SizedBox(width: 14),
                Expanded(flex: 5, child: threadList),
                const SizedBox(width: 14),
                Expanded(flex: 7, child: conversation),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _openNewThread(
    BuildContext context,
    TgcgSessionController session,
  ) async {
    final title = TextEditingController();
    final body = TextEditingController();
    var channelId = selectedChannelId;

    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('New discussion'),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: channelId,
                  decoration: const InputDecoration(labelText: 'Room'),
                  items: channels
                      .map(
                        (channel) => DropdownMenuItem(
                          value: channel.id,
                          child: Text(channel.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setDialogState(
                    () => channelId = value ?? channelId,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: 'Discussion title'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: body,
                  maxLines: 5,
                  decoration: const InputDecoration(labelText: 'Message'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () {
                if (title.text.trim().isEmpty || body.text.trim().isEmpty) return;
                Navigator.pop(dialogContext, true);
              },
              icon: const Icon(Icons.forum_outlined),
              label: const Text('Create discussion'),
            ),
          ],
        ),
      ),
    );

    if (created == true) {
      final id = 'THR-${1000 + threads.length + 1}';
      setState(() {
        selectedChannelId = channelId;
        selectedThreadId = id;
        threads.insert(
          0,
          _DiscussionThread(
            id: id,
            channelId: channelId,
            title: title.text.trim(),
            body: body.text.trim(),
            author: session.operatorName,
            role: roleLabel(session.role!),
            time: _currentTime(),
            replies: [],
          ),
        );
      });
    }
    title.dispose();
    body.dispose();
  }

  void _postReply(
    BuildContext context,
    TgcgSessionController session,
    _DiscussionThread thread,
  ) {
    final body = replyController.text.trim();
    if (body.isEmpty) return;
    setState(() {
      thread.replies.add(
        _DiscussionReply(
          author: session.operatorName,
          role: roleLabel(session.role!),
          body: body,
          time: _currentTime(),
        ),
      );
      replyController.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Reply posted.')),
    );
  }
}

class _DiscussionMetrics extends StatelessWidget {
  const _DiscussionMetrics({
    required this.channels,
    required this.threads,
    required this.replies,
    required this.pinned,
    required this.resolved,
  });

  final int channels;
  final int threads;
  final int replies;
  final int pinned;
  final int resolved;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 1050
              ? 5
              : constraints.maxWidth >= 650
                  ? 3
                  : constraints.maxWidth >= 430
                      ? 2
                      : 1;
          const gap = 12.0;
          final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              TgcgMetricCard(
                width: width,
                label: 'Rooms',
                value: '$channels',
                detail: 'Operational discussion spaces',
                icon: Icons.forum_outlined,
                tone: TgcgMetricTone.info,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Discussions',
                value: '$threads',
                detail: 'Active coordination threads',
                icon: Icons.chat_bubble_outline_rounded,
                tone: TgcgMetricTone.neutral,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Replies',
                value: '$replies',
                detail: 'Team responses across rooms',
                icon: Icons.reply_all_rounded,
                tone: TgcgMetricTone.success,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Pinned',
                value: '$pinned',
                detail: 'Priority coordination threads',
                icon: Icons.push_pin_outlined,
                tone: TgcgMetricTone.warning,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Resolved',
                value: '$resolved',
                detail: 'Closed operational discussions',
                icon: Icons.task_alt_rounded,
                tone: TgcgMetricTone.success,
              ),
            ],
          );
        },
      );
}

class _ChannelRail extends StatelessWidget {
  const _ChannelRail({
    required this.channels,
    required this.selectedId,
    required this.threadCounts,
    required this.onSelect,
  });

  final List<_DiscussionChannel> channels;
  final String selectedId;
  final Map<String, int> threadCounts;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Discussion rooms',
        subtitle: 'Choose a coordination space.',
        child: Column(
          children: channels.map((channel) {
            final selected = channel.id == selectedId;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => onSelect(channel.id),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: selected ? TgcgColors.primarySoft : TgcgColors.surfaceSoft,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected
                          ? TgcgColors.primary.withValues(alpha: .25)
                          : TgcgColors.border,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: (selected ? TgcgColors.primary : TgcgColors.muted)
                              .withValues(alpha: .10),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(
                          channel.icon,
                          color: selected ? TgcgColors.primary : TgcgColors.muted,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              channel.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: TgcgColors.ink,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${threadCounts[channel.id] ?? 0} discussions',
                              style: const TextStyle(
                                color: TgcgColors.muted,
                                fontSize: 9,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      );
}

class _ThreadList extends StatelessWidget {
  const _ThreadList({
    required this.channel,
    required this.threads,
    required this.selectedId,
    required this.search,
    required this.onSearchChanged,
    required this.onSelect,
  });

  final _DiscussionChannel channel;
  final List<_DiscussionThread> threads;
  final String? selectedId;
  final String search;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: channel.name,
        subtitle: channel.description,
        child: Column(
          children: [
            TextFormField(
              initialValue: search,
              onChanged: onSearchChanged,
              decoration: const InputDecoration(
                hintText: 'Search discussions',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 12),
            if (threads.isEmpty)
              const TgcgEmptyState(
                icon: Icons.forum_outlined,
                title: 'No discussions found',
                message: 'Start a discussion or adjust your search.',
              )
            else
              ...threads.map(
                (thread) => _ThreadTile(
                  thread: thread,
                  selected: thread.id == selectedId,
                  onTap: () => onSelect(thread.id),
                ),
              ),
          ],
        ),
      );
}

class _ThreadTile extends StatelessWidget {
  const _ThreadTile({
    required this.thread,
    required this.selected,
    required this.onTap,
  });

  final _DiscussionThread thread;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Material(
          color: selected ? TgcgColors.primarySoft : TgcgColors.surfaceSoft,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected
                      ? TgcgColors.primary.withValues(alpha: .24)
                      : TgcgColors.border,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (thread.pinned) ...[
                        const Icon(
                          Icons.push_pin_rounded,
                          color: TgcgColors.accent,
                          size: 15,
                        ),
                        const SizedBox(width: 5),
                      ],
                      Expanded(
                        child: Text(
                          thread.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: TgcgColors.ink,
                            fontSize: 11,
                            height: 1.3,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      if (thread.resolved)
                        const TgcgStatusPill(
                          label: 'RESOLVED',
                          color: TgcgColors.success,
                          compact: true,
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    thread.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: TgcgColors.muted,
                      fontSize: 9.5,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${thread.author} • ${thread.time}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: TgcgColors.muted,
                            fontSize: 9,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 13,
                        color: TgcgColors.muted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${thread.replies.length}',
                        style: const TextStyle(
                          color: TgcgColors.muted,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _ThreadDetail extends StatelessWidget {
  const _ThreadDetail({
    required this.thread,
    required this.canReply,
    required this.replyController,
    required this.onReply,
    required this.onToggleResolved,
  });

  final _DiscussionThread? thread;
  final bool canReply;
  final TextEditingController replyController;
  final VoidCallback? onReply;
  final VoidCallback? onToggleResolved;

  @override
  Widget build(BuildContext context) {
    final item = thread;
    return TgcgSectionCard(
      title: 'Conversation',
      subtitle: 'Threaded operational discussion and handoff history.',
      trailing: item == null || onToggleResolved == null
          ? null
          : TextButton.icon(
              onPressed: onToggleResolved,
              icon: Icon(
                item.resolved ? Icons.replay_rounded : Icons.task_alt_rounded,
                size: 17,
              ),
              label: Text(item.resolved ? 'Reopen' : 'Resolve'),
            ),
      child: item == null
          ? const TgcgEmptyState(
              icon: Icons.touch_app_outlined,
              title: 'Select a discussion',
              message: 'Choose a discussion to view the conversation.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MessageCard(
                  author: item.author,
                  role: item.role,
                  body: item.body,
                  time: item.time,
                  primary: true,
                ),
                if (item.replies.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ...item.replies.map(
                    (reply) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _MessageCard(
                        author: reply.author,
                        role: reply.role,
                        body: reply.body,
                        time: reply.time,
                      ),
                    ),
                  ),
                ],
                if (canReply && !item.resolved) ...[
                  const Divider(height: 28),
                  TextField(
                    controller: replyController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'Write a reply…',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: onReply,
                      icon: const Icon(Icons.send_rounded, size: 18),
                      label: const Text('Post reply'),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.author,
    required this.role,
    required this.body,
    required this.time,
    this.primary = false,
  });

  final String author;
  final String role;
  final String body;
  final String time;
  final bool primary;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: primary ? TgcgColors.primarySoft : TgcgColors.surfaceSoft,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: primary
                ? TgcgColors.primary.withValues(alpha: .18)
                : TgcgColors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: TgcgColors.primary.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.person_outline_rounded,
                    color: TgcgColors.primary,
                    size: 17,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        author,
                        style: const TextStyle(
                          color: TgcgColors.ink,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        role,
                        style: const TextStyle(
                          color: TgcgColors.muted,
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  time,
                  style: const TextStyle(
                    color: TgcgColors.muted,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              body,
              style: const TextStyle(
                color: TgcgColors.ink,
                fontSize: 11,
                height: 1.5,
              ),
            ),
          ],
        ),
      );
}

String _currentTime() {
  final now = DateTime.now();
  final hour = now.hour.toString().padLeft(2, '0');
  final minute = now.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
