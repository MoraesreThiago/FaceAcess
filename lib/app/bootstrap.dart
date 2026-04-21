import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../firebase_options.dart';
import 'app.dart';
import 'flavor.dart';

/// Inicialização comum aos dois entrypoints (`main_admin` e `main_porta`).
///
/// Toda a composição de infraestrutura já vive nos providers em
/// `lib/app/providers/`. Este bootstrap cuida só do que **precisa**
/// acontecer antes do Flutter subir (bindings, chrome do sistema,
/// Firebase) e então dispara o `runApp` com o flavor injetado via
/// override do [appFlavorProvider].
Future<void> bootstrap(AppFlavor flavor) async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Modo kiosk — esconde barra de navegação e status bar.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);

  runApp(
    ProviderScope(
      overrides: [
        appFlavorProvider.overrideWithValue(flavor),
      ],
      child: const FaceAccessApp(),
    ),
  );
}
