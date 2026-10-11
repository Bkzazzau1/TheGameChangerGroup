import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/backend.dart';
import '../api/mapping_repository.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'pin_guide_page.dart';

/// Coordinators map every polling unit in their area before election day.
class UnitMappingPage extends StatefulWidget {
  const UnitMappingPage({super.key});

  @override
  State<UnitMappingPage> createState() => _UnitMappingPageState();
}

class _UnitMappingPageState extends State<UnitMappingPage> {
  MappingStatus? _filter = MappingStatus.unmapped;
  final _search = TextEditingController();
  Timer? _debounce;
  Future<(MappingProgress, ({List<MappingUnit> units, int count}))>? _loading;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loading ??= _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<(MappingProgress, ({List<MappingUnit> units, int count}))> _load() async {
    final mapping = TgcgBackend.of(context)!.mapping;
    final results = await Future.wait([
      mapping.progress(),
      mapping.units(status: _filter, search: _search.text),
    ]);
    return (
      results[0] as MappingProgress,
      results[1] as ({List<MappingUnit> units, int count}),
    );
  }

  void _reload() => setState(() => _loading = _load());

  Future<void> _open(MappingUnit unit) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PinGuidePage(unit: unit)),
    );
    if (changed == true && mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    if (TgcgBackend.of(context) == null) {
      return const Center(
        child: TgcgEmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'Connect to the TGCG server',
          message: 'Polling unit mapping saves pins to the server. Sign in with a server account to use it.',
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        TgcgPageHeader(
          eyebrow: 'BEFORE ELECTION DAY',
          title: 'Polling Unit Mapping',
          subtitle:
              '${session.scope.label}: visit each polling unit and pin its location. INEC publishes no coordinates, so these pins let the app check that agents are at their units.',
        ),
        const SizedBox(height: 16),
        FutureBuilder(
          future: _loading,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              final error = snapshot.error;
              return TgcgEmptyState(
                icon: Icons.cloud_off_outlined,
                title: 'Could not load polling units',
                message: error is ApiException ? error.message : '$error',
                action: TextButton(onPressed: _reload, child: const Text('Try again')),
              );
            }
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final (progress, page) = snapshot.data!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ProgressCard(progress: progress),
                const SizedBox(height: 16),
                _filters(),
                const SizedBox(height: 10),
                TextField(
                  controller: _search,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    labelText: 'Search by code, name or location',
                  ),
                  onChanged: (_) {
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 400), _reload);
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  '${page.count} polling unit${page.count == 1 ? '' : 's'}'
                  '${page.count > page.units.length ? ' (first ${page.units.length} shown; search to narrow)' : ''}',
                  style: const TextStyle(color: TgcgColors.muted, fontSize: 12),
                ),
                const SizedBox(height: 8),
                if (page.units.isEmpty)
                  const TgcgEmptyState(
                    icon: Icons.task_alt_rounded,
                    title: 'Nothing here',
                    message: 'No polling units match this filter.',
                  )
                else
                  for (final unit in page.units) _UnitTile(unit: unit, onTap: () => _open(unit)),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _filters() => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final option in <(MappingStatus?, String)>[
            (MappingStatus.unmapped, 'Not mapped'),
            (MappingStatus.pinned, 'Pinned'),
            (MappingStatus.confirmed, 'Confirmed'),
            (MappingStatus.conflict, 'Conflicts'),
            (MappingStatus.problem, 'Problems'),
            (null, 'All'),
          ])
            ChoiceChip(
              label: Text(option.$2),
              selected: _filter == option.$1,
              onSelected: (_) {
                _filter = option.$1;
                _reload();
              },
            ),
        ],
      );
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.progress});
  final MappingProgress progress;

  @override
  Widget build(BuildContext context) {
    int n(MappingStatus s) => progress.counts[s] ?? 0;
    return TgcgSectionCard(
      title: '${progress.mappedPercent.toStringAsFixed(1)}% mapped',
      subtitle: '${progress.mapped} of ${progress.total} polling units have a location.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress.total == 0 ? 0 : progress.mapped / progress.total,
              minHeight: 10,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              TgcgStatusPill(label: '${n(MappingStatus.confirmed)} CONFIRMED', color: TgcgColors.success, compact: true),
              TgcgStatusPill(label: '${n(MappingStatus.pinned)} PINNED ONCE', color: TgcgColors.primary, compact: true),
              TgcgStatusPill(label: '${n(MappingStatus.conflict)} CONFLICTS', color: TgcgColors.danger, compact: true),
              TgcgStatusPill(label: '${n(MappingStatus.problem)} PROBLEMS', color: TgcgColors.warning, compact: true),
              TgcgStatusPill(label: '${n(MappingStatus.unmapped)} TO MAP', color: TgcgColors.muted, compact: true),
            ],
          ),
        ],
      ),
    );
  }
}

(String, Color) mappingStatusLabel(MappingStatus status) => switch (status) {
      MappingStatus.unmapped => ('NOT MAPPED', TgcgColors.muted),
      MappingStatus.pinned => ('PINNED ONCE', TgcgColors.primary),
      MappingStatus.confirmed => ('CONFIRMED', TgcgColors.success),
      MappingStatus.conflict => ('CONFLICT', TgcgColors.danger),
      MappingStatus.problem => ('PROBLEM', TgcgColors.warning),
    };

class _UnitTile extends StatelessWidget {
  const _UnitTile({required this.unit, required this.onTap});
  final MappingUnit unit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (label, color) = mappingStatusLabel(unit.status);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          unit.status == MappingStatus.unmapped ? Icons.add_location_alt_outlined : Icons.place_rounded,
          color: color,
        ),
        title: Text(unit.name, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(
          '${unit.code} · ${unit.wardName}${unit.location.isEmpty ? '' : '\n${unit.location}'}',
          style: const TextStyle(fontSize: 12, color: TgcgColors.muted),
        ),
        isThreeLine: unit.location.isNotEmpty,
        trailing: TgcgStatusPill(label: label, color: color, compact: true),
      ),
    );
  }
}
