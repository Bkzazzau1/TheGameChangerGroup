import 'package:flutter/widgets.dart';

import '../domain/models.dart';
import '../domain/permissions.dart';
import '../governance/governance_store.dart';
import '../membership/membership_store.dart';
import '../offline/offline_payloads.dart';
import '../offline/offline_persistence.dart';

enum BulkCommunicationChannel { push, sms, email, voice }

enum BulkDeliveryJobState {
  draft,
  queued,
  waitingForProvider,
  processing,
  completed,
  partiallyDelivered,
  failed,
  cancelled,
}

enum ProviderConnectionState { notConfigured, ready, degraded, unavailable }

class CommunicationPreference {
  const CommunicationPreference({
    required this.memberId,
    required this.updatedAt,
    required this.updatedBy,
    required this.source,
    this.smsOptIn = false,
    this.pushOptIn = false,
    this.emailOptIn = false,
    this.voiceOptIn = false,
    this.suppressed = false,
  });

  final String memberId;
  final bool smsOptIn;
  final bool pushOptIn;
  final bool emailOptIn;
  final bool voiceOptIn;
  final bool suppressed;
  final DateTime updatedAt;
  final String updatedBy;
  final String source;

  bool optedIn(BulkCommunicationChannel channel) => switch (channel) {
        BulkCommunicationChannel.sms => smsOptIn,
        BulkCommunicationChannel.push => pushOptIn,
        BulkCommunicationChannel.email => emailOptIn,
        BulkCommunicationChannel.voice => voiceOptIn,
      };
}

class CommunicationContact {
  const CommunicationContact({
    required this.memberId,
    required this.fullName,
    required this.phoneNumber,
    required this.scope,
    required this.preference,
    required this.hasAppDevice,
    this.email,
  });

  final String memberId;
  final String fullName;
  final String phoneNumber;
  final String? email;
  final GeographicScope scope;
  final CommunicationPreference preference;
  final bool hasAppDevice;

  bool eligibleFor(BulkCommunicationChannel channel) {
    if (preference.suppressed || !preference.optedIn(channel)) return false;
    return switch (channel) {
      BulkCommunicationChannel.sms => phoneNumber.trim().isNotEmpty,
      BulkCommunicationChannel.push => hasAppDevice,
      BulkCommunicationChannel.email => email?.trim().isNotEmpty == true,
      BulkCommunicationChannel.voice => phoneNumber.trim().isNotEmpty,
    };
  }
}

class BulkDeliveryProvider {
  const BulkDeliveryProvider({
    required this.id,
    required this.name,
    required this.channel,
    required this.priority,
    required this.state,
    this.supportsDeliveryReceipts = false,
  });

  final String id;
  final String name;
  final BulkCommunicationChannel channel;
  final int priority;
  final ProviderConnectionState state;
  final bool supportsDeliveryReceipts;

  bool get available => state == ProviderConnectionState.ready;
}

class BulkDeliveryJob {
  const BulkDeliveryJob({
    required this.id,
    required this.title,
    required this.body,
    required this.targetScope,
    required this.channels,
    required this.createdBy,
    required this.createdAt,
    required this.state,
    required this.targetContactCount,
    required this.eligibleRecipientCount,
    required this.suppressedCount,
    required this.channelPlan,
    this.scheduledFor,
    this.sentCount = 0,
    this.deliveredCount = 0,
    this.failedCount = 0,
  });

  final String id;
  final String title;
  final String body;
  final GeographicScope targetScope;
  final List<BulkCommunicationChannel> channels;
  final String createdBy;
  final DateTime createdAt;
  final DateTime? scheduledFor;
  final BulkDeliveryJobState state;
  final int targetContactCount;
  final int eligibleRecipientCount;
  final int suppressedCount;
  final Map<BulkCommunicationChannel, int> channelPlan;
  final int sentCount;
  final int deliveredCount;
  final int failedCount;
}

class BulkCommunicationsController extends ChangeNotifier {
  BulkCommunicationsController._({
    required MembershipOperationsController membership,
    required GovernanceOperationsController governance,
    OfflinePersistenceController? persistence,
    Map<String, CommunicationPreference> preferences = const {},
    List<BulkDeliveryJob> jobs = const [],
    List<BulkDeliveryProvider> providers = const [],
  })  : _membership = membership,
        _governance = governance,
        _persistence = persistence,
        _preferences = Map.of(preferences),
        _jobs = List.of(jobs),
        _providers = List.of(providers);

  factory BulkCommunicationsController.productionFoundation({
    required MembershipOperationsController membership,
    required GovernanceOperationsController governance,
    OfflinePersistenceController? persistence,
  }) {
    return BulkCommunicationsController._(
      membership: membership,
      governance: governance,
      persistence: persistence,
      providers: const [
        BulkDeliveryProvider(
          id: 'PUSH-PRIMARY',
          name: 'Push Notification Provider',
          channel: BulkCommunicationChannel.push,
          priority: 1,
          state: ProviderConnectionState.notConfigured,
          supportsDeliveryReceipts: true,
        ),
        BulkDeliveryProvider(
          id: 'SMS-PRIMARY',
          name: 'Primary SMS Gateway',
          channel: BulkCommunicationChannel.sms,
          priority: 1,
          state: ProviderConnectionState.notConfigured,
          supportsDeliveryReceipts: true,
        ),
        BulkDeliveryProvider(
          id: 'SMS-BACKUP',
          name: 'Backup SMS Gateway',
          channel: BulkCommunicationChannel.sms,
          priority: 2,
          state: ProviderConnectionState.notConfigured,
          supportsDeliveryReceipts: true,
        ),
        BulkDeliveryProvider(
          id: 'EMAIL-PRIMARY',
          name: 'Transactional Email Provider',
          channel: BulkCommunicationChannel.email,
          priority: 1,
          state: ProviderConnectionState.notConfigured,
          supportsDeliveryReceipts: true,
        ),
        BulkDeliveryProvider(
          id: 'VOICE-PRIMARY',
          name: 'Voice / IVR Provider',
          channel: BulkCommunicationChannel.voice,
          priority: 1,
          state: ProviderConnectionState.notConfigured,
          supportsDeliveryReceipts: true,
        ),
      ],
    );
  }

  final MembershipOperationsController _membership;
  final GovernanceOperationsController _governance;
  final OfflinePersistenceController? _persistence;
  final Map<String, CommunicationPreference> _preferences;
  final List<BulkDeliveryJob> _jobs;
  final List<BulkDeliveryProvider> _providers;

  List<BulkDeliveryProvider> get providers => List.unmodifiable(
        [..._providers]..sort((a, b) {
          final channel = a.channel.index.compareTo(b.channel.index);
          if (channel != 0) return channel;
          return a.priority.compareTo(b.priority);
        }),
      );

  List<BulkDeliveryJob> get jobs => List.unmodifiable(
        [..._jobs]..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
      );

  List<CommunicationContact> get contacts => _membership.members
      .map(_contactForMember)
      .toList(growable: false);

  List<CommunicationContact> contactsForScope(GeographicScope scope) => contacts
      .where((contact) => TgcgPermissionPolicy.scopeAllows(scope, contact.scope))
      .toList(growable: false);

  List<BulkDeliveryJob> jobsForScope(GeographicScope scope) => jobs
      .where((job) =>
          TgcgPermissionPolicy.scopeAllows(scope, job.targetScope) ||
          TgcgPermissionPolicy.scopeAllows(job.targetScope, scope))
      .toList(growable: false);

  CommunicationContact _contactForMember(TgcgMember member) {
    final scope = _membership.registrationScopeForMember(member.id) ??
        GeographicScope.nigeria;
    final hasAppDevice = _membership.agents.any(
      (agent) =>
          agent.memberId == member.id &&
          agent.status == AccreditationStatus.approved &&
          agent.deviceId?.trim().isNotEmpty == true,
    );
    final preference = _preferences[member.id] ??
        CommunicationPreference(
          memberId: member.id,
          updatedAt: member.createdAt,
          updatedBy: 'UNSET',
          source: 'No communication preference recorded',
        );
    return CommunicationContact(
      memberId: member.id,
      fullName: member.fullName,
      phoneNumber: member.phoneNumber,
      email: member.email,
      scope: scope,
      preference: preference,
      hasAppDevice: hasAppDevice,
    );
  }

  int eligibleCount(
    GeographicScope scope,
    BulkCommunicationChannel channel,
  ) =>
      contactsForScope(scope).where((contact) => contact.eligibleFor(channel)).length;

  int suppressedCount(GeographicScope scope) => contactsForScope(scope)
      .where((contact) => contact.preference.suppressed)
      .length;

  Future<bool> recordPreference({
    required String memberId,
    required String actorId,
    required TgcgRole actorRole,
    required GeographicScope actorScope,
    required String source,
    required bool smsOptIn,
    required bool pushOptIn,
    required bool emailOptIn,
    required bool voiceOptIn,
    bool suppressed = false,
  }) async {
    if (!TgcgPermissionPolicy.allows(
      actorRole,
      TgcgCapability.manageMembership,
    )) {
      return false;
    }
    final member = _membership.memberById(memberId);
    if (member == null) return false;
    final memberScope = _membership.registrationScopeForMember(memberId) ??
        GeographicScope.nigeria;
    if (!TgcgPermissionPolicy.scopeAllows(actorScope, memberScope)) return false;
    final normalizedSource = source.trim();
    if (normalizedSource.isEmpty) return false;

    final preference = CommunicationPreference(
      memberId: memberId,
      smsOptIn: smsOptIn,
      pushOptIn: pushOptIn,
      emailOptIn: emailOptIn,
      voiceOptIn: voiceOptIn,
      suppressed: suppressed,
      updatedAt: DateTime.now().toUtc(),
      updatedBy: actorId,
      source: normalizedSource,
    );

    await _persistence?.persistMutation(
      entityType: 'communication_preference',
      entityId: memberId,
      mutationType: SyncMutationType.update,
      payload: _preferencePayload(preference),
      scopeKey: scopeStorageKey(memberScope),
      ownerId: actorId,
    );
    _preferences[memberId] = preference;
    _governance.recordAudit(
      actorId: actorId,
      action: 'communication_preference_updated',
      entityType: 'communication_preference',
      entityId: memberId,
      detail:
          'Communication preference updated. Source: ${preference.source}. Suppressed: ${preference.suppressed}.',
      scope: memberScope,
    );
    notifyListeners();
    return true;
  }

  Future<BulkDeliveryJob?> queueJob({
    required String title,
    required String body,
    required GeographicScope targetScope,
    required List<BulkCommunicationChannel> channels,
    required String actorId,
    required TgcgRole actorRole,
    required GeographicScope actorScope,
    DateTime? scheduledFor,
  }) async {
    if (!TgcgPermissionPolicy.allows(actorRole, TgcgCapability.sendBroadcast)) {
      return null;
    }
    if (!TgcgPermissionPolicy.scopeAllows(actorScope, targetScope)) return null;
    final cleanTitle = title.trim();
    final cleanBody = body.trim();
    final orderedChannels = channels.toSet().toList(growable: false);
    if (cleanTitle.isEmpty || cleanBody.isEmpty || orderedChannels.isEmpty) {
      return null;
    }

    final targetContacts = contactsForScope(targetScope);
    final channelPlan = <BulkCommunicationChannel, int>{
      for (final channel in BulkCommunicationChannel.values) channel: 0,
    };
    var eligible = 0;
    var suppressed = 0;
    for (final contact in targetContacts) {
      if (contact.preference.suppressed) {
        suppressed++;
        continue;
      }
      BulkCommunicationChannel? route;
      for (final channel in orderedChannels) {
        if (contact.eligibleFor(channel)) {
          route = channel;
          break;
        }
      }
      if (route != null) {
        eligible++;
        channelPlan[route] = (channelPlan[route] ?? 0) + 1;
      }
    }

    final providerReady = orderedChannels.any(
      (channel) => _providers.any(
        (provider) => provider.channel == channel && provider.available,
      ),
    );
    final now = DateTime.now().toUtc();
    final job = BulkDeliveryJob(
      id: 'BULK-${(now.microsecondsSinceEpoch % 1000000000).toString().padLeft(9, '0')}',
      title: cleanTitle,
      body: cleanBody,
      targetScope: targetScope,
      channels: orderedChannels,
      createdBy: actorId,
      createdAt: now,
      scheduledFor: scheduledFor,
      state: providerReady
          ? BulkDeliveryJobState.queued
          : BulkDeliveryJobState.waitingForProvider,
      targetContactCount: targetContacts.length,
      eligibleRecipientCount: eligible,
      suppressedCount: suppressed,
      channelPlan: Map.unmodifiable(channelPlan),
    );

    await _persistence?.persistMutation(
      entityType: 'bulk_delivery_job',
      entityId: job.id,
      mutationType: SyncMutationType.create,
      payload: _jobPayload(job),
      scopeKey: scopeStorageKey(targetScope),
      ownerId: actorId,
    );
    _jobs.insert(0, job);
    _governance.recordAudit(
      actorId: actorId,
      action: 'bulk_delivery_job_created',
      entityType: 'bulk_delivery_job',
      entityId: job.id,
      detail:
          'Queued ${job.eligibleRecipientCount} eligible recipients within ${targetScope.label}.',
      scope: targetScope,
    );
    notifyListeners();
    return job;
  }

  Map<String, Object?> _preferencePayload(CommunicationPreference value) => {
        'member_id': value.memberId,
        'sms_opt_in': value.smsOptIn,
        'push_opt_in': value.pushOptIn,
        'email_opt_in': value.emailOptIn,
        'voice_opt_in': value.voiceOptIn,
        'suppressed': value.suppressed,
        'updated_at': value.updatedAt.toIso8601String(),
        'updated_by': value.updatedBy,
        'source': value.source,
      };

  Map<String, Object?> _jobPayload(BulkDeliveryJob value) => {
        'id': value.id,
        'title': value.title,
        'body': value.body,
        'target_scope': scopeStorageKey(value.targetScope),
        'channels': value.channels.map((item) => item.name).toList(),
        'created_by': value.createdBy,
        'created_at': value.createdAt.toIso8601String(),
        'scheduled_for': value.scheduledFor?.toIso8601String(),
        'state': value.state.name,
        'target_contact_count': value.targetContactCount,
        'eligible_recipient_count': value.eligibleRecipientCount,
        'suppressed_count': value.suppressedCount,
        'channel_plan': {
          for (final entry in value.channelPlan.entries)
            entry.key.name: entry.value,
        },
      };
}

class BulkCommunications
    extends InheritedNotifier<BulkCommunicationsController> {
  const BulkCommunications({
    super.key,
    required BulkCommunicationsController controller,
    required super.child,
  }) : super(notifier: controller);

  static BulkCommunicationsController of(
    BuildContext context, {
    bool listen = true,
  }) {
    if (listen) {
      final value =
          context.dependOnInheritedWidgetOfExactType<BulkCommunications>();
      assert(value != null, 'BulkCommunications is missing above this context.');
      return value!.notifier!;
    }
    final element =
        context.getElementForInheritedWidgetOfExactType<BulkCommunications>();
    final value = element?.widget as BulkCommunications?;
    assert(value != null, 'BulkCommunications is missing above this context.');
    return value!.notifier!;
  }
}
