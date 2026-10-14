import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/backend.dart';
import '../api/reference_repository.dart';
import '../ui/tgcg_design.dart';

/// Finds a polling unit by name, for someone who cannot read the code on
/// their PVC: the state, the LGA and the ward, each picked from a list that
/// typing narrows, then the unit. Returns the chosen polling unit.
class PollingUnitFinderPage extends StatefulWidget {
  const PollingUnitFinderPage({super.key});

  @override
  State<PollingUnitFinderPage> createState() => _PollingUnitFinderPageState();
}

class _PollingUnitFinderPageState extends State<PollingUnitFinderPage> {
  static const _titles = [
    'Choose your state',
    'Choose your LGA',
    'Choose your ward',
    'Choose your polling unit',
  ];

  late ReferenceRepository _reference;
  bool _started = false;
  final _filter = TextEditingController();

  /// The state, LGA and ward chosen so far.
  final _chosen = <RegistrationPlace>[];

  /// Lists already loaded, by the codes chosen before them.
  final _loaded = <String, List<RegistrationPlace>>{};
  String? _error;

  int get _level => _chosen.length;
  String get _key => _chosen.map((place) => place.code).join('/');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reference = TgcgBackend.of(context)!.reference;
    if (!_started) {
      _started = true;
      _load();
    }
  }

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final key = _key;
    if (_loaded.containsKey(key)) return;
    final parent = _chosen.isEmpty ? null : _chosen.last.code;
    try {
      final places = await _reference.registrationPlaces(
        state: _level == 1 ? parent : null,
        lga: _level == 2 ? parent : null,
        ward: _level == 3 ? parent : null,
      );
      if (mounted) setState(() => _loaded[key] = places);
    } on ApiException catch (error) {
      if (mounted && key == _key) {
        setState(() => _error = error.isOffline
            ? 'No connection. Check your internet and try again.'
            : error.message);
      }
    }
  }

  void _show(void Function() change) {
    setState(() {
      change();
      _filter.clear();
      _error = null;
    });
    _load();
  }

  void _choose(RegistrationPlace place) {
    if (_level == _titles.length - 1) {
      Navigator.of(context).pop(place);
    } else {
      _show(() => _chosen.add(place));
    }
  }

  /// Lower case words without punctuation, so "pri sch" finds "PRI. SCH.".
  static String _plain(String text) => text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  List<RegistrationPlace> _matching(List<RegistrationPlace> places) {
    final words = _plain(_filter.text).split(' ').where((word) => word.isNotEmpty).toList();
    if (words.isEmpty) return places;
    return [
      for (final place in places)
        if (_plain('${place.name} ${place.location} ${place.code}') case final text
            when words.every(text.contains))
          place,
    ];
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: _level == 0,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _show(_chosen.removeLast);
        },
        child: Scaffold(
          appBar: AppBar(title: const Text('Find your polling unit')),
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_chosen.isNotEmpty)
                        Text(
                          _chosen.map((place) => place.name).join(' › '),
                          style: const TextStyle(color: TgcgColors.muted, fontWeight: FontWeight.w700),
                        ),
                      const SizedBox(height: 4),
                      Text(_titles[_level], style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _filter,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search_rounded),
                          labelText: 'Type part of the name',
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(child: _list()),
              ],
            ),
          ),
        ),
      );

  Widget _list() {
    if (_error case final error?) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              TextButton(onPressed: () => _show(() {}), child: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    final places = _loaded[_key];
    if (places == null) return const Center(child: CircularProgressIndicator());
    final shown = _matching(places);
    if (shown.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            places.isEmpty ? 'Nothing is listed here.' : 'Nothing matches "${_filter.text.trim()}".',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final lastLevel = _level == _titles.length - 1;
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: shown.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final place = shown[index];
        final details = [
          if (place.location.isNotEmpty) place.location,
          if (lastLevel) place.code,
        ];
        return ListTile(
          title: Text(place.name, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: details.isEmpty ? null : Text(details.join(' · ')),
          trailing: lastLevel ? null : const Icon(Icons.chevron_right_rounded),
          onTap: () => _choose(place),
        );
      },
    );
  }
}
