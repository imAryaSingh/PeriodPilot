import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:provider/provider.dart';

import '../features/auth/presentation/auth_gate.dart';
import '../features/notifications/data/firebase_notification_service.dart';
import '../core/network/connectivity_status.dart';
import 'theme.dart';

class TeacherSubstituteApp extends StatelessWidget {
  const TeacherSubstituteApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'PeriodPilot by StackSeed',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    themeMode: ThemeMode.dark,
    scaffoldMessengerKey: FirebaseNotificationService.scaffoldMessengerKey,
    home: const AuthGate(),
    builder: (context, child) => Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF101A2C), Color(0xFF0D1420), Color(0xFF102126)],
              stops: [0, .58, 1],
            ),
          ),
        ),
        const IgnorePointer(child: CustomPaint(painter: _BackdropPainter())),
        Column(
          children: [
            const _OfflineBanner(),
            Expanded(child: child ?? const SizedBox.shrink()),
          ],
        ),
      ],
    ),
  );
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    if (!context.watch<ConnectivityStatus>().isOffline) {
      return const SizedBox.shrink();
    }
    return SafeArea(
      bottom: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: const Color(0xFF79551C),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off_rounded, size: 17),
            SizedBox(width: 8),
            Text('Offline · showing previously synced data'),
          ],
        ),
      ),
    );
  }
}

class _BackdropPainter extends CustomPainter {
  const _BackdropPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xFF70B9EE).withValues(alpha: .055);
    final origin = Offset(size.width * .96, size.height * .12);
    for (var i = 0; i < 7; i++) {
      canvas.drawCircle(origin, 50 + i * 38, paint);
    }
    paint
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF45BBA7).withValues(alpha: .035);
    final path = Path()
      ..moveTo(size.width * .72, size.height)
      ..lineTo(size.width, size.height * .63)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, paint);
    paint.color = const Color(0xFF628DD2).withValues(alpha: .035);
    canvas.drawCircle(
      Offset(size.width * .04, size.height * .78),
      math.min(size.width, size.height) * .16,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _BackdropPainter oldDelegate) => false;
}
