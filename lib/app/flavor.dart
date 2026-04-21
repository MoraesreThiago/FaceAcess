import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Qual APK está rodando.
///
/// O valor é fixado no `main_admin.dart` / `main_porta.dart` via override
/// do [appFlavorProvider] dentro do `ProviderScope`. Nenhuma outra parte
/// do app tem autoridade para escolher o flavor — ele é decidido pelo
/// Gradle via `productFlavors`.
enum AppFlavor {
  /// Host das UIs de gestão (portas, pessoas, matriz de acesso). A UI
  /// real é entregue em PRs posteriores; no PR #6.5 o único efeito
  /// visível é o `LoginScreen` mostrar apenas o card de Administrador.
  admin,

  /// Dispositivo de parede para reconhecimento facial. `LoginScreen`
  /// mostra apenas o card "Acesso Porta".
  porta,
}

/// Provider que expõe o flavor atual para a árvore de widgets.
///
/// **Nunca leia este provider sem override** — o default lança para
/// falhar cedo caso alguém esqueça de configurar o entrypoint. Os
/// entrypoints oficiais (`main_admin.dart` / `main_porta.dart`)
/// sobrescrevem este provider no `ProviderScope` raiz.
final appFlavorProvider = Provider<AppFlavor>((ref) {
  throw StateError(
    'appFlavorProvider não foi sobrescrito. Rode o app via '
    '`flutter run --flavor admin -t lib/main_admin.dart` ou '
    '`flutter run --flavor porta -t lib/main_porta.dart`.',
  );
});
