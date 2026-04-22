import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/use_cases/evaluate_access_use_case.dart';
import '../domain/entities/operator_role.dart';
import '../domain/entities/tablet_assignment.dart';
import '../domain/entities/tablet_identity.dart';
import '../domain/repositories/person_repository.dart';
import '../infrastructure/access_log_service.dart';
import '../infrastructure/face_recognizer.dart';
import '../infrastructure/firebase_database.dart';
import '../infrastructure/mqtt_door_controller.dart';
import '../infrastructure/tts_service.dart';
import 'access/access_controller.dart';
import 'access/widgets/access_bottom_bar.dart';
import 'access/widgets/access_feedback_overlay.dart';
import 'access/widgets/access_top_bar.dart';
import 'access/widgets/camera_preview_box.dart';
import 'access/widgets/scan_frame_overlay.dart';
import 'people_list_screen.dart';
import 'register_screen.dart';

class AccessScreen extends ConsumerWidget {
  const AccessScreen({
    super.key,
    required this.cameras,
    required this.faceRecognizer,
    required this.evaluateAccess,
    required this.doorController,
    required this.ttsService,
    required this.personRepository,
    required this.firebaseDatabase,
    required this.tabletIdentity,
    required this.tabletAssignment,
    required this.accessLogService,
    required this.profile,
  });

  final List<CameraDescription> cameras;
  final FaceRecognizer faceRecognizer;
  final EvaluateAccessUseCase evaluateAccess;
  final MqttDoorController doorController;
  final TtsService ttsService;
  final PersonRepository personRepository;
  final FirebaseDatabase firebaseDatabase;
  final TabletIdentity tabletIdentity;
  final TabletAssignment? tabletAssignment;
  final AccessLogService accessLogService;
  final OperatorRole profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controllerConfig = AccessControllerConfig(
      cameras: cameras,
      faceRecognizer: faceRecognizer,
      evaluateAccess: evaluateAccess,
      doorController: doorController,
      ttsService: ttsService,
      accessLogService: accessLogService,
    );
    final controller = ref.watch(accessControllerProvider(controllerConfig));
    final state = controller.state;
    final isAdmin = profile == OperatorRole.admin;

    Future<void> openPeopleList() async {
      await controller.pauseCamera();
      if (!context.mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PeopleListScreen(
            personRepository: personRepository,
            firebaseDatabase: firebaseDatabase,
          ),
        ),
      );

      if (!context.mounted) return;
      await controller.resumeCamera(fullReinit: false);
    }

    Future<void> openRegisterScreen() async {
      await controller.pauseCamera();
      if (!context.mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RegisterScreen(
            cameras: cameras,
            faceRecognizer: faceRecognizer,
            personRepository: personRepository,
            firebaseDatabase: firebaseDatabase,
            locationId: tabletAssignment?.locationId,
          ),
        ),
      );

      if (!context.mounted) return;
      await controller.resumeCamera(fullReinit: true);
    }

    Future<void> recognizeNow() async {
      final error = await controller.recognizeNow();
      if (error != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error),
            backgroundColor: Colors.red[800],
            duration: const Duration(seconds: 6),
          ),
        );
      }
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreviewBox(controller: state.cameraController),
          ScanFrameOverlay(active: !state.overlayVisible),
          AccessBottomBar(
            isAdmin: isAdmin,
            isRecognizing: state.isRecognizing,
            onShowPeople: isAdmin ? openPeopleList : null,
            onRegister: isAdmin ? openRegisterScreen : null,
            onRecognize: recognizeNow,
          ),
          if (state.lastDecision != null)
            AccessFeedbackOverlay(
              visible: state.overlayVisible,
              decision: state.lastDecision!,
              greeting: controller.currentGreeting,
            ),
          const AccessTopBar(),
        ],
      ),
    );
  }
}
