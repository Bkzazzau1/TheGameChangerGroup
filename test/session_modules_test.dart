import 'package:flutter_test/flutter_test.dart';
import 'package:tgcg_emcop/tgcg/session.dart';

void main() {
  group('TGCG role-aware modules', () {
    test('polling unit agent sees operational submission modules only', () {
      final modules = allowedModules(TgcgRole.pollingUnitAgent);

      expect(modules, contains(TgcgModule.overview));
      expect(modules, contains(TgcgModule.geography));
      expect(modules, contains(TgcgModule.fieldMonitoring));
      expect(modules, contains(TgcgModule.resultCapture));
      expect(modules, contains(TgcgModule.communications));

      expect(modules, isNot(contains(TgcgModule.accreditation)));
      expect(modules, isNot(contains(TgcgModule.collation)));
      expect(modules, isNot(contains(TgcgModule.governance)));
    });

    test('national administrator sees every application module', () {
      final modules = allowedModules(TgcgRole.nationalAdministrator);
      expect(modules, containsAll(TgcgModule.values));
    });

    test('read only executive has no submission or accreditation routes', () {
      final modules = allowedModules(TgcgRole.readOnlyExecutive);

      expect(modules, contains(TgcgModule.overview));
      expect(modules, contains(TgcgModule.situationRoom));
      expect(modules, contains(TgcgModule.collation));
      expect(modules, contains(TgcgModule.reports));
      expect(modules, contains(TgcgModule.governance));

      expect(modules, isNot(contains(TgcgModule.accreditation)));
      expect(modules, isNot(contains(TgcgModule.resultCapture)));
    });
  });
}
