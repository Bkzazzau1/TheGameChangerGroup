import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:tgcg_emcop/tgcg/geography/geography_registry.dart';
import 'package:tgcg_emcop/tgcg/geography/nigeria_map.dart';

GeoShapeSet _lgas(String stateId) =>
    GeoShapeSet.parse(File(nigeriaLgaAsset(stateId)).readAsStringSync(), 'lgas');

void main() {
  final registry = GeographyRegistry.prototypeSeed();
  final states = GeoShapeSet.parse(
    File(nigeriaStatesAsset).readAsStringSync(),
    'states',
  );

  test('boundary asset covers every canonical state and FCT', () {
    expect(
      states.shapes.keys.toSet(),
      registry.states.map((state) => state.id).toSet(),
    );
  });

  test('every label point lies inside its own state', () {
    for (final shape in states.shapes.values) {
      expect(
        states.idAt(shape.labelPoint.dy, shape.labelPoint.dx),
        shape.id,
        reason: shape.id,
      );
    }
  });

  test('known city coordinates resolve to the correct state', () {
    expect(states.idAt(6.6018, 3.3515), 'LA'); // Ikeja
    expect(states.idAt(9.0579, 7.4951), 'FCT'); // Abuja
    expect(states.idAt(12.0022, 8.5920), 'KN'); // Kano
    expect(states.idAt(10.5105, 7.4165), 'KD'); // Kaduna
    expect(states.idAt(7.7322, 8.5391), 'BN'); // Makurdi
    expect(states.idAt(11.8333, 13.1500), 'BO'); // Maiduguri
    expect(states.idAt(4.8156, 7.0498), 'RI'); // Port Harcourt
    expect(states.idAt(5.0, 2.0), isNull); // Atlantic / Benin
  });

  test('LGA boundaries match the canonical LGA ids of every state', () {
    var total = 0;
    for (final state in registry.states) {
      final shapes = _lgas(state.id);
      expect(
        shapes.shapes.keys.toSet(),
        registry.lgasForState(state.id).map((lga) => lga.id).toSet(),
        reason: state.id,
      );
      total += shapes.shapes.length;
    }
    expect(total, 774);
  });

  test('LGA label points sit inside their parent state', () {
    for (final state in registry.states) {
      for (final lga in _lgas(state.id).shapes.values) {
        expect(
          states.idAt(lga.labelPoint.dy, lga.labelPoint.dx),
          state.id,
          reason: lga.id,
        );
      }
    }
  });

  test('known places resolve to the correct LGA', () {
    expect(_lgas('LA').idAt(6.6018, 3.3515), 'LA-IKEJA');
    expect(_lgas('KD').idAt(10.5222, 7.4383), 'KD-KADUNA-NORTH');
    expect(_lgas('BN').idAt(7.7322, 8.5391), 'BN-MAKURDI');
    expect(_lgas('FCT').idAt(9.0579, 7.4951), 'FCT-ABUJA-MUNICIPAL');
  });

  test('projection keeps the country inside the canvas', () {
    const size = Size(600, 420);
    final projection = GeoProjection.fit(states.bounds, size);
    for (final shape in states.shapes.values) {
      final rect = projection.pathFor(shape).getBounds();
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(size.width));
      expect(rect.bottom, lessThanOrEqualTo(size.height));
    }
    // North is up: Kano renders above Lagos.
    expect(
      projection.project(12.0, 8.59).dy,
      lessThan(projection.project(6.52, 3.38).dy),
    );
  });
}
