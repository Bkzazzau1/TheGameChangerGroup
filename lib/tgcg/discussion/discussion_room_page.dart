import 'package:flutter/material.dart';

import '../domain/permissions.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';

class DiscussionRoomPage extends StatefulWidget {
  const DiscussionRoomPage({super.key});

  @override
  State<DiscussionRoomPage> createState() => _DiscussionRoomPageState();
}

class _Room {
  const _Room(this.id, this.name, this.subtitle, this.icon);
  final String id;
  final String name;
  final String subtitle;
  final IconData icon;
}

class _Reply {
  const _Reply(this.author, this.role, this.body, this.time);
  final String author;
  final String role;
  final String body;
  final String time;
}

class _Thread {
  _Thread({
    required this.id,
    required this.roomId,
    required this.title,
    required this.body,
    required this.author,
    required this.role,
    required this.time,
    List<_Reply>? replies,
    this.pinned = false,
    this.resolved = false,
  }) : replies = List<_Reply>.of(replies ?? const []);

  final String id;
  final String roomId;
  final String title;
  final String body;
  final String author;
  final String role;
  final String time;
  final List<_Reply> replies;
  bool pinned;
  bool resolved;
}

class _DiscussionRoomPageState extends State<DiscussionRoomPage> {
  static const rooms = [
    _Room('national', 'National Operations', 'Cross-team coordination', Icons.public_rounded),
    _Room('situation', 'Situation Room', 'Incident and response coordination', Icons.radar_rounded),
    _Room('field', 'Field Support', 'Agent support and field updates', Icons.support_agent_rounded),
    _Room('legal', 'Legal & Evidence', 'Evidence and documentation', Icons.gavel_rounded),
  ];

  final replyController = TextEditingController();
  String selectedRoomId = 'national';
  String? selectedThreadId = 'THR-1001';
  String search = '';

  late final List<_Thread> threads = [
    _Thread(
      id: 'THR-1001',
      roomId: 'national',
      title: 'Morning operational coordination',
      body:
          'Confirm opening-status coverage, agent availability and priority support requirements from each assigned geography.',
      author: 'National Operations Desk',
      role: 'Situation Room',
      time: '08:05',
      pinned: true,
      replies: const [
        _Reply(
          'North West Desk',
          'Zonal Coordination',
          'Coverage check completed. Priority items have been routed to the relevant state desks.',
          '08:18',
        ),
        _Reply(
          'Technical Support',
          'Support Desk',
          'Field support queue is active and device-access requests are being handled by assignment.',
          '08:24',
        ),
      ],
    ),
    _Thread(
      id: 'THR-1002',
      roomId: 'situation',
      title: 'Incident escalation checklist',
      body:
          'High-priority incidents should include the polling-unit reference, observable facts, evidence reference and current response owner.',
      author: 'Situation Room Director',
      role: 'Command',
      time: '08:32',
      replies: const [
        _Reply(
          'State Coordination Desk',
          'State Coordinator',
          'Checklist acknowledged. Open incidents are being reviewed against the required fields.',
          '08:41',
        ),
      ],
    ),
    _Thread(
      id: 'THR-1003',
      roomId: 'field',
      title: 'Agent support requests',
      body:
          'Use this discussion for access, assignment, device and communications support affecting field operations.',
      author: 'Field Support Desk',
      role: 'Technical Support',
      time: '08:47',
      replies: const [
        _Reply(
          'LGA Coordinator',
          'LGA Coordination',
          'One assignment clarification has been forwarded with the agent ID and polling-unit code.',
          '08:53',
        ),
      ],
    ),
    _Thread(
      id: 'THR-1004',
      roomId: 'legal',
      title: 'Evidence review handoff',
      body:
          'Items sent for legal review should retain the original evidence reference, submission ID and reviewer notes.',
      author: 'Legal Desk',
      role: 'Legal Officer',
      time: '09:02',
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
    final room = rooms.firstWhere((item) => item.id == selectedRoomId);
    final q = search.trim().toLowerCase();
    final visible = threads.where((item) {
      if (item.roomId != selectedRoomId) return false;
      return q.isEmpty ||
          item.title.toLowerCase().contains(q) ||
          item.body.toLowerCase().contains(q) ||
          item.author.toLowerCase().contains(q);
    }).toList()
      ..sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        return b.id.compareTo(a.id);
      });

    _Thread? selected;
    for (final item in threads) {
      if (item.id == selectedThreadId && item.roomId == selectedRoomId) {
        selected = item;
        break;
      }
    }

    final totalReplies = threads.fold<int>(0, (sum, item) => sum + item.replies.length);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
      children: [
        TgcgPageHeader(
          eyebrow: 'TEAM COLLABORATION',
          title: 'Discussion Room',
          subtitle:
              '${session.scope.label}: internal discussions, operational handoffs and team coordination.',
          trailing: canCreate
              ? FilledButton.icon(
                  onPressed: () => _newDiscussion(context, session),
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
        _Metrics(
          rooms: rooms.length,
          discussions: threads.length,
          replies: totalReplies,
          pinned: threads.where((item) => item.pinned).length,
          resolved: threads.where((item) => item.resolved).length,
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final roomRail = _RoomRail(
              rooms: rooms,
              selectedId: selectedRoomId,
              counts: {
                for (final item in rooms)
                  item.id: threads.where((thread) => thread.roomId == item.id).length,
              },
              onSelect: (id) => setState(() {
                selectedRoomId = id;
                selectedThreadId = null;
              }),
            );
            final list = _ThreadList(
              room: room,
              threads: visible,
              selectedId: selectedThreadId,
              onSearch: (value) => setState(() => search = value),
              onSelect: (id) => setState(() => selectedThreadId = id),
            );
            final detail = _ThreadDetail(
              thread: selected,
              canReply: canReply,
              controller: replyController,
              onReply: selected == null
                  ? null
                  : () => _reply(context, session, selected!),
              onResolve: selected == null || !canCreate
                  ? null
                  : () => setState(() => selected!.resolved = !selected!.resolved),
            );

            if (constraints.maxWidth < 760) {
              return Column(
                children: [roomRail, const SizedBox(height: 14), list, const SizedBox(height: 14), detail],
              );
            }
            if (constraints.maxWidth < 1120) {
              return Column(
                children: [
                  roomRail,
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 5, child: list),
                      const SizedBox(width: 14),
                      Expanded(flex: 7, child: detail),
                    ],
                  ),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 260, child: roomRail),
                const SizedBox(width: 14),
                Expanded(flex: 5, child: list),
                const SizedBox(width: 14),
                Expanded(flex: 7, child: detail),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _newDiscussion(
    BuildContext context,
    TgcgSessionController session,
  ) async {
    final title = TextEditingController();
    final body = TextEditingController();
    var roomId = selectedRoomId;
    final create = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('New discussion'),
          content: SizedBox(
            width: 540,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: roomId,
                  decoration: const InputDecoration(labelText: 'Room'),
                  items: rooms
                      .map((item) => DropdownMenuItem(value: item.id, child: Text(item.name)))
                      .toList(),
                  onChanged: (value) => setDialogState(() => roomId = value ?? roomId),
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
              label: const Text('Create'),
            ),
          ],
        ),
      ),
    );

    if (create == true) {
      final id = 'THR-${1000 + threads.length + 1}';
      setState(() {
        selectedRoomId = roomId;
        selectedThreadId = id;
        threads.insert(
          0,
          _Thread(
            id: id,
            roomId: roomId,
            title: title.text.trim(),
            body: body.text.trim(),
            author: session.operatorName,
            role: roleLabel(session.role!),
            time: _timeNow(),
          ),
        );
      });
    }
    title.dispose();
    body.dispose();
  }

  void _reply(
    BuildContext context,
    TgcgSessionController session,
    _Thread thread,
  ) {
    final text = replyController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      thread.replies.add(_Reply(session.operatorName, roleLabel(session.role!), text, _timeNow()));
      replyController.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Reply posted.')),
    );
  }
}

class _Metrics extends StatelessWidget {
  const _Metrics({
    required this.rooms,
    required this.discussions,
    required this.replies,
    required this.pinned,
    required this.resolved,
  });
  final int rooms;
  final int discussions;
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
              TgcgMetricCard(width: width, label: 'Rooms', value: '$rooms', detail: 'Operational discussion spaces', icon: Icons.forum_outlined, tone: TgcgMetricTone.info),
              TgcgMetricCard(width: width, label: 'Discussions', value: '$discussions', detail: 'Coordination threads', icon: Icons.chat_bubble_outline_rounded, tone: TgcgMetricTone.neutral),
              TgcgMetricCard(width: width, label: 'Replies', value: '$replies', detail: 'Team responses', icon: Icons.reply_all_rounded, tone: TgcgMetricTone.success),
              TgcgMetricCard(width: width, label: 'Pinned', value: '$pinned', detail: 'Priority discussions', icon: Icons.push_pin_outlined, tone: TgcgMetricTone.warning),
              TgcgMetricCard(width: width, label: 'Resolved', value: '$resolved', detail: 'Closed discussions', icon: Icons.task_alt_rounded, tone: TgcgMetricTone.success),
            ],
          );
        },
      );
}

class _RoomRail extends StatelessWidget {
  const _RoomRail({required this.rooms, required this.selectedId, required this.counts, required this.onSelect});
  final List<_Room> rooms;
  final String selectedId;
  final Map<String, int> counts;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Discussion rooms',
        subtitle: 'Choose a coordination space.',
        child: Column(
          children: rooms.map((room) {
            final active = room.id == selectedId;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => onSelect(room.id),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: active ? TgcgColors.primarySoft : TgcgColors.surfaceSoft,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: active ? TgcgColors.primary.withValues(alpha: .25) : TgcgColors.border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: (active ? TgcgColors.primary : TgcgColors.muted).withValues(alpha: .10),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(room.icon, color: active ? TgcgColors.primary : TgcgColors.muted, size: 18),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(room.name, style: const TextStyle(color: TgcgColors.ink, fontSize: 10.5, fontWeight: FontWeight.w900)),
                            const SizedBox(height: 2),
                            Text('${counts[room.id] ?? 0} discussions', style: const TextStyle(color: TgcgColors.muted, fontSize: 9)),
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
  const _ThreadList({required this.room, required this.threads, required this.selectedId, required this.onSearch, required this.onSelect});
  final _Room room;
  final List<_Thread> threads;
  final String? selectedId;
  final ValueChanged<String> onSearch;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: room.name,
        subtitle: room.subtitle,
        child: Column(
          children: [
            TextField(
              onChanged: onSearch,
              decoration: const InputDecoration(hintText: 'Search discussions', prefixIcon: Icon(Icons.search_rounded)),
            ),
            const SizedBox(height: 12),
            if (threads.isEmpty)
              const TgcgEmptyState(icon: Icons.forum_outlined, title: 'No discussions found', message: 'Start a discussion or adjust your search.')
            else
              ...threads.map((thread) => _ThreadTile(thread: thread, selected: thread.id == selectedId, onTap: () => onSelect(thread.id))),
          ],
        ),
      );
}

class _ThreadTile extends StatelessWidget {
  const _ThreadTile({required this.thread, required this.selected, required this.onTap});
  final _Thread thread;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: selected ? TgcgColors.primarySoft : TgcgColors.surfaceSoft,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: selected ? TgcgColors.primary.withValues(alpha: .24) : TgcgColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (thread.pinned) ...[
                      const Icon(Icons.push_pin_rounded, color: TgcgColors.accent, size: 15),
                      const SizedBox(width: 5),
                    ],
                    Expanded(child: Text(thread.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: TgcgColors.ink, fontSize: 11, fontWeight: FontWeight.w900))),
                    if (thread.resolved)
                      const TgcgStatusPill(label: 'RESOLVED', color: TgcgColors.success, compact: true),
                  ],
                ),
                const SizedBox(height: 6),
                Text(thread.body, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: TgcgColors.muted, fontSize: 9.5, height: 1.4)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: Text('${thread.author} • ${thread.time}', overflow: TextOverflow.ellipsis, style: const TextStyle(color: TgcgColors.muted, fontSize: 9))),
                    const Icon(Icons.chat_bubble_outline_rounded, size: 13, color: TgcgColors.muted),
                    const SizedBox(width: 4),
                    Text('${thread.replies.length}', style: const TextStyle(color: TgcgColors.muted, fontSize: 9, fontWeight: FontWeight.w800)),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
}

class _ThreadDetail extends StatelessWidget {
  const _ThreadDetail({required this.thread, required this.canReply, required this.controller, required this.onReply, required this.onResolve});
  final _Thread? thread;
  final bool canReply;
  final TextEditingController controller;
  final VoidCallback? onReply;
  final VoidCallback? onResolve;

  @override
  Widget build(BuildContext context) {
    final item = thread;
    return TgcgSectionCard(
      title: 'Conversation',
      subtitle: 'Threaded operational discussion and handoff history.',
      trailing: item == null || onResolve == null
          ? null
          : TextButton.icon(
              onPressed: onResolve,
              icon: Icon(item.resolved ? Icons.replay_rounded : Icons.task_alt_rounded, size: 17),
              label: Text(item.resolved ? 'Reopen' : 'Resolve'),
            ),
      child: item == null
          ? const TgcgEmptyState(icon: Icons.touch_app_outlined, title: 'Select a discussion', message: 'Choose a discussion to view the conversation.')
          : Column(
              children: [
                _Message(author: item.author, role: item.role, body: item.body, time: item.time, primary: true),
                if (item.replies.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ...item.replies.map((reply) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _Message(author: reply.author, role: reply.role, body: reply.body, time: reply.time),
                      )),
                ],
                if (canReply && !item.resolved) ...[
                  const Divider(height: 28),
                  TextField(controller: controller, maxLines: 3, decoration: const InputDecoration(hintText: 'Write a reply…')),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(onPressed: onReply, icon: const Icon(Icons.send_rounded, size: 18), label: const Text('Post reply')),
                  ),
                ],
              ],
            ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.author, required this.role, required this.body, required this.time, this.primary = false});
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
          border: Border.all(color: primary ? TgcgColors.primary.withValues(alpha: .18) : TgcgColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(color: TgcgColors.primary.withValues(alpha: .10), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.person_outline_rounded, color: TgcgColors.primary, size: 17),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(author, style: const TextStyle(color: TgcgColors.ink, fontSize: 10.5, fontWeight: FontWeight.w900)),
                      Text(role, style: const TextStyle(color: TgcgColors.muted, fontSize: 9)),
                    ],
                  ),
                ),
                Text(time, style: const TextStyle(color: TgcgColors.muted, fontSize: 9)),
              ],
            ),
            const SizedBox(height: 10),
            Text(body, style: const TextStyle(color: TgcgColors.ink, fontSize: 11, height: 1.5)),
          ],
        ),
      );
}

String _timeNow() {
  final now = DateTime.now();
  return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
}
