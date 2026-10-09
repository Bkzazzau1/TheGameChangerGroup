import 'package:flutter/material.dart';

import '../domain/permissions.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'communications_store.dart';

class CommunicationsPage extends StatefulWidget {
  const CommunicationsPage({super.key});

  @override
  State<CommunicationsPage> createState() => _CommunicationsPageState();
}

enum _CommunicationWorkspace { rooms, broadcasts, gateways, voiceVideo }

class _CommunicationsPageState extends State<CommunicationsPage> {
  final messageController = TextEditingController();
  final broadcastTitleController = TextEditingController();
  final broadcastBodyController = TextEditingController();

  _CommunicationWorkspace workspace = _CommunicationWorkspace.rooms;
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
    final visibleRoomIds = rooms.map((room) => room.id).toSet();
    final visibleMessages = store.messages
        .where((message) => visibleRoomIds.contains(message.roomId))
        .toList(growable: false);

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
    final canSend = TgcgPermissionPolicy.allows(
      session.role!,
      TgcgCapability.sendOperationalMessage,
    );
    final canBroadcast = TgcgPermissionPolicy.allows(
      session.role!,
      TgcgCapability.sendBroadcast,
    );
    final queuedMessages = visibleMessages
        .where((item) => item.deliveryState == MessageDeliveryState.localQueued)
        .length;
    final deliveredMessages = visibleMessages
        .where((item) => item.deliveryState == MessageDeliveryState.delivered)
        .length;
    final queuedBroadcasts = broadcasts
        .where((item) => item.deliveryState == BroadcastDeliveryState.queued)
        .length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
      children: [
        TgcgPageHeader(
          eyebrow: 'OPERATIONAL COORDINATION',
          title: 'Communications Hub',
          subtitle:
              '${session.scope.label}: scoped messaging, authorized broadcasts and integration surfaces for fallback SMS/USSD plus voice/video coordination.',
          trailing: const TgcgStatusPill(
            label: 'OPERATIONAL ONLY',
            color: TgcgColors.primary,
            icon: Icons.shield_outlined,
          ),
        ),
        const SizedBox(height: 18),
        _Metrics(
          rooms: rooms.length,
          messages: visibleMessages.length,
          deliveredMessages: deliveredMessages,
          queuedMessages: queuedMessages,
          broadcasts: broadcasts.length,
          queuedBroadcasts: queuedBroadcasts,
        ),
        const SizedBox(height: 16),
        _WorkspaceSelector(
          selected: workspace,
          onChanged: (value) => setState(() => workspace = value),
        ),
        const SizedBox(height: 16),
        switch (workspace) {
          _CommunicationWorkspace.rooms => _RoomsWorkspace(
              rooms: rooms,
              selectedRoom: selectedRoom,
              messages: messages,
              messageController: messageController,
              canSend: canSend,
              onSelectRoom: (id) => setState(() => selectedRoomId = id),
              onSend: selectedRoom == null
                  ? null
                  : () => _sendMessage(
                        context,
                        store: store,
                        session: session,
                        room: selectedRoom!,
                      ),
            ),
          _CommunicationWorkspace.broadcasts => _BroadcastWorkspace(
              broadcasts: broadcasts,
              titleController: broadcastTitleController,
              bodyController: broadcastBodyController,
              canBroadcast: canBroadcast,
              onBroadcast: () => _sendBroadcast(
                context,
                store: store,
                session: session,
              ),
            ),
          _CommunicationWorkspace.gateways => const _GatewayWorkspace(),
          _CommunicationWorkspace.voiceVideo => const _VoiceVideoWorkspace(),
        },
        const SizedBox(height: 16),
        const _OperationalUseNotice(),
      ],
    );
  }

  void _sendMessage(
    BuildContext context, {
    required CommunicationsController store,
    required TgcgSessionController session,
    required OperationalRoom room,
  }) {
    final ok = store.sendMessage(
      roomId: room.id,
      senderId: session.accessId.isEmpty
          ? session.operatorName
          : session.accessId,
      body: messageController.text,
      role: session.role!,
      userScope: session.scope,
    );
    if (!ok) return;
    messageController.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Message saved locally and queued for delivery.'),
      ),
    );
  }

  void _sendBroadcast(
    BuildContext context, {
    required CommunicationsController store,
    required TgcgSessionController session,
  }) {
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
    if (!ok) return;
    broadcastTitleController.clear();
    broadcastBodyController.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Broadcast queued for authorized delivery.'),
      ),
    );
  }
}

class _Metrics extends StatelessWidget {
  const _Metrics({
    required this.rooms,
    required this.messages,
    required this.deliveredMessages,
    required this.queuedMessages,
    required this.broadcasts,
    required this.queuedBroadcasts,
  });

  final int rooms;
  final int messages;
  final int deliveredMessages;
  final int queuedMessages;
  final int broadcasts;
  final int queuedBroadcasts;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 1080
              ? 6
              : constraints.maxWidth >= 720
                  ? 3
                  : constraints.maxWidth >= 440
                      ? 2
                      : 1;
          const gap = 12.0;
          final width =
              (constraints.maxWidth - (gap * (columns - 1))) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              TgcgMetricCard(
                width: width,
                label: 'Visible rooms',
                value: '$rooms',
                detail: 'Rooms overlapping your authorized geography',
                icon: Icons.forum_outlined,
                tone: TgcgMetricTone.neutral,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Messages',
                value: '$messages',
                detail: 'Operational messages visible in this scope',
                icon: Icons.chat_bubble_outline_rounded,
                tone: TgcgMetricTone.info,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Delivered',
                value: '$deliveredMessages',
                detail: 'Prototype messages explicitly marked delivered',
                icon: Icons.done_all_rounded,
                tone: TgcgMetricTone.success,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Local queue',
                value: '$queuedMessages',
                detail: 'Saved locally; not represented as delivered',
                icon: Icons.schedule_send_outlined,
                tone: queuedMessages == 0
                    ? TgcgMetricTone.neutral
                    : TgcgMetricTone.warning,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Broadcasts',
                value: '$broadcasts',
                detail: 'Authorized operational notices in scope',
                icon: Icons.campaign_outlined,
                tone: TgcgMetricTone.neutral,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Broadcast queue',
                value: '$queuedBroadcasts',
                detail: 'Awaiting external delivery service acknowledgement',
                icon: Icons.outbox_outlined,
                tone: queuedBroadcasts == 0
                    ? TgcgMetricTone.neutral
                    : TgcgMetricTone.warning,
              ),
            ],
          );
        },
      );
}

class _WorkspaceSelector extends StatelessWidget {
  const _WorkspaceSelector({
    required this.selected,
    required this.onChanged,
  });

  final _CommunicationWorkspace selected;
  final ValueChanged<_CommunicationWorkspace> onChanged;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        padding: const EdgeInsets.all(10),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _WorkspaceChip(
              value: _CommunicationWorkspace.rooms,
              selected: selected,
              icon: Icons.forum_outlined,
              label: 'Rooms & Messages',
              onChanged: onChanged,
            ),
            _WorkspaceChip(
              value: _CommunicationWorkspace.broadcasts,
              selected: selected,
              icon: Icons.campaign_outlined,
              label: 'Broadcasts',
              onChanged: onChanged,
            ),
            _WorkspaceChip(
              value: _CommunicationWorkspace.gateways,
              selected: selected,
              icon: Icons.sms_outlined,
              label: 'SMS / USSD',
              onChanged: onChanged,
            ),
            _WorkspaceChip(
              value: _CommunicationWorkspace.voiceVideo,
              selected: selected,
              icon: Icons.video_call_outlined,
              label: 'Voice / Video',
              onChanged: onChanged,
            ),
          ],
        ),
      );
}

class _WorkspaceChip extends StatelessWidget {
  const _WorkspaceChip({
    required this.value,
    required this.selected,
    required this.icon,
    required this.label,
    required this.onChanged,
  });

  final _CommunicationWorkspace value;
  final _CommunicationWorkspace selected;
  final IconData icon;
  final String label;
  final ValueChanged<_CommunicationWorkspace> onChanged;

  @override
  Widget build(BuildContext context) {
    final active = value == selected;
    return InkWell(
      borderRadius: BorderRadius.circular(13),
      onTap: () => onChanged(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: active ? TgcgColors.primary : TgcgColors.surfaceSoft,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: active ? TgcgColors.primary : TgcgColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 17,
              color: active ? Colors.white : TgcgColors.muted,
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                color: active ? Colors.white : TgcgColors.ink,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomsWorkspace extends StatelessWidget {
  const _RoomsWorkspace({
    required this.rooms,
    required this.selectedRoom,
    required this.messages,
    required this.messageController,
    required this.canSend,
    required this.onSelectRoom,
    required this.onSend,
  });

  final List<OperationalRoom> rooms;
  final OperationalRoom? selectedRoom;
  final List<OperationalMessage> messages;
  final TextEditingController messageController;
  final bool canSend;
  final ValueChanged<String> onSelectRoom;
  final VoidCallback? onSend;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final roomList = _RoomRail(
            rooms: rooms,
            selectedRoomId: selectedRoom?.id,
            onSelect: onSelectRoom,
          );
          final conversation = _ConversationWorkspace(
            room: selectedRoom,
            messages: messages,
            controller: messageController,
            canSend: canSend,
            onSend: onSend,
          );

          if (constraints.maxWidth < 940) {
            return Column(
              children: [
                roomList,
                const SizedBox(height: 14),
                conversation,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 320, child: roomList),
              const SizedBox(width: 14),
              Expanded(child: conversation),
            ],
          );
        },
      );
}

class _RoomRail extends StatelessWidget {
  const _RoomRail({
    required this.rooms,
    required this.selectedRoomId,
    required this.onSelect,
  });

  final List<OperationalRoom> rooms;
  final String? selectedRoomId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Operational rooms',
        subtitle: 'Scope-aware rooms for command, field and technical coordination.',
        child: rooms.isEmpty
            ? const TgcgEmptyState(
                icon: Icons.forum_outlined,
                title: 'No rooms in scope',
                message: 'No operational room overlaps this assignment.',
              )
            : Column(
                children: rooms.map((room) {
                  final active = room.id == selectedRoomId;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => onSelect(room.id),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: active
                              ? TgcgColors.primarySoft
                              : TgcgColors.surfaceSoft,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: active
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
                                color: (active
                                        ? TgcgColors.primary
                                        : TgcgColors.muted)
                                    .withValues(alpha: .10),
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: Icon(
                                _roomIcon(room.type),
                                size: 19,
                                color: active
                                    ? TgcgColors.primary
                                    : TgcgColors.muted,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    room.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: TgcgColors.ink,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    room.scope.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: TgcgColors.muted,
                                      fontSize: 9.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (active)
                              const Icon(
                                Icons.chevron_right_rounded,
                                color: TgcgColors.primary,
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

class _ConversationWorkspace extends StatelessWidget {
  const _ConversationWorkspace({
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
  Widget build(BuildContext context) {
    if (room == null) {
      return const TgcgSectionCard(
        child: TgcgEmptyState(
          icon: Icons.mark_chat_unread_outlined,
          title: 'Select an operational room',
          message: 'Choose a room to view its coordination history.',
        ),
      );
    }

    return TgcgSectionCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(17),
            decoration: const BoxDecoration(
              color: TgcgColors.primaryDark,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .09),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(_roomIcon(room!.type), color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        room!.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        room!.description ?? room!.scope.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFB9BECB),
                          fontSize: 10.5,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const TgcgStatusPill(
                  label: 'SCOPED ROOM',
                  color: TgcgColors.accent,
                  compact: true,
                ),
              ],
            ),
          ),
          Container(
            constraints: const BoxConstraints(minHeight: 280, maxHeight: 430),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: messages.isEmpty
                ? const TgcgEmptyState(
                    icon: Icons.chat_bubble_outline_rounded,
                    title: 'No messages yet',
                    message: 'Start this operational room with a factual coordination update.',
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: messages.length,
                    itemBuilder: (context, index) => _MessageBubble(
                      message: messages[index],
                    ),
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: controller,
                  enabled: canSend,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: canSend
                        ? 'Operational message'
                        : 'Read-only communication access',
                    hintText:
                        'Write a factual logistics, safety, verification or system-coordination update.',
                    prefixIcon: const Icon(Icons.chat_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Queued locally does not mean delivered.',
                        style: TextStyle(
                          color: TgcgColors.muted,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: canSend ? onSend : null,
                      icon: const Icon(Icons.send_rounded, size: 18),
                      label: const Text('Queue message'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final OperationalMessage message;

  @override
  Widget build(BuildContext context) {
    final color = _messageDeliveryColor(message.deliveryState);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: TgcgColors.surfaceSoft,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: TgcgColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: TgcgColors.primarySoft,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.person_outline_rounded,
                  size: 16,
                  color: TgcgColors.primary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message.senderId,
                  style: const TextStyle(
                    color: TgcgColors.ink,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              TgcgStatusPill(
                label: _label(message.deliveryState.name).toUpperCase(),
                color: color,
                icon: _messageDeliveryIcon(message.deliveryState),
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message.body,
            style: const TextStyle(
              color: TgcgColors.ink,
              fontSize: 11.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _formatTime(message.createdAt),
            style: const TextStyle(
              color: TgcgColors.muted,
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }
}

class _BroadcastWorkspace extends StatelessWidget {
  const _BroadcastWorkspace({
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
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final compose = TgcgSectionCard(
            title: 'Operational broadcast',
            subtitle:
                'Authorized logistics, safety, system and election-operation notices only.',
            trailing: TgcgStatusPill(
              label: canBroadcast ? 'AUTHORIZED' : 'READ ONLY',
              color: canBroadcast ? TgcgColors.success : TgcgColors.muted,
              icon: canBroadcast ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
              compact: true,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: titleController,
                  enabled: canBroadcast,
                  decoration: const InputDecoration(
                    labelText: 'Broadcast title',
                    prefixIcon: Icon(Icons.title_rounded),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: bodyController,
                  enabled: canBroadcast,
                  minLines: 4,
                  maxLines: 7,
                  decoration: const InputDecoration(
                    labelText: 'Operational notice',
                    hintText:
                        'Example: synchronization advisory, safety notice, logistics instruction or verification procedure.',
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Current prototype targets the operator’s authorized geographic scope. A future recipient/role selector must remain constrained by server-side RBAC.',
                  style: TextStyle(
                    color: TgcgColors.muted,
                    fontSize: 9.5,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: canBroadcast ? onBroadcast : null,
                    icon: const Icon(Icons.campaign_outlined),
                    label: const Text('Queue broadcast'),
                  ),
                ),
              ],
            ),
          );

          final history = TgcgSectionCard(
            title: 'Broadcast history',
            subtitle:
                'Delivery state is retained separately from creation state.',
            child: broadcasts.isEmpty
                ? const TgcgEmptyState(
                    icon: Icons.campaign_outlined,
                    title: 'No broadcasts in scope',
                    message: 'Authorized notices will appear here with delivery state.',
                  )
                : Column(
                    children: broadcasts
                        .map((item) => _BroadcastTile(item: item))
                        .toList(),
                  ),
          );

          if (constraints.maxWidth < 940) {
            return Column(
              children: [
                compose,
                const SizedBox(height: 14),
                history,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: compose),
              const SizedBox(width: 14),
              Expanded(flex: 6, child: history),
            ],
          );
        },
      );
}

class _BroadcastTile extends StatelessWidget {
  const _BroadcastTile({required this.item});

  final OperationalBroadcast item;

  @override
  Widget build(BuildContext context) {
    final color = _broadcastDeliveryColor(item.deliveryState);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TgcgColors.surfaceSoft,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: TgcgColors.border),
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
                    color: TgcgColors.ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              TgcgStatusPill(
                label: _label(item.deliveryState.name).toUpperCase(),
                color: color,
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            '${item.scope.label} • ${item.senderId} • ${_formatTime(item.createdAt)}',
            style: const TextStyle(
              color: TgcgColors.muted,
              fontSize: 9.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item.body,
            style: const TextStyle(
              color: TgcgColors.ink,
              fontSize: 11,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _GatewayWorkspace extends StatelessWidget {
  const _GatewayWorkspace();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final sms = const _GatewayCard(
            icon: Icons.sms_outlined,
            title: 'SMS Gateway',
            subtitle:
                'Fallback alphanumeric result, incident and acknowledgement transport.',
            protocol: 'SMPP / HTTP integration',
            safeguards: [
              'Agent ID + PIN validation',
              'Registered SIM / phone binding',
              'Polling-unit validation',
              'Duplicate and arithmetic checks',
              'Delivery receipts / acknowledgements',
            ],
          );
          final ussd = const _GatewayCard(
            icon: Icons.dialpad_outlined,
            title: 'USSD Gateway',
            subtitle:
                'Low-bandwidth fallback workflow for structured field transactions.',
            protocol: 'USSD aggregator integration',
            safeguards: [
              'Session-bound Agent ID',
              'Short structured transaction flow',
              'Canonical polling-unit reference',
              'Server validation before acceptance',
              'Final acknowledgement reference',
            ],
          );

          if (constraints.maxWidth < 860) {
            return Column(
              children: [
                sms,
                const SizedBox(height: 14),
                ussd,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: sms),
              const SizedBox(width: 14),
              Expanded(child: ussd),
            ],
          );
        },
      );
}

class _GatewayCard extends StatelessWidget {
  const _GatewayCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.protocol,
    required this.safeguards,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String protocol;
  final List<String> safeguards;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: title,
        subtitle: subtitle,
        trailing: const TgcgStatusPill(
          label: 'INTEGRATION PENDING',
          color: TgcgColors.warning,
          icon: Icons.construction_outlined,
          compact: true,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: TgcgColors.primaryDark,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .09),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: Colors.white),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'External gateway not connected',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          protocol,
                          style: const TextStyle(
                            color: Color(0xFFB9BECB),
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 15),
            const Text(
              'Required operational safeguards',
              style: TextStyle(
                color: TgcgColors.ink,
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 9),
            ...safeguards.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.check_circle_outline_rounded,
                      color: TgcgColors.primary,
                      size: 17,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item,
                        style: const TextStyle(
                          color: TgcgColors.muted,
                          fontSize: 10.5,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            const _NoFakeMetricsNotice(),
          ],
        ),
      );
}

class _VoiceVideoWorkspace extends StatelessWidget {
  const _VoiceVideoWorkspace();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final voice = const _MediaIntegrationCard(
            icon: Icons.call_outlined,
            title: 'Operational Voice',
            description:
                'Secure room or direct operational calling for authorized coordinators and field personnel.',
            capabilities: [
              'Room-based or direct calling',
              'Participant identity and role display',
              'Scope-aware call permissions',
              'Call-state and connectivity feedback',
              'Auditable session metadata without recording private content by default',
            ],
          );
          final video = const _MediaIntegrationCard(
            icon: Icons.videocam_outlined,
            title: 'Video Conference',
            description:
                'Live coordination rooms for command, verification and technical response.',
            capabilities: [
              'Multi-participant rooms',
              'Role and geography context',
              'Camera/microphone permission states',
              'Low-bandwidth adaptation',
              'WebRTC/service-provider integration boundary',
            ],
          );

          if (constraints.maxWidth < 860) {
            return Column(
              children: [
                voice,
                const SizedBox(height: 14),
                video,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: voice),
              const SizedBox(width: 14),
              Expanded(child: video),
            ],
          );
        },
      );
}

class _MediaIntegrationCard extends StatelessWidget {
  const _MediaIntegrationCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.capabilities,
  });

  final IconData icon;
  final String title;
  final String description;
  final List<String> capabilities;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: title,
        subtitle: description,
        trailing: const TgcgStatusPill(
          label: 'INTEGRATION PENDING',
          color: TgcgColors.warning,
          icon: Icons.link_off_rounded,
          compact: true,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 210,
              decoration: BoxDecoration(
                color: TgcgColors.primaryDark,
                borderRadius: BorderRadius.circular(17),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .09),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(icon, color: Colors.white, size: 30),
                  ),
                  const SizedBox(height: 13),
                  const Text(
                    'No active media service',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'Connect WebRTC / approved provider before enabling calls.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFFB9BECB),
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 15),
            ...capabilities.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.check_circle_outline_rounded,
                      color: TgcgColors.primary,
                      size: 17,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item,
                        style: const TextStyle(
                          color: TgcgColors.muted,
                          fontSize: 10.5,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}

class _NoFakeMetricsNotice extends StatelessWidget {
  const _NoFakeMetricsNotice();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: TgcgColors.warning.withValues(alpha: .06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: TgcgColors.warning.withValues(alpha: .15),
          ),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: 17,
              color: TgcgColors.warning,
            ),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'No delivery volume, queue depth or acknowledgement percentage is shown until a real gateway provides those values.',
                style: TextStyle(
                  color: TgcgColors.muted,
                  fontSize: 9.5,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      );
}

class _OperationalUseNotice extends StatelessWidget {
  const _OperationalUseNotice();

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        backgroundColor: TgcgColors.accentSoft,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.policy_outlined, color: TgcgColors.warning),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Operational communications boundary',
                    style: TextStyle(
                      color: TgcgColors.ink,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'This workspace is designed for logistics, safety, system support, incident response, verification and election-operation coordination. It is not a voter-profiling or persuasion workspace.',
                    style: TextStyle(
                      color: TgcgColors.muted,
                      fontSize: 10.5,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

Color _messageDeliveryColor(MessageDeliveryState state) => switch (state) {
      MessageDeliveryState.delivered => TgcgColors.success,
      MessageDeliveryState.sent => TgcgColors.info,
      MessageDeliveryState.localQueued => TgcgColors.warning,
      MessageDeliveryState.sending => TgcgColors.ai,
      MessageDeliveryState.failed => TgcgColors.danger,
    };

IconData _messageDeliveryIcon(MessageDeliveryState state) => switch (state) {
      MessageDeliveryState.delivered => Icons.done_all_rounded,
      MessageDeliveryState.sent => Icons.done_rounded,
      MessageDeliveryState.localQueued => Icons.schedule_send_outlined,
      MessageDeliveryState.sending => Icons.sync_rounded,
      MessageDeliveryState.failed => Icons.error_outline_rounded,
    };

Color _broadcastDeliveryColor(BroadcastDeliveryState state) => switch (state) {
      BroadcastDeliveryState.sent => TgcgColors.success,
      BroadcastDeliveryState.partiallyDelivered => TgcgColors.warning,
      BroadcastDeliveryState.queued => TgcgColors.info,
      BroadcastDeliveryState.failed => TgcgColors.danger,
    };

IconData _roomIcon(CommunicationRoomType type) => switch (type) {
      CommunicationRoomType.nationalCommand => Icons.public_rounded,
      CommunicationRoomType.situationRoom => Icons.radar_rounded,
      CommunicationRoomType.zone => Icons.language_rounded,
      CommunicationRoomType.state => Icons.map_rounded,
      CommunicationRoomType.lga => Icons.location_city_rounded,
      CommunicationRoomType.ward => Icons.grid_view_rounded,
      CommunicationRoomType.technicalSupport => Icons.support_agent_rounded,
    };

String _formatTime(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _label(String value) {
  final spaced = value.replaceAllMapped(
    RegExp(r'([a-z])([A-Z])'),
    (match) => '${match.group(1)} ${match.group(2)}',
  );
  return spaced.isEmpty
      ? spaced
      : '${spaced[0].toUpperCase()}${spaced.substring(1)}';
}
