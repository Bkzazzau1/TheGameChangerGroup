// Exports the canonical Nigerian geography (zones, states, senatorial
// districts, LGAs) as JSON so the Django backend seeds exactly the same ids.
//
// Usage: dart run tool/export_geography.dart <output.json>
import 'dart:convert';
import 'dart:io';

import 'package:tgcg_emcop/tgcg/geography/geography_registry.dart';
import 'package:tgcg_emcop/tgcg/geography/nigeria_lga_catalog.dart';

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('Usage: dart run tool/export_geography.dart <output.json>');
    exit(64);
  }
  final registry = GeographyRegistry.prototypeSeed();

  final data = {
    'source': 'TheGameChangerGroup Flutter GeographyRegistry',
    'country': 'Nigeria',
    'zones': [
      for (final zone in registry.zones) {'code': zone.id, 'name': zone.name},
    ],
    'states': [
      for (final state in registry.states)
        {
          'code': state.id,
          'name': state.name,
          'zone': state.zoneId,
          'is_fct': state.isFederalCapitalTerritory,
        },
    ],
    'senatorial_districts': [
      for (final state in registry.states)
        for (final district in registry.districtsForState(state.id))
          {
            'code': district.id,
            'name': district.name,
            'state': state.id,
          },
    ],
    'lgas': [
      for (final state in registry.states)
        for (final slug in nigeriaLgaSlugsByStateId[state.id] ?? const <String>[])
          {
            'code': '${state.id}-${slug.toUpperCase().replaceAll("'", '')}',
            'slug': slug,
            'name': nigeriaLgaDisplayName(slug),
            'state': state.id,
            'senatorial_district':
                registry.districtForLgaSlug(state.id, slug)?.id,
          },
    ],
  };

  File(args.single).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(data),
  );
  stdout.writeln(
    'Exported ${(data['states'] as List).length} states, '
    '${(data['senatorial_districts'] as List).length} senatorial districts, '
    '${(data['lgas'] as List).length} LGAs.',
  );
}
