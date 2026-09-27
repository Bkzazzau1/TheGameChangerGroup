import 'package:flutter/widgets.dart';

import '../domain/models.dart';
import '../domain/permissions.dart';
import '../governance/governance_store.dart';

enum CommunicationRoomType {
  nationalCommand,
  situationRoom,
  zone,
  state,
  lga,
  ward,
  technicalSupport,
}

enum MessageDeliveryState { localQueued, sending, sent, delivered, failed }

enum BroadcastDeliveryState { queued, sent, partiallyDelivered, failed }

class OperationalRoom {
  const OperationalRoom({
    required this.id,
    required this.name,
    required this.type,
    required this.scope,
    this.description,
  });

  final String id;
  final String name;
  final CommunicationRoomType type;
  final GeographicScope scope;
  final String? description;
}

class OperationalMessage {
  const OperationalMessage({
    required this.id,
    required this.roomId,
    required this.senderId,
    required this.body,
    required this.createdAt,
    required this.deliveryState,
    this.replyToMessageId,
  });

  final String id;
  final String roomId;
  final String senderId;
  final String body;
  final DateTime createdAt;
  final MessageDeliveryState deliveryState;
  final String? replyToMessageId;
}

class OperationalBroadcast {
  const OperationalBroadcast({
    required this.id,
    required this.title,
    required this.body,
    required this.scope,
    required this.senderId,
    required this.createdAt,
    required this.deliveryState,
  });

  final String id;
  final String title;
  final String body;
  final GeographicScope scope;
  final String senderId;
  final DateTime createdAt;
  final BroadcastDeliveryState deliveryState;
}

class CommunicationsController extends ChangeNotifier {
  CommunicationsController._({
    required GovernanceOperationsController governance,
    required List<OperationalRoom> rooms,
    required List<OperationalMessage> messages,
    required List<OperationalBroadcast> broadcasts,
  })  : _governance = governance,
        _rooms = rooms,
        _messages = messages,
        _broadcasts = broadcasts;

  factory CommunicationsController.prototypeSeed(
    GovernanceOperationsController governance,
  ) {
    final now = DateTime.utc(2026, 9, 27, 8, 25);

    final kadunaState = GeographicScope(
      level: GeographyLevel.state,
      country: 'Nigeria',
      zoneId: 'NW',
      zoneName: 'North West',
      stateId: 'KD',
      stateName: 'Kaduna',
    );
    final makurdi = GeographicScope(
      level: GeographyLevel.lga,
      country: 'Nigeria',
      zoneId: 'NC',
      zoneName: 'North Central',
      stateId: 'BN',
      stateName: 'Benue',
      lgaId: 'BN-MAKURDI',
      lgaName: 'Makurdi',
    );

    return CommunicationsController._(
      governance: governance,
      rooms: [
        const OperationalRoom(
          id: 'ROOM-NATIONAL',
          name: 'National Operations',
          type: CommunicationRoomType.nationalCommand,
          scope: GeographicScope.nigeria,
          description: 'National operational coordination and command notices.',
        ),
        const OperationalRoom(
          id: 'ROOM-SITUATION',
          name: 'Situation Room',
          type: CommunicationRoomType.situationRoom,
          scope: GeographicScope.nigeria,
          description: 'Live operational coordination for incidents and verification.',
        ),
        OperationalRoom(
          id: 'ROOM-KD',
          name: 'Kaduna State Operations',
          type: CommunicationRoomType.state,
          scope: kadunaState,
          description: 'Kaduna state coordination room.',
        ),
        OperationalRoom(
          id: 'ROOM-BN-MK',
          name: 'Makurdi LGA Operations',
          type: CommunicationRoomType.lga,
          scope: makurdi,
          description: 'Makurdi field coordination room.',
        ),
        const OperationalRoom(
          id: 'ROOM-SUPPORT',
          name: 'Technical Support',
          type: CommunicationRoomType.technicalSupport,
          scope: GeographicScope.nigeria,
          description: 'Device, sync and application support desk.',
        ),
      ],
      messages: [
        OperationalMessage(
          id: 'MSG-0001',
          roomId: 'ROOM-SITUATION',
          senderId: 'SITUATION-DESK',
          body: 'Confirm acknowledgement of all high-priority incidents and maintain evidence provenance.',
          createdAt: now.subtract(const Duration(minutes: 28)),
          deliveryState: MessageDeliveryState.delivered,
        ),
        OperationalMessage(
          id: 'MSG-0002',
          roomId: 'ROOM-KD',
          senderId: 'KD-COORD',
          body: 'Polling-unit assignment review is in progress. Escalate any unassigned unit through the accreditation desk.',
          createdAt: now.subtract(const Duration(minutes: 19)),
          deliveryState: MessageDeliveryState.delivered,
        ),
        OperationalMessage(
          id: 'MSG-0003',
          roomId: 'ROOM-SUPPORT',
          senderId: 'TECH-SUPPORT',
          body: 'Offline records remain locally queued when connectivity is unavailable. Do not duplicate submissions.',
          createdAt: now.subtract(const Duration(minutes: 12)),
          deliveryState: MessageDeliveryState.sent,
        ),
      ],
      broadcasts: [
        OperationalBroadcast(
          id: 'BCAST-0001',
          title: 'Operational readiness notice',
          body: 'Use only assigned accounts and devices for field workflows. Report access or synchronization issues through the support channel.',
          scope: GeographicScope.nigeria,
          senderId: 'NATIONAL-OPS',
          createdAt: now.subtract(const Duration(hours: 1)),
          deliveryState: BroadcastDeliveryState.sent,
        ),
      ],
    );
  }

  final GovernanceOperationsController _governance;
  final List<OperationalRoom> _rooms;
  final List<OperationalMessage> _messages;
  final List<OperationalBroadcast> _broadcasts;

  List<OperationalRoom> get rooms => List.unmodifiable(_rooms);
  List<OperationalMessage> get messages => List.unmodifiable(_messages);
  List<OperationalBroadcast> get broadcasts => List.unmodifiable(_broadcasts);

  List<OperationalRoom> roomsForScope(GeographicScope userScope) =>
      _rooms.where((room) => _overlaps(userScope, room.scope)).toList(growable: false);

  List<OperationalMessage> messagesForRoom(String roomId) => _messages
      .where((message) => message.roomId == roomId)
      .toList(growable: false)
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  List<OperationalBroadcast> broadcastsForScope(GeographicScope userScope) =>
      _broadcasts.where((item) => _overlaps(userScope, item.scope)).toList(growable: false)
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  bool sendMessage({
    required String roomId,
    required String senderId,
    required String body,
    required TgcgRole role,
    required GeographicScope userScope,
  }) {
    final roomIndex = _rooms.indexWhere((room) => room.id == roomId);
    if (roomIndex < 0 || body.trim().isEmpty) return false;
    final room = _rooms[roomIndex];
    if (!TgcgPermissionPolicy.allows(role, TgcgCapability.sendOperationalMessage)) {
      return false;
    }
    if (!_overlaps(userScope, room.scope)) return false;

    final message = OperationalMessage(
      id: 'MSG-${(_messages.length + 1).toString().padLeft(4, '0')}',
      roomId: room.id,
      senderId: senderId,
      body: body.trim(),
      createdAt: DateTime.now().toUtc(),
      deliveryState: MessageDeliveryState.localQueued,
    );
    _messages.add(message);
    _governance.recordAudit(
      actorId: senderId,
      action: 'operational_message_created',
      entityType: 'communication_message',
      entityId: message.id,
      detail: 'Queued local message for room ${room.name}.',
      scope: room.scope,
    );
    notifyListeners();
    return true;
  }

  bool sendBroadcast({
    required String title,
    required String body,
    required GeographicScope targetScope,
    required String senderId,
    required TgcgRole role,
    required GeographicScope userScope,
  }) {
    if (title.trim().isEmpty || body.trim().isEmpty) return false;
    if (!TgcgPermissionPolicy.allows(role, TgcgCapability.sendBroadcast)) {
      return false;
    }
    if (!_within(userScope, targetScope)) return false;

    final broadcast = OperationalBroadcast(
      id: 'BCAST-${(_broadcasts.length + 1).toString().padLeft(4, '0')}',
      title: title.trim(),
      body: body.trim(),
      scope: targetScope,
      senderId: senderId,
      createdAt: DateTime.now().toUtc(),
      deliveryState: BroadcastDeliveryState.queued,
    );
    _broadcasts.insert(0, broadcast);
    _governance.recordAudit(
      actorId: senderId,
      action: 'broadcast_created',
      entityType: 'operational_broadcast',
      entityId: broadcast.id,
      detail: 'Operational broadcast queued for ${targetScope.label}.',
      scope: targetScope,
    );
    notifyListeners();
    return true;
  }

  static bool _overlaps(GeographicScope a, GeographicScope b) =>
      _within(a, b) || _within(b, a);

  static bool _within(GeographicScope parent, GeographicScope child) {
    if (parent.country != child.country) return false;
    if (parent.level == GeographyLevel.country) return true;
    if (parent.zoneId != null && parent.zoneId != child.zoneId) return false;
    if (parent.level == GeographyLevel.geopoliticalZone) return true;
    if (parent.stateId != null && parent.stateId != child.stateId) return false;
    if (parent.level == GeographyLevel.state) return true;
    if (parent.senatorialDistrictId != null &&
        parent.senatorialDistrictId != child.senatorialDistrictId) return false;
    if (parent.level == GeographyLevel.senatorialDistrict) return true;
    if (parent.lgaId != null && parent.lgaId != child.lgaId) return false;
    if (parent.level == GeographyLevel.lga) return true;
    if (parent.wardId != null && parent.wardId != child.wardId) return false;
    if (parent.level == GeographyLevel.ward) return true;
    return parent.pollingUnitId == child.pollingUnitId;
  }
}

class Communications extends InheritedNotifier<CommunicationsController> {
  const Communications({
    super.key,
    required CommunicationsController controller,
    required super.child,
  }) : super(notifier: controller);

  static CommunicationsController of(BuildContext context, {bool listen = true}) {
    if (listen) {
      final value = context.dependOnInheritedWidgetOfExactType<Communications>();
      assert(value != null, 'Communications is missing above this context.');
      return value!.notifier!;
    }
    final element = context.getElementForInheritedWidgetOfExactType<Communications>();
    final value = element?.widget as Communications?;
    assert(value != null, 'Communications is missing above this context.');
    return value!.notifier!;
  }
}
