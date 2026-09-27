import 'offline_database_contract.dart';
import 'offline_database_stub.dart'
    if (dart.library.io) 'offline_database_native.dart' as platform;

export 'offline_database_contract.dart';

Future<OfflineDatabaseBackend> openOfflineDatabase() =>
    platform.openOfflineDatabaseBackend();
