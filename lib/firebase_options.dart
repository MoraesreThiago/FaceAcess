import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) throw UnsupportedError('Web não suportado.');
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError('Plataforma não suportada.');
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDQ2flUoc1B1ievvlouK0XYza8vyyiqqU0',
    appId: '1:185723702704:android:5ffce4889f7b8a2070da75',
    messagingSenderId: '185723702704',
    projectId: 'faceaccessbb-59e98',
    storageBucket: 'faceaccessbb-59e98.firebasestorage.app',
  );
}
