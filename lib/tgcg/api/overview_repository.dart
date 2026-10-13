import 'api_client.dart';
import 'tracking_repository.dart';

/// Counts for the dashboard, each from the server and only where the
/// account may see it: null where it may not.
class OverviewNumbers {
  const OverviewNumbers({this.members, this.coverage, this.results, this.verifiedResults});

  /// Members registered in the account's areas.
  final int? members;

  /// Today's agent check-ins in the account's area, with the areas below it.
  final Coverage? coverage;

  /// Results received, and how many of them are verified.
  final int? results;
  final int? verifiedResults;
}

/// What the dashboard shows, read from the server's own lists and counts.
class OverviewRepository {
  OverviewRepository(this.client, this.tracking);

  final ApiClient client;
  final TrackingRepository tracking;

  Future<int> _count(String path, [Map<String, String> query = const {}]) async {
    final body = await client.get(path, query: {...query, 'limit': '1'}) as Map<String, dynamic>;
    return body['count'] as int? ?? 0;
  }

  /// Null when the server says the account may not see it, or (for an area
  /// summary) that it must first choose one of several areas.
  static Future<T?> _ifAllowed<T>(Future<T> Function() load) async {
    try {
      return await load();
    } on ApiException catch (error) {
      if (error.statusCode == 403 || error.statusCode == 400) return null;
      rethrow;
    }
  }

  Future<OverviewNumbers> load() async {
    final values = await Future.wait<Object?>([
      _ifAllowed(() => _count('members/')),
      _ifAllowed(tracking.coverage),
      _ifAllowed(() => _count('results/')),
      _ifAllowed(() => _count('results/', {'status': 'verified'})),
    ]);
    return OverviewNumbers(
      members: values[0] as int?,
      coverage: values[1] as Coverage?,
      results: values[2] as int?,
      verifiedResults: values[3] as int?,
    );
  }
}
