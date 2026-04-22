import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class AccessTopBar extends StatefulWidget {
  const AccessTopBar({super.key});

  @override
  State<AccessTopBar> createState() => _AccessTopBarState();
}

class _AccessTopBarState extends State<AccessTopBar> {
  late final Timer _clockTimer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (mounted) {
          setState(() => _now = DateTime.now());
        }
      },
    );
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final weekdays = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
    final months = [
      'Jan',
      'Fev',
      'Mar',
      'Abr',
      'Mai',
      'Jun',
      'Jul',
      'Ago',
      'Set',
      'Out',
      'Nov',
      'Dez',
    ];
    final dateStr =
        '${weekdays[_now.weekday - 1]}, ${_now.day} ${months[_now.month - 1]} ${_now.year}';
    final hour = _now.hour.toString().padLeft(2, '0');
    final minute = _now.minute.toString().padLeft(2, '0');
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Transform.translate(
          offset: const Offset(0, -30),
          child: Container(
            padding: EdgeInsets.only(
              left: 0,
              right: isPortrait ? 12 : 20,
              top: isPortrait ? 8 : 10,
              bottom: isPortrait ? 8 : 10,
            ),
            child: isPortrait
                ? Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Transform.translate(
                            offset: const Offset(-8, 0),
                            child: Image.asset(
                              'assets/logo_bembrasil.png',
                              height: 90,
                              fit: BoxFit.contain,
                            ),
                          ),
                          Expanded(
                            child: Center(
                              child: Transform.translate(
                                offset: const Offset(-20, 0),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.shield,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                    SizedBox(width: 6),
                                    Text(
                                      'FACE ACCESS',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                dateStr,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 10,
                                ),
                              ),
                              Text(
                                '$hour:$minute',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w300,
                                  letterSpacing: 2,
                                  fontFeatures: [
                                    ui.FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Transform.translate(
                        offset: const Offset(-8, -21),
                        child: Image.asset(
                          'assets/logo_bembrasil.png',
                          height: 115,
                          fit: BoxFit.contain,
                        ),
                      ),
                      Expanded(
                        child: Transform.translate(
                          offset: const Offset(-29, -25),
                          child: const Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.shield,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'FACE ACCESS',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Transform.translate(
                        offset: const Offset(0, -20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              dateStr,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              '$hour:$minute',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w300,
                                letterSpacing: 2,
                                fontFeatures: [
                                  ui.FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
