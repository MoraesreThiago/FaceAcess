import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class AccessTopBar extends StatefulWidget {
  const AccessTopBar({
    super.key,
    required this.tabletName,
    required this.assignmentConfigured,
    this.locationName,
    this.doorName,
  });

  final String tabletName;
  final bool assignmentConfigured;
  final String? locationName;
  final String? doorName;

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
    final weekdays = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sab', 'Dom'];
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
    final assignmentLabel = _buildAssignmentLabel();

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
                                child: _BrandBlock(
                                  tabletName: widget.tabletName,
                                  assignmentLabel: assignmentLabel,
                                  compact: true,
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
                          child: Center(
                            child: _BrandBlock(
                              tabletName: widget.tabletName,
                              assignmentLabel: assignmentLabel,
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

  String _buildAssignmentLabel() {
    if (!widget.assignmentConfigured) {
      return 'Vinculacao pendente';
    }

    final locationName = widget.locationName?.trim();
    final doorName = widget.doorName?.trim();

    if (locationName != null &&
        locationName.isNotEmpty &&
        doorName != null &&
        doorName.isNotEmpty) {
      return '$locationName • $doorName';
    }

    if (doorName != null && doorName.isNotEmpty) {
      return doorName;
    }

    if (locationName != null && locationName.isNotEmpty) {
      return locationName;
    }

    return 'Vinculacao pendente';
  }
}

class _BrandBlock extends StatelessWidget {
  const _BrandBlock({
    required this.tabletName,
    required this.assignmentLabel,
    this.compact = false,
  });

  final String tabletName;
  final String assignmentLabel;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.shield,
              color: Colors.white,
              size: compact ? 16 : 20,
            ),
            SizedBox(width: compact ? 6 : 8),
            Text(
              'FACE ACCESS',
              style: TextStyle(
                color: Colors.white,
                fontSize: compact ? 15 : 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          tabletName.isEmpty ? 'Tablet' : tabletName,
          style: TextStyle(
            color: Colors.white70,
            fontSize: compact ? 11 : 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          assignmentLabel,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white54,
            fontSize: compact ? 10 : 11,
          ),
        ),
      ],
    );
  }
}
