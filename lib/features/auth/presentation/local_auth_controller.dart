import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../data/firebase_auth_store.dart';
import '../data/local_auth_store.dart';
import '../domain/user_profile.dart';
import '../../notifications/data/firebase_notification_service.dart';

class LocalAuthController extends ChangeNotifier {
  LocalAuthController(
    this._store, {
    this.firebaseStore,
    this.notificationService,
  });

  final LocalAuthStore _store;
  final FirebaseAuthStore? firebaseStore;
  final FirebaseNotificationService? notificationService;

  bool get usesFirebase => Firebase.apps.isNotEmpty && firebaseStore != null;

  bool isInitializing = true;
  bool isBusy = false;
  bool hasAccounts = false;
  String? initializationError;
  UserProfile? profile;

  Future<void> initialize() async {
    isInitializing = true;
    initializationError = null;
    notifyListeners();
    try {
      if (usesFirebase) {
        profile = await firebaseStore!.loadProfile();
        if (profile != null) await notificationService?.initialize(profile!);
        // Firebase Auth cannot enumerate school accounts from the client.
        // Start at sign-in; first-time admins can choose school setup there.
        hasAccounts = true;
      } else {
        final profiles = await _store.getProfiles();
        hasAccounts = profiles.isNotEmpty;
        profile = await _store.loadSession();
      }
    } catch (error) {
      initializationError = error.toString();
    } finally {
      isInitializing = false;
      notifyListeners();
    }
  }

  Future<void> createFirstAdministrator({
    required String displayName,
    required String email,
    required String password,
    String schoolName = '',
  }) async {
    await _run(() async {
      try {
        profile = usesFirebase
            ? await firebaseStore!.createFirstAdministrator(
                displayName: displayName,
                email: email,
                password: password,
                schoolName: schoolName,
              )
            : await _store.createFirstAdministrator(
                displayName: displayName,
                email: email,
                password: password,
              );
      } on FirebaseAuthException catch (error) {
        throw _firebaseError(error);
      }
      hasAccounts = true;
      if (profile != null && usesFirebase) {
        await notificationService?.initialize(profile!);
      }
    });
  }

  Future<void> signIn({required String email, required String password}) async {
    await _run(() async {
      try {
        profile = usesFirebase
            ? await firebaseStore!.signIn(email: email, password: password)
            : await _store.signIn(email: email, password: password);
      } on FirebaseAuthException catch (error) {
        throw _firebaseError(error);
      }
      if (profile != null && usesFirebase) {
        await notificationService?.initialize(profile!);
      }
    });
  }

  Future<void> signOut() async {
    await _run(() async {
      if (usesFirebase) {
        await notificationService?.signOut();
        await firebaseStore!.signOut();
      } else {
        await _store.signOut();
      }
      profile = null;
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    isBusy = true;
    notifyListeners();
    try {
      await action();
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  String _firebaseError(FirebaseAuthException error) => switch (error.code) {
    'invalid-email' => 'Enter a valid email address.',
    'user-disabled' => 'This account has been disabled.',
    'user-not-found' ||
    'wrong-password' ||
    'invalid-credential' => 'Email or password is incorrect.',
    'email-already-in-use' => 'An account already uses this email address.',
    'weak-password' => 'Choose a stronger password.',
    'network-request-failed' =>
      'No internet connection. Try again when online.',
    'operation-not-allowed' =>
      'Email and password sign-in is not enabled in Firebase Authentication.',
    _ => error.message ?? 'Authentication failed. Please try again.',
  };
}
