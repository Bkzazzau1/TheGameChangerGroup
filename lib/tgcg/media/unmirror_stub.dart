import 'package:cross_file/cross_file.dart';

/// Phone and desktop cameras save pictures the right way round.
Future<XFile> unmirrored(XFile photo, {required String name}) async => photo;
