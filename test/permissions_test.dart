import 'package:flutter_test/flutter_test.dart';
import 'package:tgcg_emcop/tgcg/domain/models.dart';
import 'package:tgcg_emcop/tgcg/domain/permissions.dart';

void main() {
  const national = GeographicScope.nigeria;
  const benue = GeographicScope(
    level: GeographyLevel.state,
    country: 'Nigeria',
    zoneId: 'NG-NC',
    zoneName: 'North Central',
    stateId: 'NG-BN',
    stateName: 'Benue',
  );
  const makurdi = GeographicScope(
    level: GeographyLevel.lga,
    country: 'Nigeria',
    zoneId: 'NG-NC',
    zoneName: 'North Central',
    stateId: 'NG-BN',
    stateName: 'Benue',
    lgaId: 'NG-BN-MKD',
    lgaName: 'Makurdi',
  );
  const gboko = GeographicScope(
    level: GeographyLevel.lga,
    country: 'Nigeria',
    zoneId: 'NG-NC',
    zoneName: 'North Central',
    stateId: 'NG-BN',
    stateName: 'Benue',
    lgaId: 'NG-BN-GBK',
    lgaName: 'Gboko',
  );

  group('TgcgPermissionPolicy', () {
    test('national scope can access state and LGA records', () {
      expect(TgcgPermissionPolicy.scopeAllows(national, benue), isTrue);
      expect(TgcgPermissionPolicy.scopeAllows(national, makurdi), isTrue);
    });

    test('LGA coordinator is confined to assigned LGA', () {
      expect(TgcgPermissionPolicy.scopeAllows(makurdi, makurdi), isTrue);
      expect(TgcgPermissionPolicy.scopeAllows(makurdi, gboko), isFalse);
    });

    test('polling-unit agent can submit results but cannot verify them', () {
      expect(
        TgcgPermissionPolicy.allows(
          TgcgRole.pollingUnitAgent,
          TgcgCapability.submitElectionResult,
        ),
        isTrue,
      );
      expect(
        TgcgPermissionPolicy.allows(
          TgcgRole.pollingUnitAgent,
          TgcgCapability.verifyElectionResult,
        ),
        isFalse,
      );
    });
  });
}
