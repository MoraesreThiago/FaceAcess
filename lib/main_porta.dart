import 'app/bootstrap.dart';
import 'app/flavor.dart';

/// Entrypoint do APK **porta** (dispositivo de parede, reconhecimento
/// facial).
///
/// Invocar com:
/// ```
/// flutter run --flavor porta -t lib/main_porta.dart
/// flutter build apk --flavor porta -t lib/main_porta.dart
/// ```
Future<void> main() => bootstrap(AppFlavor.porta);
