/// Entrypoint *placeholder*.
///
/// A partir do PR #6.5 o app é construído em dois flavors distintos
/// (`admin` e `porta`), cada um com seu próprio entrypoint:
///
///   - `lib/main_admin.dart`  →  `flutter run --flavor admin -t lib/main_admin.dart`
///   - `lib/main_porta.dart`  →  `flutter run --flavor porta -t lib/main_porta.dart`
///
/// Este arquivo existe apenas para produzir uma mensagem de erro clara
/// caso alguém rode `flutter run` sem passar `-t`, o que usaria
/// `lib/main.dart` por padrão e silenciosamente escolheria um flavor
/// errado.
void main() {
  throw StateError(
    'Escolha um flavor explicitamente:\n'
    '  flutter run --flavor admin -t lib/main_admin.dart\n'
    '  flutter run --flavor porta -t lib/main_porta.dart',
  );
}
