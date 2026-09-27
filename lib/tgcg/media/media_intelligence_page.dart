import 'package:flutter/material.dart';

import '../ui/tgcg_design.dart';

class MediaIntelligencePage extends StatefulWidget {
  const MediaIntelligencePage({super.key});

  @override
  State<MediaIntelligencePage> createState() => _MediaIntelligencePageState();
}

enum _MediaSource { onlineNews, television, radio, social, blog }
enum _SignalState { verified, monitoring, review }
enum _MediaPriority { normal, watch, urgent }

class _MediaSignal {
  const _MediaSignal({
    required this.id,
    required this.headline,
    required this.source,
    required this.sourceName,
    required this.topic,
    required this.location,
    required this.state,
    required this.priority,
    required this.minutesAgo,
    required this.summary,
  });

  final String id;
  final String headline;
  final _MediaSource source;
  final String sourceName;
  final String topic;
  final String location;
  final _SignalState state;
  final _MediaPriority priority;
  final int minutesAgo;
  final String summary;
}

class _TopicPulse {
  const _TopicPulse(this.label, this.volume, this.change, this.icon);

  final String label;
  final int volume;
  final int change;
  final IconData icon;
}

class _MediaIntelligencePageState extends State<MediaIntelligencePage> {
  String query = '';
  _MediaSource? sourceFilter;
  _SignalState? stateFilter;
  String? selectedSignalId;

  static const _signals = <_MediaSignal>[
    _MediaSignal(
      id: 'MED-1042',
      headline: 'Election logistics and polling-unit readiness draw increased coverage',
      source: _MediaSource.onlineNews,
      sourceName: 'National News Desk',
      topic: 'Election Logistics',
      location: 'National',
      state: _SignalState.verified,
      priority: _MediaPriority.watch,
      minutesAgo: 8,
      summary:
          'Coverage is focused on deployment timelines, polling-unit preparation and operational readiness across multiple states.',
    ),
    _MediaSignal(
      id: 'MED-1041',
      headline: 'Radio discussions focus on accreditation procedures and opening times',
      source: _MediaSource.radio,
      sourceName: 'Regional Radio Monitor',
      topic: 'Accreditation',
      location: 'North West',
      state: _SignalState.monitoring,
      priority: _MediaPriority.normal,
      minutesAgo: 14,
      summary:
          'Public discussion is centered on voter accreditation procedures, polling-unit opening expectations and access to official information.',
    ),
    _MediaSignal(
      id: 'MED-1040',
      headline: 'Conflicting social posts circulate about result-sheet availability',
      source: _MediaSource.social,
      sourceName: 'Public Social Monitor',
      topic: 'Result Materials',
      location: 'South West',
      state: _SignalState.review,
      priority: _MediaPriority.urgent,
      minutesAgo: 19,
      summary:
          'Multiple public posts repeat conflicting claims about election materials. The item is queued for source verification before operational escalation.',
    ),
    _MediaSignal(
      id: 'MED-1039',
      headline: 'Television panel highlights election security coordination and incident response',
      source: _MediaSource.television,
      sourceName: 'Broadcast Monitor',
      topic: 'Security & Safety',
      location: 'National',
      state: _SignalState.verified,
      priority: _MediaPriority.watch,
      minutesAgo: 27,
      summary:
          'The discussion focused on public safety, response coordination and the need for verified incident information from official channels.',
    ),
    _MediaSignal(
      id: 'MED-1038',
      headline: 'Online coverage tracks accessibility at polling locations',
      source: _MediaSource.blog,
      sourceName: 'Civic Monitoring Desk',
      topic: 'Polling Access',
      location: 'North Central',
      state: _SignalState.monitoring,
      priority: _MediaPriority.normal,
      minutesAgo: 34,
      summary:
          'Coverage highlights physical access, queue management and accessibility considerations at selected polling locations.',
    ),
    _MediaSignal(
      id: 'MED-1037',
      headline: 'Public discussion rises around official result publication channels',
      source: _MediaSource.social,
      sourceName: 'Public Social Monitor',
      topic: 'Result Publication',
      location: 'National',
      state: _SignalState.monitoring,
      priority: _MediaPriority.watch,
      minutesAgo: 42,
      summary:
          'Conversation volume is increasing around where and how official election results will be published and verified.',
    ),
  ];

  static const _topics = <_TopicPulse>[
    _TopicPulse('Election Logistics', 86, 18, Icons.local_shipping_outlined),
    _TopicPulse('Accreditation', 73, 12, Icons.badge_outlined),
    _TopicPulse('Security & Safety', 61, 8, Icons.shield_outlined),
    _TopicPulse('Result Publication', 54, 16, Icons.fact_check_outlined),
    _TopicPulse('Polling Access', 42, 5, Icons.accessible_forward_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final filtered = _signals.where((item) {
      final normalized = query.trim().toLowerCase();
      final matchesQuery = normalized.isEmpty ||
          item.headline.toLowerCase().contains(normalized) ||
          item.topic.toLowerCase().contains(normalized) ||
          item.location.toLowerCase().contains(normalized) ||
          item.sourceName.toLowerCase().contains(normalized);
      final matchesSource = sourceFilter == null || item.source == sourceFilter;
      final matchesState = stateFilter == null || item.state == stateFilter;
      return matchesQuery && matchesSource && matchesState;
    }).toList(growable: false);

    final selected = _signals
        .where((item) => item.id == selectedSignalId)
        .cast<_MediaSignal?>()
        .firstOrNull;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
      children: [
        const TgcgPageHeader(
          eyebrow: 'PUBLIC MEDIA MONITORING',
          title: 'Media Intelligence',
          subtitle:
              'Monitor public reporting, broadcast coverage, emerging operational topics and information that requires verification.',
          trailing: TgcgStatusPill(
            label: 'MEDIA DESK',
            color: TgcgColors.ai,
            icon: Icons.insights_outlined,
          ),
        ),
        const SizedBox(height: 18),
        const _MediaMetrics(),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final pulse = const _TopicPulsePanel();
            final sources = const _SourceCoveragePanel();
            if (constraints.maxWidth < 960) {
              return const Column(
                children: [
                  _TopicPulsePanel(),
                  SizedBox(height: 14),
                  _SourceCoveragePanel(),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 7, child: pulse),
                const SizedBox(width: 14),
                Expanded(flex: 4, child: sources),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _FilterBar(
          query: query,
          source: sourceFilter,
          state: stateFilter,
          onQueryChanged: (value) => setState(() => query = value),
          onSourceChanged: (value) => setState(() => sourceFilter = value),
          onStateChanged: (value) => setState(() => stateFilter = value),
          onClear: () => setState(() {
            query = '';
            sourceFilter = null;
            stateFilter = null;
          }),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final feed = _MediaFeed(
              signals: filtered,
              selectedId: selectedSignalId,
              onSelect: (id) => setState(() => selectedSignalId = id),
            );
            final inspector = _SignalInspector(signal: selected);
            if (constraints.maxWidth < 1020) {
              return Column(
                children: [
                  feed,
                  const SizedBox(height: 14),
                  inspector,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 7, child: feed),
                const SizedBox(width: 14),
                Expanded(flex: 4, child: inspector),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _MediaMetrics extends StatelessWidget {
  const _MediaMetrics();

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
                label: 'Media items',
                value: '248',
                detail: 'Captured across monitored public sources',
                icon: Icons.library_books_outlined,
                tone: TgcgMetricTone.info,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Sources',
                value: '38',
                detail: 'News, broadcast, radio and public social sources',
                icon: Icons.hub_outlined,
                tone: TgcgMetricTone.neutral,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Active topics',
                value: '7',
                detail: 'Operational themes with notable coverage',
                icon: Icons.trending_up_rounded,
                tone: TgcgMetricTone.success,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Verification queue',
                value: '12',
                detail: 'Items requiring source confirmation',
                icon: Icons.fact_check_outlined,
                tone: TgcgMetricTone.warning,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Priority watch',
                value: '4',
                detail: 'Operational mentions requiring attention',
                icon: Icons.notification_important_outlined,
                tone: TgcgMetricTone.ai,
              ),
            ],
          );
        },
      );
}

class _TopicPulsePanel extends StatelessWidget {
  const _TopicPulsePanel();

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Topic pulse',
        subtitle: 'Coverage volume across monitored election-operation themes.',
        trailing: const TgcgStatusPill(
          label: '24H VIEW',
          color: TgcgColors.primary,
          icon: Icons.schedule_rounded,
          compact: true,
        ),
        child: Column(
          children: _MediaIntelligencePageState._topics
              .map((topic) => _TopicPulseRow(topic: topic))
              .toList(),
        ),
      );
}

class _TopicPulseRow extends StatelessWidget {
  const _TopicPulseRow({required this.topic});

  final _TopicPulse topic;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: TgcgColors.primarySoft,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(topic.icon, color: TgcgColors.primary, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          topic.label,
                          style: const TextStyle(
                            color: TgcgColors.ink,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Text(
                        '${topic.change >= 0 ? '+' : ''}${topic.change}%',
                        style: const TextStyle(
                          color: TgcgColors.success,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: topic.volume / 100,
                      minHeight: 7,
                      backgroundColor: TgcgColors.surfaceSoft,
                      valueColor:
                          const AlwaysStoppedAnimation(TgcgColors.primary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 28,
              child: Text(
                '${topic.volume}',
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: TgcgColors.ink,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      );
}

class _SourceCoveragePanel extends StatelessWidget {
  const _SourceCoveragePanel();

  @override
  Widget build(BuildContext context) {
    const sources = [
      ('Online News', 34, Icons.public_rounded, TgcgColors.info),
      ('Television', 18, Icons.tv_outlined, TgcgColors.ai),
      ('Radio', 22, Icons.radio_outlined, TgcgColors.warning),
      ('Public Social', 20, Icons.tag_rounded, TgcgColors.primary),
      ('Blogs / Civic', 6, Icons.article_outlined, TgcgColors.muted),
    ];
    return TgcgSectionCard(
      title: 'Source coverage',
      subtitle: 'Current distribution of monitored public media items.',
      child: Column(
        children: sources
            .map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: item.$4.withValues(alpha: .09),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(item.$3, size: 17, color: item.$4),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        item.$1,
                        style: const TextStyle(
                          color: TgcgColors.ink,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      '${item.$2}%',
                      style: const TextStyle(
                        color: TgcgColors.muted,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.query,
    required this.source,
    required this.state,
    required this.onQueryChanged,
    required this.onSourceChanged,
    required this.onStateChanged,
    required this.onClear,
  });

  final String query;
  final _MediaSource? source;
  final _SignalState? state;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<_MediaSource?> onSourceChanged;
  final ValueChanged<_SignalState?> onStateChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        padding: const EdgeInsets.all(14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final search = SizedBox(
              width: constraints.maxWidth < 620 ? constraints.maxWidth : 330,
              child: TextFormField(
                initialValue: query,
                onChanged: onQueryChanged,
                decoration: const InputDecoration(
                  hintText: 'Search media, topic or location',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
            );
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                search,
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<_MediaSource?>(
                    initialValue: source,
                    decoration: const InputDecoration(labelText: 'Source'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All sources')),
                      ..._MediaSource.values.map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(_sourceLabel(value)),
                        ),
                      ),
                    ],
                    onChanged: onSourceChanged,
                  ),
                ),
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<_SignalState?>(
                    initialValue: state,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All statuses')),
                      ..._SignalState.values.map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(_stateLabel(value)),
                        ),
                      ),
                    ],
                    onChanged: onStateChanged,
                  ),
                ),
                TextButton.icon(
                  onPressed: onClear,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Reset'),
                ),
              ],
            );
          },
        ),
      );
}

class _MediaFeed extends StatelessWidget {
  const _MediaFeed({
    required this.signals,
    required this.selectedId,
    required this.onSelect,
  });

  final List<_MediaSignal> signals;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Media feed',
        subtitle: 'Public-source items organized for operational review.',
        trailing: TgcgStatusPill(
          label: '${signals.length} ITEMS',
          color: TgcgColors.info,
          compact: true,
        ),
        child: signals.isEmpty
            ? const TgcgEmptyState(
                icon: Icons.search_off_rounded,
                title: 'No matching media item',
                message: 'Adjust the filters to view more monitored coverage.',
              )
            : Column(
                children: signals
                    .map(
                      (signal) => _MediaSignalTile(
                        signal: signal,
                        selected: signal.id == selectedId,
                        onTap: () => onSelect(signal.id),
                      ),
                    )
                    .toList(),
              ),
      );
}

class _MediaSignalTile extends StatelessWidget {
  const _MediaSignalTile({
    required this.signal,
    required this.selected,
    required this.onTap,
  });

  final _MediaSignal signal;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _priorityColor(signal.priority);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected ? color.withValues(alpha: .055) : TgcgColors.surfaceSoft,
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(15),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: selected ? color.withValues(alpha: .28) : TgcgColors.border,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .09),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(_sourceIcon(signal.source), color: color, size: 20),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        signal.headline,
                        style: const TextStyle(
                          color: TgcgColors.ink,
                          fontSize: 11.5,
                          height: 1.35,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          TgcgStatusPill(
                            label: _sourceLabel(signal.source).toUpperCase(),
                            color: TgcgColors.muted,
                            compact: true,
                          ),
                          TgcgStatusPill(
                            label: signal.topic.toUpperCase(),
                            color: TgcgColors.primary,
                            compact: true,
                          ),
                          TgcgStatusPill(
                            label: _stateLabel(signal.state).toUpperCase(),
                            color: _stateColor(signal.state),
                            compact: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Text(
                        '${signal.sourceName} • ${signal.location} • ${signal.minutesAgo}m',
                        style: const TextStyle(
                          color: TgcgColors.muted,
                          fontSize: 9.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: TgcgColors.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SignalInspector extends StatelessWidget {
  const _SignalInspector({required this.signal});

  final _MediaSignal? signal;

  @override
  Widget build(BuildContext context) {
    final item = signal;
    return TgcgSectionCard(
      title: 'Signal detail',
      subtitle: 'Source, verification state and operational context.',
      child: item == null
          ? const TgcgEmptyState(
              icon: Icons.touch_app_outlined,
              title: 'Select a media item',
              message: 'Choose an item from the media feed to inspect its details.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [TgcgColors.primaryDark, TgcgColors.primary],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.id,
                        style: const TextStyle(
                          color: TgcgColors.accent,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        item.headline,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          height: 1.3,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _Detail('Source', item.sourceName),
                _Detail('Channel', _sourceLabel(item.source)),
                _Detail('Topic', item.topic),
                _Detail('Coverage area', item.location),
                _Detail('Status', _stateLabel(item.state)),
                _Detail('Priority', _priorityLabel(item.priority)),
                const Divider(),
                const Text(
                  'Summary',
                  style: TextStyle(
                    color: TgcgColors.ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  item.summary,
                  style: const TextStyle(
                    color: TgcgColors.muted,
                    fontSize: 11,
                    height: 1.5,
                  ),
                ),
              ],
            ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 110,
              child: Text(
                label,
                style: const TextStyle(color: TgcgColors.muted, fontSize: 10),
              ),
            ),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: TgcgColors.ink,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );
}

String _sourceLabel(_MediaSource source) => switch (source) {
      _MediaSource.onlineNews => 'Online News',
      _MediaSource.television => 'Television',
      _MediaSource.radio => 'Radio',
      _MediaSource.social => 'Public Social',
      _MediaSource.blog => 'Blogs / Civic',
    };

IconData _sourceIcon(_MediaSource source) => switch (source) {
      _MediaSource.onlineNews => Icons.public_rounded,
      _MediaSource.television => Icons.tv_outlined,
      _MediaSource.radio => Icons.radio_outlined,
      _MediaSource.social => Icons.tag_rounded,
      _MediaSource.blog => Icons.article_outlined,
    };

String _stateLabel(_SignalState state) => switch (state) {
      _SignalState.verified => 'Verified',
      _SignalState.monitoring => 'Monitoring',
      _SignalState.review => 'Needs Review',
    };

Color _stateColor(_SignalState state) => switch (state) {
      _SignalState.verified => TgcgColors.success,
      _SignalState.monitoring => TgcgColors.info,
      _SignalState.review => TgcgColors.warning,
    };

String _priorityLabel(_MediaPriority priority) => switch (priority) {
      _MediaPriority.normal => 'Normal',
      _MediaPriority.watch => 'Watch',
      _MediaPriority.urgent => 'Urgent',
    };

Color _priorityColor(_MediaPriority priority) => switch (priority) {
      _MediaPriority.normal => TgcgColors.info,
      _MediaPriority.watch => TgcgColors.warning,
      _MediaPriority.urgent => TgcgColors.danger,
    };

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
