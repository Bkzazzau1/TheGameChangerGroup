import 'package:flutter/widgets.dart';

import 'tgcg/app.dart';
import 'tgcg/media/device_media.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  registerDesktopCameraDelegate();
  runApp(const TgcgApp());
}
