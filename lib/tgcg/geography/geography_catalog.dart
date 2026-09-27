import '../domain/models.dart';

class GeographyNode {
  const GeographyNode({
    required this.id,
    required this.name,
    required this.level,
    this.parentId,
    this.code,
    this.latitude,
    this.longitude,
    this.registeredVoters,
    this.sourceReference,
  });

  final String id;
  final String name;
  final GeographyLevel level;
  final String? parentId;
  final String? code;
  final double? latitude;
  final double? longitude;
  final int? registeredVoters;
  final String? sourceReference;
}

class GeographyCatalog {
  const GeographyCatalog({
    required this.nodes,
    required this.version,
    required this.importedAt,
    required this.sourceName,
  });

  final List<GeographyNode> nodes;
  final String version;
  final DateTime importedAt;
  final String sourceName;

  List<GeographyNode> childrenOf(String parentId) => nodes
      .where((node) => node.parentId == parentId)
      .toList(growable: false);

  List<GeographyNode> atLevel(GeographyLevel level) =>
      nodes.where((node) => node.level == level).toList(growable: false);

  GeographyNode? byId(String id) {
    for (final node in nodes) {
      if (node.id == id) return node;
    }
    return null;
  }

  GeographyNode? byCode(String code) {
    final normalized = code.trim().toLowerCase();
    for (final node in nodes) {
      if (node.code?.trim().toLowerCase() == normalized) return node;
    }
    return null;
  }
}

enum GeographyIssueSeverity { warning, error }

class GeographyImportIssue {
  const GeographyImportIssue({
    required this.code,
    required this.message,
    required this.severity,
    this.recordId,
  });

  final String code;
  final String message;
  final GeographyIssueSeverity severity;
  final String? recordId;
}

class GeographyValidationResult {
  const GeographyValidationResult(this.issues);

  final List<GeographyImportIssue> issues;

  bool get isValid =>
      !issues.any((issue) => issue.severity == GeographyIssueSeverity.error);

  int get errorCount => issues
      .where((issue) => issue.severity == GeographyIssueSeverity.error)
      .length;

  int get warningCount => issues
      .where((issue) => issue.severity == GeographyIssueSeverity.warning)
      .length;
}

class GeographyCatalogValidator {
  const GeographyCatalogValidator._();

  static const Map<GeographyLevel, GeographyLevel?> expectedParent = {
    GeographyLevel.country: null,
    GeographyLevel.geopoliticalZone: GeographyLevel.country,
    GeographyLevel.state: GeographyLevel.geopoliticalZone,
    GeographyLevel.senatorialDistrict: GeographyLevel.state,
    GeographyLevel.lga: GeographyLevel.state,
    GeographyLevel.ward: GeographyLevel.lga,
    GeographyLevel.pollingUnit: GeographyLevel.ward,
  };

  static GeographyValidationResult validate(GeographyCatalog catalog) {
    final issues = <GeographyImportIssue>[];
    final byId = <String, GeographyNode>{};
    final codes = <String>{};

    if (catalog.version.trim().isEmpty) {
      issues.add(const GeographyImportIssue(
        code: 'MISSING_VERSION',
        message: 'Geography catalogue version is required.',
        severity: GeographyIssueSeverity.error,
      ));
    }

    for (final node in catalog.nodes) {
      final id = node.id.trim();
      final name = node.name.trim();

      if (id.isEmpty || name.isEmpty) {
        issues.add(GeographyImportIssue(
          code: 'REQUIRED_FIELD',
          message: 'Geography node id and name are required.',
          severity: GeographyIssueSeverity.error,
          recordId: node.id,
        ));
        continue;
      }

      if (byId.containsKey(id)) {
        issues.add(GeographyImportIssue(
          code: 'DUPLICATE_ID',
          message: 'Duplicate geography node id: $id',
          severity: GeographyIssueSeverity.error,
          recordId: id,
        ));
      } else {
        byId[id] = node;
      }

      final code = node.code?.trim();
      if (code != null && code.isNotEmpty && !codes.add(code.toLowerCase())) {
        issues.add(GeographyImportIssue(
          code: 'DUPLICATE_CODE',
          message: 'Duplicate geography code: $code',
          severity: GeographyIssueSeverity.error,
          recordId: id,
        ));
      }

      if (node.level == GeographyLevel.pollingUnit &&
          (node.latitude == null || node.longitude == null)) {
        issues.add(GeographyImportIssue(
          code: 'POLLING_UNIT_COORDINATES_MISSING',
          message: 'Polling unit $name has no coordinates.',
          severity: GeographyIssueSeverity.warning,
          recordId: id,
        ));
      }
    }

    for (final node in catalog.nodes) {
      final expectedParentLevel = expectedParent[node.level];
      if (expectedParentLevel == null) {
        if (node.parentId != null) {
          issues.add(GeographyImportIssue(
            code: 'COUNTRY_HAS_PARENT',
            message: 'Country node ${node.name} must not have a parent.',
            severity: GeographyIssueSeverity.error,
            recordId: node.id,
          ));
        }
        continue;
      }

      final parentId = node.parentId;
      if (parentId == null || parentId.trim().isEmpty) {
        issues.add(GeographyImportIssue(
          code: 'PARENT_REQUIRED',
          message: '${node.level.name} node ${node.name} requires a parent.',
          severity: GeographyIssueSeverity.error,
          recordId: node.id,
        ));
        continue;
      }

      final parent = byId[parentId];
      if (parent == null) {
        issues.add(GeographyImportIssue(
          code: 'PARENT_NOT_FOUND',
          message: 'Parent $parentId for ${node.name} was not found.',
          severity: GeographyIssueSeverity.error,
          recordId: node.id,
        ));
        continue;
      }

      if (node.level == GeographyLevel.senatorialDistrict ||
          node.level == GeographyLevel.lga) {
        if (parent.level != GeographyLevel.state) {
          issues.add(GeographyImportIssue(
            code: 'INVALID_PARENT_LEVEL',
            message:
                '${node.name} expects a state parent but received ${parent.level.name}.',
            severity: GeographyIssueSeverity.error,
            recordId: node.id,
          ));
        }
        continue;
      }

      if (parent.level != expectedParentLevel) {
        issues.add(GeographyImportIssue(
          code: 'INVALID_PARENT_LEVEL',
          message:
              '${node.name} expects a ${expectedParentLevel.name} parent but received ${parent.level.name}.',
          severity: GeographyIssueSeverity.error,
          recordId: node.id,
        ));
      }
    }

    final countries = catalog.atLevel(GeographyLevel.country);
    if (countries.isEmpty) {
      issues.add(const GeographyImportIssue(
        code: 'COUNTRY_MISSING',
        message: 'The catalogue must include a country root.',
        severity: GeographyIssueSeverity.error,
      ));
    }

    return GeographyValidationResult(List.unmodifiable(issues));
  }
}
