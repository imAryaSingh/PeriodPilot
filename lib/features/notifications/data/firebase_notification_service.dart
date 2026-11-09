import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../auth/domain/user_profile.dart';

const _webVapidKey = String.fromEnvironment('FCM_VAPID_KEY');

class FirebaseNotificationService {
  FirebaseNotificationService({
    FirebaseMessaging? messaging,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  }) : _messaging = messaging ?? FirebaseMessaging.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance;

  static final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  final FirebaseMessaging _messaging;
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  StreamSubscription<String>? _registrationListener;
  StreamSubscription<String>? _unregistrationListener;
  StreamSubscription<RemoteMessage>? _foregroundListener;
  String? _activeUid;
  String? _activeFid;
  AuthorizationStatus? _authorizationStatus;

  AuthorizationStatus? get authorizationStatus => _authorizationStatus;
  bool get webVapidKeyConfigured => !kIsWeb || _webVapidKey.isNotEmpty;

  Future<AuthorizationStatus> readAuthorizationStatus() async {
    final settings = await _messaging.getNotificationSettings();
    _authorizationStatus = settings.authorizationStatus;
    return settings.authorizationStatus;
  }

  Future<void> initialize(UserProfile profile) async {
    if (profile.schoolId == null || !profile.active) return;
    _activeUid = profile.uid;
    _listenForMessages();
    try {
      final settings = await _messaging.getNotificationSettings();
      _authorizationStatus = settings.authorizationStatus;
      if (_isAuthorized(settings.authorizationStatus) &&
          webVapidKeyConfigured) {
        await _register();
      }
    } on Object {
      // Push registration is optional and must not prevent signing in.
    }
  }

  Future<void> requestAndRegister() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Sign in before enabling notifications.');
    }
    _activeUid = user.uid;
    if (!webVapidKeyConfigured) {
      throw StateError(
        'Web push is not configured. Build with the project VAPID key.',
      );
    }
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    _authorizationStatus = settings.authorizationStatus;
    if (!_isAuthorized(settings.authorizationStatus)) {
      throw StateError('Notification permission was not granted.');
    }
    _listenForMessages();
    await _register();
  }

  Future<void> _register() async {
    final uid = _auth.currentUser?.uid ?? _activeUid;
    if (uid == null) return;
    _activeUid = uid;
    _registrationListener ??= _messaging.onRegistered.listen((fid) {
      final targetUid = _auth.currentUser?.uid ?? _activeUid;
      if (targetUid != null) unawaited(_saveInstallationSafely(targetUid, fid));
    }, onError: (_) {});
    _unregistrationListener ??= _messaging.onUnregistered.listen((fid) {
      final targetUid = _auth.currentUser?.uid ?? _activeUid ?? uid;
      unawaited(_removeInstallationSafely(targetUid, fid));
    }, onError: (_) {});
    await _messaging.register(
      vapidKey: kIsWeb ? _webVapidKey : null,
      serviceWorkerScriptPath: kIsWeb ? 'firebase-messaging-sw.js' : null,
    );
  }

  void _listenForMessages() {
    _foregroundListener ??= FirebaseMessaging.onMessage.listen((message) {
      final title = message.notification?.title ?? 'PeriodPilot by StackSeed';
      final body =
          message.notification?.body ?? 'You have an assignment update.';
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text('$title\n$body'),
          duration: const Duration(seconds: 6),
        ),
      );
    });
  }

  Future<void> _saveInstallation(String uid, String fid) async {
    _activeFid = fid;
    await _firestore
        .collection('users')
        .doc(uid)
        .collection('fcmInstallations')
        .doc(fid)
        .set({
          'fid': fid,
          'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  Future<void> _saveInstallationSafely(String uid, String fid) async {
    try {
      await _saveInstallation(uid, fid);
    } on Object {
      // Keep the app usable if the registration sync is temporarily offline.
    }
  }

  Future<void> _removeInstallation(String uid, String fid) async {
    await _firestore
        .collection('users')
        .doc(uid)
        .collection('fcmInstallations')
        .doc(fid)
        .delete();
    if (_activeFid == fid) _activeFid = null;
  }

  Future<void> _removeInstallationSafely(String uid, String fid) async {
    try {
      await _removeInstallation(uid, fid);
    } on Object {
      // Sign-out proceeds even if a stale registration cannot be removed.
    }
  }

  Future<void> signOut() async {
    final user = _auth.currentUser;
    final uid = user?.uid ?? _activeUid;
    final fid = _activeFid;
    if (uid != null && fid != null) {
      try {
        await _removeInstallation(uid, fid);
        await _messaging.unregister();
      } on Object {
        // Removing a device registration must not prevent account sign-out.
      }
    }
    _activeUid = null;
    _activeFid = null;
  }

  bool _isAuthorized(AuthorizationStatus status) =>
      status == AuthorizationStatus.authorized ||
      status == AuthorizationStatus.provisional;
}

class SchoolNotification {
  const SchoolNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.readAt,
    required this.deliveryStatus,
  });
  final String id;
  final String title;
  final String body;
  final DateTime? createdAt;
  final DateTime? readAt;
  final String deliveryStatus;
  bool get isRead => readAt != null;

  factory SchoolNotification.fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    final created = data['createdAt'];
    final read = data['readAt'];
    return SchoolNotification(
      id: document.id,
      title: data['title'] as String? ?? 'Substitute duty',
      body: data['body'] as String? ?? '',
      createdAt: created is Timestamp ? created.toDate() : null,
      readAt: read is Timestamp ? read.toDate() : null,
      deliveryStatus: data['deliveryStatus'] as String? ?? 'sent',
    );
  }
}

class FirebaseNotificationRepository {
  FirebaseNotificationRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  Stream<List<SchoolNotification>> watchForUser(UserProfile profile) {
    final schoolId = profile.schoolId;
    if (schoolId == null) return Stream.value(const []);
    return _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('notifications')
        .where('recipientUid', isEqualTo: profile.uid)
        .snapshots()
        .map((snapshot) {
          final records = snapshot.docs
              .map(SchoolNotification.fromDocument)
              .toList();
          records.sort(
            (a, b) => (b.createdAt ?? DateTime(0)).compareTo(
              a.createdAt ?? DateTime(0),
            ),
          );
          return records;
        });
  }

  Future<void> markRead(UserProfile profile, String notificationId) async {
    final schoolId = profile.schoolId;
    if (_auth.currentUser?.uid != profile.uid || schoolId == null) {
      throw StateError('Your signed-in profile changed. Reopen notifications.');
    }
    await _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('notifications')
        .doc(notificationId)
        .update({'readAt': FieldValue.serverTimestamp()});
  }
}
