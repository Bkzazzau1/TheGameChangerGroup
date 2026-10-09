import 'package:flutter/material.dart';

import '../communications/communications_store.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';

class FieldAgentCommunicationsPage extends StatefulWidget {
  const FieldAgentCommunicationsPage({super.key});

  @override
  State<FieldAgentCommunicationsPage> createState() =>
      _FieldAgentCommunicationsPageState();
}

class _FieldAgentCommunicationsPageState
    extends State<FieldAgentCommunicationsPage> {
  final messageController = TextEditingController();
  String? selectedRoomId;

  @override
  void dispose() {
    messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final store = Communications.of(context);
    final rooms = store.localRoomsForFieldAgent(session.scope);

    if (rooms.isNotEmpty && !rooms.any((room) => room.id == selectedRoomId)) {
      selectedRoomId = rooms.first.id;
    }

    OperationalRoom? selectedRoom;
    for (final room in rooms) {
      if (room.id == selectedRoomId) {
        selectedRoom = room;
        break;
      }
    }

    final messages = selectedRoom == null
        ? const <OperationalMessage>[]
        : store.messagesForRoom(selectedRoom.id);

    return Column(
      children: [
        _Header(
          ward: session.scope.wardName ?? 'Assigned ward',
          lga: session.scope.lgaName ?? 'Assigned LGA',
          rooms: rooms.length,
        ),
        if (rooms.isNotEmpty)
          _RoomSelector(
            rooms: rooms,
            selectedRoomId: selectedRoomId,
            onSelect: (id) => setState(() => selectedRoomId = id),
          ),
        Expanded(
          child: selectedRoom == null
              ? const TgcgEmptyState(
                  icon: Icons.chat_bubble_outline_rounded,
                  title: 'No local room available',
                  message: 'Local operational rooms will appear here.',
                )
              : _Conversation(
                  room: selectedRoom,
                  messages: messages,
                  currentUser: session.accessId,
                ),
        ),
        if (selectedRoom != null)
          _Composer(
            controller: messageController,
            onSend: () => _send(context, store, session, selectedRoom!),
          ),
      ],
    );
  }

  void _send(
    BuildContext context,
    CommunicationsController store,
    TgcgSessionController session,
    OperationalRoom room,
  ) {
    final text = messageController.text.trim();
    if (text.isEmpty) return;
    final ok = store.sendMessage(
      roomId: room.id,
      senderId: session.accessId.isEmpty ? session.operatorName : session.accessId,
      body: text,
      role: session.role!,
      userScope: session.scope,
    );
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This message is outside your local area.')),
      );
      return;
    }
    messageController.clear();
    setState(() {});
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.ward,
    required this.lga,
    required this.rooms,
  });

  final String ward;
  final String lga;
  final int rooms;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [TgcgColors.primaryDark, TgcgColors.primary],
          ),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.forum_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Local Messages',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$ward • $lga',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFC7CCD8),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$rooms ROOMS',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      );
}

class _RoomSelector extends StatelessWidget {
  const _RoomSelector({
    required this.rooms,
    required this.selectedRoomId,
    required this.onSelect,
  });

  final List<OperationalRoom> rooms;
  final String? selectedRoomId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 48,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          scrollDirection: Axis.horizontal,
          itemCount: rooms.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final room = rooms[index];
            final active = room.id == selectedRoomId;
            return ChoiceChip(
              selected: active,
              onSelected: (_) => onSelect(room.id),
              avatar: Icon(
                room.type == CommunicationRoomType.ward
                    ? Icons.groups_2_outlined
                    : Icons.hub_outlined,
                size: 16,
                color: active ? Colors.white : TgcgColors.primary,
              ),
              label: Text(room.name),
              labelStyle: TextStyle(
                color: active ? Colors.white : TgcgColors.ink,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
              selectedColor: TgcgColors.primary,
              backgroundColor: TgcgColors.surface,
              side: const BorderSide(color: TgcgColors.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            );
          },
        ),
      );
}

class _Conversation extends StatelessWidget {
  const _Conversation({
    required this.room,
    required this.messages,
    required this.currentUser,
  });

  final OperationalRoom room;
  final List<OperationalMessage> messages;
  final String currentUser;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: TgcgColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: TgcgColors.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.lock_outline_rounded,
                    size: 17, color: TgcgColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    room.scope.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: TgcgColors.ink,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const Text(
                  'LOCAL AREA',
                  style: TextStyle(
                    color: TgcgColors.primary,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: messages.isEmpty
                ? const TgcgEmptyState(
                    icon: Icons.chat_bubble_outline_rounded,
                    title: 'Start the conversation',
                    message: 'Messages to your local team will appear here.',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      final mine = currentUser.isNotEmpty &&
                          message.senderId.toLowerCase() ==
                              currentUser.toLowerCase();
                      return _MessageBubble(message: message, mine: mine);
                    },
                  ),
          ),
        ],
      );
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.mine});

  final OperationalMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) => Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(13, 10, 13, 8),
          decoration: BoxDecoration(
            color: mine ? TgcgColors.primary : TgcgColors.surface,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(mine ? 16 : 4),
              bottomRight: Radius.circular(mine ? 4 : 16),
            ),
            border: mine ? null : Border.all(color: TgcgColors.border),
          ),
          child: Column(
            crossAxisAlignment:
                mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (!mine) ...[
                Text(
                  message.senderId,
                  style: const TextStyle(
                    color: TgcgColors.primary,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
              ],
              Text(
                message.body,
                style: TextStyle(
                  color: mine ? Colors.white : TgcgColors.ink,
                  fontSize: 11,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                _time(message.createdAt),
                style: TextStyle(
                  color: mine
                      ? Colors.white.withValues(alpha: .68)
                      : TgcgColors.muted,
                  fontSize: 8,
                ),
              ),
            ],
          ),
        ),
      );
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.onSend});

  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: const BoxDecoration(
            color: TgcgColors.surface,
            border: Border(top: BorderSide(color: TgcgColors.border)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: TgcgColors.surfaceSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.add_rounded,
                    color: TgcgColors.primary, size: 20),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 4,
                  onSubmitted: (_) => onSend(),
                  decoration: const InputDecoration(
                    hintText: 'Message your local team…',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: onSend,
                icon: const Icon(Icons.send_rounded),
              ),
            ],
          ),
        ),
      );
}

String _time(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
