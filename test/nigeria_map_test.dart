import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:tgcg_emcop/tgcg/geography/geography_registry.dart';
import 'package:tgcg_emcop/tgcg/geography/nigeria_map.dart';

void main() {
  final geometry = NigeriaMapGeometry.parse(
    File(nigeriaStatesAsset).readAsStringSync(),
  );

  test('boundary asset covers every canonical state and FCT', () {
    final registry = GeographyRegistry.prototypeSeed();
    expect(
      geometry.states.keys.toSet(),
      registry.states.map((state) => state.id).toSet(),
    );
  });

  test('every label point lies inside its own state', () {
    for (final shape in geometry.states.values) {
      expect(
        geometry.stateAt(shape.labelPoint.dy, shape.labelPoint.dx),
        shape.stateId,
        reason: shape.stateId,
      );
    }
  });

  test('known city coordinates resolve to the correct state', () {
    expect(geometry.stateAt(6.6018, 3.3515), 'LA'); // Ikeja
    expect(geometry.stateAt(9.0579, 7.4951), 'FCT'); // Abuja
    expect(geometry.stateAt(12.0022, 8.5920), 'KN'); // Kano
    expect(geometry.stateAt(10.5105, 7.4165), 'KD'); // Kaduna
    expect(geometry.stateAt(7.7322, 8.5391), 'BN'); // Makurdi
    expect(geometry.stateAt(11.8333, 13.1500), 'BO'); // Maiduguri
    expect(geometry.stateAt(4.8156, 7.0498), 'RI'); // Port Harcourt
    expect(geometry.stateAt(5.0, 2.0), isNull); // Atlantic / Benin
  });

  test('projection keeps the country inside the canvas', () {
    const size = Size(600, 420);
    final projection = NigeriaMapProjection.fit(geometry.bounds, size);
    for (final shape in geometry.states.values) {
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
