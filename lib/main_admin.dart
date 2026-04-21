import 'app/bootstrap.dart';
import 'app/flavor.dart';

/// Entrypoint do APK **admin**.
///
/// Invocar com:
/// ```
/// flutter run --flavor admin -t lib/main_admin.dart
/// flutter build apk --flavor admin -t lib/main_admin.dart
/// ```
Future<void> main() => bootstrap(AppFlavor.admin);
