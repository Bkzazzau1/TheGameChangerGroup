import 'package:flutter_test/flutter_test.dart';
import 'package:tgcg_emcop/tgcg/domain/models.dart';
import 'package:tgcg_emcop/tgcg/field/field_operations_store.dart';

void main() {
  group('FieldOperationsController', () {
    test('country scope sees all prototype incidents', () {
      final store = FieldOperationsController.prototypeSeed();

      expect(store.incidentsForScope(GeographicScope.nigeria).length, 4);
      expect(store.reportsForScope(GeographicScope.nigeria).length, 3);
    });

    test('state scope only sees matching state records', () {
      final store = FieldOperationsController.prototypeSeed();
      const kaduna = GeographicScope(
        level: GeographyLevel.state,
        country: 'Nigeria',
        zoneId: 'NW',
        zoneName: 'North West',
        stateId: 'KD',
        stateName: 'Kaduna',
      );

      final incidents = store.incidentsForScope(kaduna);
      final reports = store.reportsForScope(kaduna);

      expect(incidents.length, 1);
      expect(incidents.single.scope.stateId, 'KD');
      expect(reports.length, 1);
      expect(reports.single.scope.stateId, 'KD');
    });

    test('incident status update is shared operational state', () {
      final store = FieldOperationsController.prototypeSeed();
      final before = store.incidents.firstWhere((item) => item.id == 'INC-0004');
      expect(before.status, IncidentStatus.reported);

      store.updateIncidentStatus('INC-0004', IncidentStatus.acknowledged);

      final after = store.incidents.firstWhere((item) => item.id == 'INC-0004');
      expect(after.status, IncidentStatus.acknowledged);
    });
  });
}
