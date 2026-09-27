import 'package:flutter/material.dart';

import '../app.dart';
import '../domain/models.dart';
import '../domain/permissions.dart';
import '../session.dart';
import 'communications_store.dart';

class CommunicationsPage extends StatefulWidget {
  const CommunicationsPage({super.key});

  @override
  State<CommunicationsPage> createState() => _CommunicationsPageState();
}

class _CommunicationsPageState extends State<CommunicationsPage> {
  final messageController = TextEditingController();
  final broadcastTitleController = TextEditingController();
  final broadcastBodyController = TextEditingController();
  String? selectedRoomId;

  @override
  void dispose() {
    messageController.dispose();
    broadcastTitleController.dispose();
    broadcastBodyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final store = Communications.of(context);
    final rooms = store.roomsForScope(session.scope);
    final broadcasts = store.broadcastsForScope(session.scope);

    if (rooms.isNotEmpty && !rooms.any((room) => room.id == selectedRoomId)) {
      selectedRoomId = rooms.first.id;
    }
    final selectedRoom = rooms.where((room) => room.id == selectedRoomId).firstOrNull;
    final messages = selectedRoom == null
        ? const <OperationalMessage>[]
        : store.messagesForRoom(selectedRoom.id);
    final canSend = TgcgPermissionPolicy.allows(
      session.role!,
      TgcgCapability.sendOperationalMessage,
    );
    final canBroadcast = TgcgPermissionPolicy.allows(
      session.role!,
      TgcgCapability.sendBroadcast,
    );

    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        const Text(
          'Communications',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: TgcgApp.ink,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          '${session.scope.label}: scoped operational rooms, coordination messages and authorized broadcasts.',
          style: const TextStyle(color: TgcgApp.muted, height: 1.5),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final roomPanel = _RoomPanel(
              rooms: rooms,
              selectedRoomId: selectedRoomId,
              onSelect: (id) => setState(() => selectedRoomId = id),
            );
            final conversation = _ConversationPanel(
              room: selectedRoom,
              messages: messages,
              controller: messageController,
              canSend: canSend,
              onSend: selectedRoom == null
                  ? null
                  : () {
                      final ok = store.sendMessage(
                        roomId: selectedRoom.id,
                        senderId: session.accessId.isEmpty
                            ? session.operatorName
                            : session.accessId,
                        body: messageController.text,
                        role: session.role!,
                        userScope: session.scope,
                      );
                      if (ok) {
                        messageController.clear();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Message saved locally and queued for delivery.'),
                          ),
                        );
                      }
                    },
            );
            if (constraints.maxWidth < 920) {
              return Column(
                children: [
                  roomPanel,
                  const SizedBox(height: 14),
                  conversation,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 310, child: roomPanel),
                const SizedBox(width: 14),
                Expanded(child: conversation),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _BroadcastPanel(
          broadcasts: broadcasts,
          titleController: broadcastTitleController,
          bodyController: broadcastBodyController,
          canBroadcast: canBroadcast,
          onBroadcast: () {
            final ok = store.sendBroadcast(
              title: broadcastTitleController.text,
              body: broadcastBodyController.text,
              targetScope: session.scope,
              senderId: session.accessId.isEmpty
                  ? session.operatorName
                  : session.accessId,
              role: session.role!,
              userScope: session.scope,
            );
            if (ok) {
              broadcastTitleController.clear();
              broadcastBodyController.clear();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Broadcast queued for authorized delivery.'),
                ),
              );
            }
          },
        ),
      ],
    );
  }
}

class _RoomPanel extends StatelessWidget {
  const _RoomPanel({
    required this.rooms,
    required this.selectedRoomId,
    required this.onSelect,
  });

  final List<OperationalRoom> rooms;
  final String? selectedRoomId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Operational rooms',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: TgcgApp.ink,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Rooms are filtered to geographic overlap with your current assignment.',
                style: TextStyle(fontSize: 10.5, color: TgcgApp.muted),
              ),
              const SizedBox(height: 12),
              if (rooms.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: Text('No communication room in this scope.')),
                )
              else
                ...rooms.map(
                  (room) => Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: ListTile(
                      dense: true,
                      selected: room.id == selectedRoomId,
                      selectedTileColor: const Color(0xFFE8F1EE),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      leading: Icon(_roomIcon(room.type), size: 20),
                      title: Text(
                        room.name,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        room.scope.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10),
                      ),
                      onTap: () => onSelect(room.id),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
}

class _ConversationPanel extends StatelessWidget {
  const _ConversationPanel({
    required this.room,
    required this.messages,
    required this.controller,
    required this.canSend,
    required this.onSend,
  });

  final OperationalRoom? room;
  final List<OperationalMessage> messages;
  final TextEditingController controller;
  final bool canSend;
  final VoidCallback? onSend;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                room?.name ?? 'Select a room',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: TgcgApp.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                room?.description ?? 'Choose an operational room to view messages.',
                style: const TextStyle(fontSize: 11, color: TgcgApp.muted),
              ),
              const SizedBox(height: 14),
              if (room != null)
                Container(
                  constraints: const BoxConstraints(minHeight: 220, maxHeight: 380),
                  child: messages.isEmpty
                      ? const Center(child: Text('No messages in this room yet.'))
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            final item = messages[index];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 9),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF7F9F8),
                                borderRadius: BorderRadius.circular(13),
                                border: Border.all(color: const Color(0xFFE3E9E6)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          item.senderId,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w900,
                                            color: TgcgApp.ink,
                                          ),
                                        ),
                                      ),
                                      _DeliveryPill(item.deliveryState),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    item.body,
                                    style: const TextStyle(
                                      color: TgcgApp.muted,
                                      height: 1.45,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              if (room != null) ...[
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  enabled: canSend,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: canSend
                        ? 'Operational message'
                        : 'You have read-only communication access',
                    hintText: 'Write a factual operational update or coordination message.',
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: canSend ? onSend : null,
                    icon: const Icon(Icons.send_rounded),
                    label: const Text('Queue message'),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
}

class _BroadcastPanel extends StatelessWidget {
  const _BroadcastPanel({
    required this.broadcasts,
    required this.titleController,
    required this.bodyController,
    required this.canBroadcast,
    required this.onBroadcast,
  });

  final List<OperationalBroadcast> broadcasts;
  final TextEditingController titleController;
  final TextEditingController bodyController;
  final bool canBroadcast;
  final VoidCallback onBroadcast;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Operational broadcasts',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: TgcgApp.ink,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Broadcasts are for logistics, safety, system and election-operation coordination—not voter persuasion.',
                style: TextStyle(fontSize: 11, color: TgcgApp.muted),
              ),
              const SizedBox(height: 14),
              if (canBroadcast) ...[
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: 'Broadcast title'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: bodyController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Operational notice'),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: onBroadcast,
                  icon: const Icon(Icons.campaign_outlined),
                  label: const Text('Queue broadcast'),
                ),
                const Divider(height: 28),
              ],
              if (broadcasts.isEmpty)
                const Text('No broadcasts available in this scope.')
              else
                ...broadcasts.take(8).map(
                  (item) => Container(
                    margin: const EdgeInsets.only(bottom: 9),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAF9),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: const Color(0xFFE3E9E6)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: TgcgApp.ink,
                                ),
                              ),
                            ),
                            _Pill(
                              _label(item.deliveryState.name),
                              TgcgApp.primary,
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${item.scope.label} • ${item.senderId}',
                          style: const TextStyle(fontSize: 10.5, color: TgcgApp.muted),
                        ),
                        const SizedBox(height: 6),
                        Text(item.body, style: const TextStyle(color: TgcgApp.muted, height: 1.45)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
}

class _DeliveryPill extends StatelessWidget {
  const _DeliveryPill(this.state);
  final MessageDeliveryState state;

  @override
  Widget build(BuildContext context) => _Pill(
        _label(state.name),
        switch (state) {
          MessageDeliveryState.delivered => const Color(0xFF26734D),
          MessageDeliveryState.sent => const Color(0xFF2563EB),
          MessageDeliveryState.localQueued => const Color(0xFF8B6513),
          MessageDeliveryState.sending => const Color(0xFF6550B5),
          MessageDeliveryState.failed => const Color(0xFFB42318),
        },
      );
}

class _Pill extends StatelessWidget {
  const _Pill(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(color: color, fontSize: 9.5, fontWeight: FontWeight.w900),
        ),
      );
}

IconData _roomIcon(CommunicationRoomType type) => switch (type) {
      CommunicationRoomType.nationalCommand => Icons.public_rounded,
      CommunicationRoomType.situationRoom => Icons.radar_rounded,
      CommunicationRoomType.zone => Icons.language_rounded,
      CommunicationRoomType.state => Icons.map_rounded,
      CommunicationRoomType.lga => Icons.location_city_rounded,
      CommunicationRoomType.ward => Icons.grid_view_rounded,
      CommunicationRoomType.technicalSupport => Icons.support_agent_rounded,
    };

String _label(String value) {
  final spaced = value.replaceAllMapped(
    RegExp(r'([a-z])([A-Z])'),
    (match) => '${match.group(1)} ${match.group(2)}',
  );
  return spaced.isEmpty
      ? spaced
      : '${spaced[0].toUpperCase()}${spaced.substring(1)}';
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
