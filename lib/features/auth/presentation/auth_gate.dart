import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'local_auth_controller.dart';
import 'login_screen.dart';
import 'role_home_screen.dart';
import 'setup_admin_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<LocalAuthController>();
    if (auth.isInitializing) {
      return const _LoadingScreen();
    }
    if (auth.initializationError != null) {
      return _StorageErrorScreen(message: auth.initializationError!);
    }
    if (!auth.hasAccounts) return const SetupAdminScreen();
    final profile = auth.profile;
    if (profile == null) return const LoginScreen();
    return RoleHomeScreen(profile: profile);
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class _StorageErrorScreen extends StatelessWidget {
  const _StorageErrorScreen({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.storage_rounded, size: 48),
              const SizedBox(height: 16),
              const Text(
                'Could not load your account.',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              const Text(
                'Check your connection and account setup, then try again.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
