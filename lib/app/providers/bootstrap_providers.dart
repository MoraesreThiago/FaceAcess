import 'package:camera/camera.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Lista de câmeras disponíveis no dispositivo.
///
/// Resolvido uma única vez no boot do app. Legacy: antes era chamado
/// diretamente no `main()` e passado por parâmetro até a `AccessScreen`.
final camerasProvider = FutureProvider<List<CameraDescription>>((ref) async {
  return availableCameras();
});
