import 'package:flutter/material.dart';

class AccessBottomBar extends StatelessWidget {
  const AccessBottomBar({
    super.key,
    required this.isAdmin,
    required this.isRecognizing,
    this.onShowPeople,
    this.onRegister,
    this.onConfigureTablet,
    required this.onRecognize,
  });

  final bool isAdmin;
  final bool isRecognizing;
  final Future<void> Function()? onShowPeople;
  final Future<void> Function()? onRegister;
  final Future<void> Function()? onConfigureTablet;
  final Future<void> Function() onRecognize;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 24,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isAdmin) ...[
              ElevatedButton.icon(
                onPressed: onShowPeople == null ? null : () => onShowPeople!(),
                icon: const Icon(Icons.people, size: 18),
                label: const Text('Cadastros'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black54,
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white30),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: onRegister == null ? null : () => onRegister!(),
                icon: const Icon(Icons.person_add, size: 18),
                label: const Text('Cadastrar'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black54,
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white30),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: onConfigureTablet == null
                    ? null
                    : () => onConfigureTablet!(),
                icon: const Icon(Icons.settings_input_component, size: 18),
                label: const Text('Vincular'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black54,
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white30),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                ),
              ),
              const SizedBox(width: 16),
            ],
            GestureDetector(
              onTap: isRecognizing ? null : () => onRecognize(),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: isRecognizing
                      ? Colors.white12
                      : Colors.cyanAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isRecognizing ? Colors.white24 : Colors.cyanAccent,
                    width: 2,
                  ),
                  boxShadow: isRecognizing
                      ? []
                      : [
                          BoxShadow(
                            color: Colors.cyanAccent.withValues(alpha: 0.25),
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ],
                ),
                child: isRecognizing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white54,
                          strokeWidth: 2.5,
                        ),
                      )
                    : const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.face_retouching_natural,
                            color: Colors.cyanAccent,
                            size: 22,
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Reconhecer',
                            style: TextStyle(
                              color: Colors.cyanAccent,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
