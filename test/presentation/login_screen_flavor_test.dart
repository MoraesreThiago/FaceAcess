import 'package:faceaccess/app/flavor.dart';
import 'package:faceaccess/domain/entities/operator_role.dart';
import 'package:faceaccess/domain/entities/tablet_identity.dart';
import 'package:faceaccess/presentation/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Valida o efeito exclusivo do PR #6.5 sobre a UI: cada flavor mostra
/// apenas o card do perfil que pertence àquele APK. A lógica de login
/// (dialog + validação de senha) não é exercida aqui — vive em
/// `login_use_case_test.dart`.
void main() {
  Widget harness(AppFlavor flavor) {
    return ProviderScope(
      overrides: [appFlavorProvider.overrideWithValue(flavor)],
      child: MaterialApp(
        home: LoginScreen(
          identity: const TabletIdentity(id: 'tid', name: 'Porta Teste'),
          assignment: null,
          onLogin: (_) {},
        ),
      ),
    );
  }

  testWidgets('flavor admin mostra somente o card Administrador',
      (tester) async {
    await tester.pumpWidget(harness(AppFlavor.admin));
    await tester.pump();

    expect(find.text('Administrador'), findsOneWidget);
    expect(find.text('Acesso\nPorta'), findsNothing);
    expect(find.text('Acesso de administrador'), findsOneWidget);
  });

  testWidgets('flavor porta mostra somente o card Acesso Porta',
      (tester) async {
    await tester.pumpWidget(harness(AppFlavor.porta));
    await tester.pump();

    expect(find.text('Acesso\nPorta'), findsOneWidget);
    expect(find.text('Administrador'), findsNothing);
    expect(find.text('Acesso porta'), findsOneWidget);
  });

  test('OperatorRole.values continua com admin e porta (sanity)', () {
    expect(OperatorRole.values, containsAll([OperatorRole.admin, OperatorRole.porta]));
  });
}
