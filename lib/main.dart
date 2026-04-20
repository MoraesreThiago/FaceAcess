import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'firebase_options.dart';

/// Bootstrap mínimo do app.
///
/// Toda a composição de infraestrutura (câmeras, Hive, Firestore, MQTT,
/// TTS, etc.) foi movida para os providers em `lib/app/providers/`. O
/// `main` cuida apenas do que **precisa** acontecer antes do Flutter subir:
/// inicializar bindings, configurar o chrome do sistema (modo kiosk) e
/// inicializar o Firebase.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Modo kiosk — esconde barra de navegação e status bar.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);

  runApp(const ProviderScope(child: FaceAccessApp()));
}
