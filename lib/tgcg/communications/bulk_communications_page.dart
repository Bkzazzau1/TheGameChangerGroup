import 'package:flutter/material.dart';

import '../domain/permissions.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'bulk_communications_store.dart';

class BulkCommunicationsPage extends StatefulWidget {
  const BulkCommunicationsPage({super.key});

  @override
  State<BulkCommunicationsPage> createState() => _BulkCommunicationsPageState();
}

enum _BulkWorkspace { audience, compose, delivery, providers }

class _BulkCommunicationsPageState extends State<BulkCommunicationsPage> {
  final titleController = TextEditingController();
  final bodyController = TextEditingController();
  _BulkWorkspace workspace = _BulkWorkspace.audience;
  final List<BulkCommunicationChannel> selectedChannels = [
    BulkCommunicationChannel.push,
    BulkCommunicationChannel.sms,
  ];
  DateTime? scheduledFor;

  @override
  void dispose() {
    titleController.dispose();
    bodyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final store = BulkCommunications.of(context);
    final contacts = store.contactsForScope(session.scope);
    final jobs = store.jobsForScope(session.scope);
    final canSend = TgcgPermissionPolicy.allows(
      session.role!,
      TgcgCapability.sendBroadcast,
    );
    final canManagePreferences = TgcgPermissionPolicy.allows(
      session.role!,
      TgcgCapability.manageMembership,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
      children: [
        TgcgPageHeader(
          eyebrow: 'AUTHORIZED OUTBOUND COMMUNICATIONS',
          title: 'Bulk Communications Centre',
          subtitle:
              '${session.scope.label}: consent-aware operational delivery, channel fallback, delivery jobs and provider readiness.',
          trailing: TgcgStatusPill(
            label: canSend ? 'AUTHORIZED' : 'READ ONLY',
            color: canSend ? TgcgColors.success : TgcgColors.muted,
            icon: canSend ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
          ),
        ),
        const SizedBox(height: 18),
        _MetricGrid(
          totalContacts: contacts.length,
          smsEligible: store.eligibleCount(
            session.scope,
            BulkCommunicationChannel.sms,
          ),
          pushEligible: store.eligibleCount(
            session.scope,
            BulkCommunicationChannel.push,
          ),
          suppressed: store.suppressedCount(session.scope),
          queuedJobs: jobs
              .where((job) =>
                  job.state == BulkDeliveryJobState.queued ||
                  job.state == BulkDeliveryJobState.waitingForProvider ||
                  job.state == BulkDeliveryJobState.processing)
              .length,
        ),
        const SizedBox(height: 16),
        _WorkspaceSelector(
          selected: workspace,
          onChanged: (value) => setState(() => workspace = value),
        ),
        const SizedBox(height: 16),
        switch (workspace) {
          _BulkWorkspace.audience => _AudienceWorkspace(
              contacts: contacts,
              canManagePreferences: canManagePreferences,
              onEdit: (contact) => _editPreference(
                context,
                store: store,
                session: session,
                contact: contact,
              ),
            ),
          _BulkWorkspace.compose => _ComposeWorkspace(
              titleController: titleController,
              bodyController: bodyController,
              selectedChannels: selectedChannels,
              scheduledFor: scheduledFor,
              canSend: canSend,
              contacts: contacts,
              onToggleChannel: _toggleChannel,
              onSchedule: _pickSchedule,
              onClearSchedule: () => setState(() => scheduledFor = null),
              onQueue: () => _queueJob(
                context,
                store: store,
                session: session,
              ),
            ),
          _BulkWorkspace.delivery => _DeliveryWorkspace(jobs: jobs),
          _BulkWorkspace.providers =>
            _ProviderWorkspace(providers: store.providers),
        },
      ],
    );
  }

  void _toggleChannel(BulkCommunicationChannel channel) {
    setState(() {
      if (selectedChannels.contains(channel)) {
        if (selectedChannels.length > 1) selectedChannels.remove(channel);
      } else {
        selectedChannels.add(channel);
      }
    });
  }

  Future<void> _pickSchedule() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: scheduledFor ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: scheduledFor == null
          ? TimeOfDay.fromDateTime(now)
          : TimeOfDay.fromDateTime(scheduledFor!),
    );
    if (time == null || !mounted) return;
    setState(() {
      scheduledFor = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ).toUtc();
    });
  }

  Future<void> _queueJob(
    BuildContext context, {
    required BulkCommunicationsController store,
    required TgcgSessionController session,
  }) async {
    final job = await store.queueJob(
      title: titleController.text,
      body: bodyController.text,
      targetScope: session.scope,
      channels: selectedChannels,
      actorId: session.accessId.isEmpty ? session.operatorName : session.accessId,
      actorRole: session.role!,
      actorScope: session.scope,
      scheduledFor: scheduledFor,
    );
    if (!mounted) return;
    if (job == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The delivery job could not be queued. Check content and permissions.'),
        ),
      );
      return;
    }
    titleController.clear();
    bodyController.clear();
    setState(() {
      scheduledFor = null;
      workspace = _BulkWorkspace.delivery;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${job.id} created for ${job.eligibleRecipientCount} eligible recipient${job.eligibleRecipientCount == 1 ? '' : 's'}.',
        ),
      ),
    );
  }

  Future<void> _editPreference(
    BuildContext context, {
    required BulkCommunicationsController store,
    required TgcgSessionController session,
    required CommunicationContact contact,
  }) async {
    var sms = contact.preference.smsOptIn;
    var push = contact.preference.pushOptIn;
    var email = contact.preference.emailOptIn;
    var voice = contact.preference.voiceOptIn;
    var suppressed = contact.preference.suppressed;
    final sourceController = TextEditingController(
      text: contact.preference.updatedBy == 'UNSET' ? '' : contact.preference.source,
    );

    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Communication preference • ${contact.fullName}'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    contact.scope.label,
                    style: const TextStyle(
                      color: TgcgColors.muted,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: sourceController,
                    decoration: const InputDecoration(
                      labelText: 'Preference / consent source',
                      hintText: 'Example: membership onboarding form',
                      prefixIcon: Icon(Icons.description_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: sms,
                    onChanged: suppressed
                        ? null
                        : (value) => setDialogState(() => sms = value ?? false),
                    title: const Text('SMS'),
                    subtitle: Text(contact.phoneNumber),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: push,
                    onChanged: suppressed || !contact.hasAppDevice
                        ? null
                        : (value) => setDialogState(() => push = value ?? false),
                    title: const Text('Push notification'),
                    subtitle: Text(contact.hasAppDevice
                        ? 'Approved app device available'
                        : 'No approved app device'),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: email,
                    onChanged: suppressed || contact.email == null
                        ? null
                        : (value) => setDialogState(() => email = value ?? false),
                    title: const Text('Email'),
                    subtitle: Text(contact.email ?? 'No email address'),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: voice,
                    onChanged: suppressed
                        ? null
                        : (value) => setDialogState(() => voice = value ?? false),
                    title: const Text('Voice / IVR'),
                    subtitle: Text(contact.phoneNumber),
                  ),
                  const Divider(),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: suppressed,
                    onChanged: (value) => setDialogState(() {
                      suppressed = value;
                      if (value) {
                        sms = false;
                        push = false;
                        email = false;
                        voice = false;
                      }
                    }),
                    title: const Text('Suppress all outbound communications'),
                    subtitle: const Text('Excludes this contact from every bulk delivery job.'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (sourceController.text.trim().isEmpty) return;
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Save preference'),
            ),
          ],
        ),
      ),
    );

    if (save != true || !mounted) {
      sourceController.dispose();
      return;
    }
    final ok = await store.recordPreference(
      memberId: contact.memberId,
      actorId: session.accessId.isEmpty ? session.operatorName : session.accessId,
      actorRole: session.role!,
      actorScope: session.scope,
      source: sourceController.text,
      smsOptIn: sms,
      pushOptIn: push,
      emailOptIn: email,
      voiceOptIn: voice,
      suppressed: suppressed,
    );
    sourceController.dispose();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Communication preference saved.'
            : 'Communication preference was not changed.'),
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({
    required this.totalContacts,
    required this.smsEligible,
    required this.pushEligible,
    required this.suppressed,
    required this.queuedJobs,
  });

  final int totalContacts;
  final int smsEligible;
  final int pushEligible;
  final int suppressed;
  final int queuedJobs;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 1000
              ? 5
              : constraints.maxWidth >= 620
                  ? 3
                  : constraints.maxWidth >= 420
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
                label: 'Contacts in scope',
                value: '$totalContacts',
                icon: Icons.contacts_outlined,
                tone: TgcgMetricTone.info,
              ),
              TgcgMetricCard(
                width: width,
                label: 'SMS eligible',
                value: '$smsEligible',
                icon: Icons.sms_outlined,
                tone: TgcgMetricTone.success,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Push eligible',
                value: '$pushEligible',
                icon: Icons.notifications_active_outlined,
                tone: TgcgMetricTone.ai,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Suppressed',
                value: '$suppressed',
                icon: Icons.block_outlined,
                tone: suppressed == 0
                    ? TgcgMetricTone.neutral
                    : TgcgMetricTone.warning,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Active delivery jobs',
                value: '$queuedJobs',
                icon: Icons.outbox_outlined,
                tone: queuedJobs == 0
                    ? TgcgMetricTone.neutral
                    : TgcgMetricTone.info,
              ),
            ],
          );
        },
      );
}

class _WorkspaceSelector extends StatelessWidget {
  const _WorkspaceSelector({required this.selected, required this.onChanged});

  final _BulkWorkspace selected;
  final ValueChanged<_BulkWorkspace> onChanged;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        padding: const EdgeInsets.all(10),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _chip(_BulkWorkspace.audience, 'Audience', Icons.groups_outlined),
            _chip(_BulkWorkspace.compose, 'Compose', Icons.edit_note_outlined),
            _chip(_BulkWorkspace.delivery, 'Delivery Jobs', Icons.outbox_outlined),
            _chip(_BulkWorkspace.providers, 'Providers', Icons.hub_outlined),
          ],
        ),
      );

  Widget _chip(_BulkWorkspace value, String label, IconData icon) {
    final active = selected == value;
    return ChoiceChip(
      selected: active,
      onSelected: (_) => onChanged(value),
      avatar: Icon(icon, size: 17, color: active ? Colors.white : TgcgColors.primary),
      label: Text(label),
      labelStyle: TextStyle(
        color: active ? Colors.white : TgcgColors.ink,
        fontWeight: FontWeight.w800,
      ),
      selectedColor: TgcgColors.primary,
      backgroundColor: TgcgColors.surfaceSoft,
      side: BorderSide(color: active ? TgcgColors.primary : TgcgColors.border),
      showCheckmark: false,
    );
  }
}

class _AudienceWorkspace extends StatelessWidget {
  const _AudienceWorkspace({
    required this.contacts,
    required this.canManagePreferences,
    required this.onEdit,
  });

  final List<CommunicationContact> contacts;
  final bool canManagePreferences;
  final ValueChanged<CommunicationContact> onEdit;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Authorized contact directory',
        subtitle:
            'Communication eligibility comes from recorded preferences plus available phone, email or approved app-device data.',
        trailing: TgcgStatusPill(
          label: canManagePreferences ? 'PREFERENCE ADMIN' : 'READ ONLY',
          color: canManagePreferences ? TgcgColors.primary : TgcgColors.muted,
          compact: true,
        ),
        child: contacts.isEmpty
            ? const TgcgEmptyState(
                icon: Icons.contacts_outlined,
                title: 'No contacts in scope',
                message: 'Registered members in this geography will appear here.',
              )
            : Column(
                children: contacts
                    .map(
                      (contact) => _ContactRow(
                        contact: contact,
                        onEdit: canManagePreferences ? () => onEdit(contact) : null,
                      ),
                    )
                    .toList(growable: false),
              ),
      );
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.contact, this.onEdit});

  final CommunicationContact contact;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final channels = <Widget>[];
    for (final channel in BulkCommunicationChannel.values) {
      if (contact.eligibleFor(channel)) {
        channels.add(
          Padding(
            padding: const EdgeInsets.only(right: 5),
            child: TgcgStatusPill(
              label: _channelLabel(channel).toUpperCase(),
              color: TgcgColors.success,
              compact: true,
            ),
          ),
        );
      }
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: TgcgColors.surfaceSoft,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: TgcgColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: contact.preference.suppressed
                  ? TgcgColors.danger.withValues(alpha: .08)
                  : TgcgColors.primarySoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              contact.preference.suppressed
                  ? Icons.block_outlined
                  : Icons.person_outline_rounded,
              color: contact.preference.suppressed
                  ? TgcgColors.danger
                  : TgcgColors.primary,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contact.fullName,
                  style: const TextStyle(
                    color: TgcgColors.ink,
                    fontWeight: FontWeight.w900,
                    fontSize: 11.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${contact.phoneNumber} • ${contact.scope.label}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: TgcgColors.muted, fontSize: 9.5),
                ),
                const SizedBox(height: 7),
                Wrap(
                  runSpacing: 5,
                  children: channels.isEmpty
                      ? [
                          TgcgStatusPill(
                            label: contact.preference.suppressed
                                ? 'SUPPRESSED'
                                : 'NO ELIGIBLE CHANNEL',
                            color: contact.preference.suppressed
                                ? TgcgColors.danger
                                : TgcgColors.muted,
                            compact: true,
                          ),
                        ]
                      : channels,
                ),
              ],
            ),
          ),
          if (onEdit != null)
            IconButton(
              tooltip: 'Edit communication preference',
              onPressed: onEdit,
              icon: const Icon(Icons.tune_rounded),
            ),
        ],
      ),
    );
  }
}

class _ComposeWorkspace extends StatelessWidget {
  const _ComposeWorkspace({
    required this.titleController,
    required this.bodyController,
    required this.selectedChannels,
    required this.scheduledFor,
    required this.canSend,
    required this.contacts,
    required this.onToggleChannel,
    required this.onSchedule,
    required this.onClearSchedule,
    required this.onQueue,
  });

  final TextEditingController titleController;
  final TextEditingController bodyController;
  final List<BulkCommunicationChannel> selectedChannels;
  final DateTime? scheduledFor;
  final bool canSend;
  final List<CommunicationContact> contacts;
  final ValueChanged<BulkCommunicationChannel> onToggleChannel;
  final VoidCallback onSchedule;
  final VoidCallback onClearSchedule;
  final VoidCallback onQueue;

  @override
  Widget build(BuildContext context) {
    final eligible = contacts.where((contact) {
      for (final channel in selectedChannels) {
        if (contact.eligibleFor(channel)) return true;
      }
      return false;
    }).length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compose = TgcgSectionCard(
          title: 'Create delivery job',
          subtitle:
              'Channels are evaluated in the order selected; the first eligible channel becomes the contact route.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: titleController,
                enabled: canSend,
                decoration: const InputDecoration(
                  labelText: 'Message title',
                  prefixIcon: Icon(Icons.title_rounded),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: bodyController,
                enabled: canSend,
                minLines: 5,
                maxLines: 9,
                decoration: const InputDecoration(
                  labelText: 'Operational message',
                  hintText: 'Write the logistics, safety, system, incident-response or operational notice.',
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Channel priority',
                style: TextStyle(
                  color: TgcgColors.ink,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: BulkCommunicationChannel.values.map((channel) {
                  final active = selectedChannels.contains(channel);
                  return FilterChip(
                    selected: active,
                    onSelected: canSend ? (_) => onToggleChannel(channel) : null,
                    avatar: Icon(_channelIcon(channel), size: 16),
                    label: Text(_channelLabel(channel)),
                  );
                }).toList(growable: false),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: canSend ? onSchedule : null,
                    icon: const Icon(Icons.schedule_outlined),
                    label: Text(scheduledFor == null ? 'Schedule' : _dateTime(scheduledFor!)),
                  ),
                  if (scheduledFor != null) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: onClearSchedule,
                      child: const Text('Clear'),
                    ),
                  ],
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: canSend ? onQueue : null,
                    icon: const Icon(Icons.outbox_rounded),
                    label: const Text('Queue delivery'),
                  ),
                ],
              ),
            ],
          ),
        );

        final preview = TgcgSectionCard(
          title: 'Recipient preview',
          subtitle: 'Calculated from current scope, recorded preferences and channel availability.',
          child: Column(
            children: [
              _PreviewRow(label: 'Contacts in scope', value: '${contacts.length}'),
              _PreviewRow(label: 'Eligible recipients', value: '$eligible'),
              _PreviewRow(
                label: 'Suppressed',
                value: '${contacts.where((item) => item.preference.suppressed).length}',
              ),
              _PreviewRow(
                label: 'Without eligible route',
                value: '${contacts.length - eligible - contacts.where((item) => item.preference.suppressed).length}',
              ),
              const Divider(),
              ...selectedChannels.map(
                (channel) => _PreviewRow(
                  label: _channelLabel(channel),
                  value:
                      '${contacts.where((contact) => contact.eligibleFor(channel)).length}',
                ),
              ),
            ],
          ),
        );

        if (constraints.maxWidth < 940) {
          return Column(children: [compose, const SizedBox(height: 14), preview]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 7, child: compose),
            const SizedBox(width: 14),
            Expanded(flex: 4, child: preview),
          ],
        );
      },
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: const TextStyle(color: TgcgColors.muted, fontSize: 10.5)),
            ),
            Text(
              value,
              style: const TextStyle(
                color: TgcgColors.ink,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
}

class _DeliveryWorkspace extends StatelessWidget {
  const _DeliveryWorkspace({required this.jobs});
  final List<BulkDeliveryJob> jobs;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Delivery jobs',
        subtitle: 'Queued work is distinct from sent and delivered work.',
        child: jobs.isEmpty
            ? const TgcgEmptyState(
                icon: Icons.outbox_outlined,
                title: 'No delivery jobs',
                message: 'Create an authorized outbound communication to start the delivery queue.',
              )
            : Column(
                children: jobs.map((job) => _JobCard(job: job)).toList(growable: false),
              ),
      );
}

class _JobCard extends StatelessWidget {
  const _JobCard({required this.job});
  final BulkDeliveryJob job;

  @override
  Widget build(BuildContext context) {
    final color = _jobColor(job.state);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TgcgColors.surfaceSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TgcgColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  job.title,
                  style: const TextStyle(
                    color: TgcgColors.ink,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              TgcgStatusPill(
                label: _jobLabel(job.state).toUpperCase(),
                color: color,
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            '${job.id} • ${job.targetScope.label} • ${_dateTime(job.createdAt)}',
            style: const TextStyle(color: TgcgColors.muted, fontSize: 9.5),
          ),
          if (job.scheduledFor != null) ...[
            const SizedBox(height: 4),
            Text(
              'Scheduled: ${_dateTime(job.scheduledFor!)}',
              style: const TextStyle(color: TgcgColors.info, fontSize: 9.5),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            job.body,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: TgcgColors.ink, fontSize: 10.5, height: 1.4),
          ),
          const SizedBox(height: 11),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              _CountChip(label: 'Target', value: job.targetContactCount),
              _CountChip(label: 'Eligible', value: job.eligibleRecipientCount),
              _CountChip(label: 'Suppressed', value: job.suppressedCount),
              _CountChip(label: 'Sent', value: job.sentCount),
              _CountChip(label: 'Delivered', value: job.deliveredCount),
              _CountChip(label: 'Failed', value: job.failedCount),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: job.channels
                .map(
                  (channel) => TgcgStatusPill(
                    label:
                        '${_channelLabel(channel).toUpperCase()} ${job.channelPlan[channel] ?? 0}',
                    color: TgcgColors.primary,
                    compact: true,
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.label, required this.value});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: TgcgColors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: TgcgColors.border),
        ),
        child: Text(
          '$label $value',
          style: const TextStyle(
            color: TgcgColors.muted,
            fontSize: 9,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
}

class _ProviderWorkspace extends StatelessWidget {
  const _ProviderWorkspace({required this.providers});
  final List<BulkDeliveryProvider> providers;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Delivery providers',
        subtitle:
            'Provider secrets and credentials remain backend configuration; this view reports connection readiness and priority.',
        child: Column(
          children: providers.map((provider) {
            final color = _providerColor(provider.state);
            return Container(
              margin: const EdgeInsets.only(bottom: 9),
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: TgcgColors.surfaceSoft,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: TgcgColors.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: .09),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(_channelIcon(provider.channel), color: color),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          provider.name,
                          style: const TextStyle(
                            color: TgcgColors.ink,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${_channelLabel(provider.channel)} • priority ${provider.priority}${provider.supportsDeliveryReceipts ? ' • delivery receipts' : ''}',
                          style: const TextStyle(color: TgcgColors.muted, fontSize: 9.5),
                        ),
                      ],
                    ),
                  ),
                  TgcgStatusPill(
                    label: _providerLabel(provider.state).toUpperCase(),
                    color: color,
                    compact: true,
                  ),
                ],
              ),
            );
          }).toList(growable: false),
        ),
      );
}

String _channelLabel(BulkCommunicationChannel channel) => switch (channel) {
      BulkCommunicationChannel.push => 'Push',
      BulkCommunicationChannel.sms => 'SMS',
      BulkCommunicationChannel.email => 'Email',
      BulkCommunicationChannel.voice => 'Voice / IVR',
    };

IconData _channelIcon(BulkCommunicationChannel channel) => switch (channel) {
      BulkCommunicationChannel.push => Icons.notifications_active_outlined,
      BulkCommunicationChannel.sms => Icons.sms_outlined,
      BulkCommunicationChannel.email => Icons.email_outlined,
      BulkCommunicationChannel.voice => Icons.call_outlined,
    };

String _jobLabel(BulkDeliveryJobState state) => switch (state) {
      BulkDeliveryJobState.draft => 'Draft',
      BulkDeliveryJobState.queued => 'Queued',
      BulkDeliveryJobState.waitingForProvider => 'Waiting for provider',
      BulkDeliveryJobState.processing => 'Processing',
      BulkDeliveryJobState.completed => 'Completed',
      BulkDeliveryJobState.partiallyDelivered => 'Partially delivered',
      BulkDeliveryJobState.failed => 'Failed',
      BulkDeliveryJobState.cancelled => 'Cancelled',
    };

Color _jobColor(BulkDeliveryJobState state) => switch (state) {
      BulkDeliveryJobState.completed => TgcgColors.success,
      BulkDeliveryJobState.processing => TgcgColors.info,
      BulkDeliveryJobState.queued => TgcgColors.info,
      BulkDeliveryJobState.waitingForProvider => TgcgColors.warning,
      BulkDeliveryJobState.partiallyDelivered => TgcgColors.warning,
      BulkDeliveryJobState.failed => TgcgColors.danger,
      BulkDeliveryJobState.cancelled => TgcgColors.muted,
      BulkDeliveryJobState.draft => TgcgColors.muted,
    };

String _providerLabel(ProviderConnectionState state) => switch (state) {
      ProviderConnectionState.notConfigured => 'Not configured',
      ProviderConnectionState.ready => 'Ready',
      ProviderConnectionState.degraded => 'Degraded',
      ProviderConnectionState.unavailable => 'Unavailable',
    };

Color _providerColor(ProviderConnectionState state) => switch (state) {
      ProviderConnectionState.ready => TgcgColors.success,
      ProviderConnectionState.degraded => TgcgColors.warning,
      ProviderConnectionState.unavailable => TgcgColors.danger,
      ProviderConnectionState.notConfigured => TgcgColors.muted,
    };

String _dateTime(DateTime value) {
  final local = value.toLocal();
  final y = local.year.toString();
  final m = local.month.toString().padLeft(2, '0');
  final d = local.day.toString().padLeft(2, '0');
  final h = local.hour.toString().padLeft(2, '0');
  final min = local.minute.toString().padLeft(2, '0');
  return '$y-$m-$d $h:$min';
}
