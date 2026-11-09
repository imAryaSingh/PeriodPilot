import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../domain/user_profile.dart';

class FirebaseAuthStore {
  FirebaseAuthStore({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  User? get currentUser => _auth.currentUser;

  Future<UserProfile?> loadProfile() async {
    final user = currentUser;
    if (user == null) return null;
    final doc = await _firestore.collection('users').doc(user.uid).get();
    if (!doc.exists) {
      await _auth.signOut();
      throw const FirebaseAuthStoreException(
        'This account is not linked to a school yet. Contact your administrator.',
      );
    }
    final data = doc.data()!;
    if (data['active'] != true) {
      await _auth.signOut();
      throw const FirebaseAuthStoreException('This account is deactivated.');
    }
    return _profileFrom(user.uid, data);
  }

  Future<UserProfile> createFirstAdministrator({
    required String displayName,
    required String email,
    required String password,
    required String schoolName,
  }) async {
    final name = displayName.trim();
    final school = schoolName.trim();
    if (name.isEmpty || school.isEmpty) {
      throw const FirebaseAuthStoreException(
        'Enter your name and school name.',
      );
    }
    if (password.length < 10 ||
        !RegExp(r'[A-Za-z]').hasMatch(password) ||
        !RegExp(r'[0-9]').hasMatch(password)) {
      throw const FirebaseAuthStoreException(
        'Use at least 10 characters with a letter and a number.',
      );
    }

    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );
    final user = credential.user!;
    final schoolRef = _firestore.collection('schools').doc();
    final profile = UserProfile(
      uid: user.uid,
      email: user.email ?? email.trim().toLowerCase(),
      displayName: name,
      role: UserRole.administrator,
      schoolId: schoolRef.id,
    );
    final userRef = _firestore.collection('users').doc(user.uid);
    final batch = _firestore.batch();
    batch.set(schoolRef, {
      'id': schoolRef.id,
      'name': school,
      'address': '',
      'phone': '',
      'ownerUid': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(userRef, {
      ...profile.toJson(),
      'active': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
    try {
      await batch.commit();
    } catch (_) {
      try {
        await user.delete();
      } on Object {
        await _auth.signOut();
      }
      rethrow;
    }
    await user.updateDisplayName(name);
    return profile;
  }

  Future<UserProfile> signIn({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );
    try {
      final profile = await loadProfile();
      if (profile == null) {
        throw const FirebaseAuthStoreException('Sign in failed.');
      }
      return profile;
    } catch (_) {
      if (_auth.currentUser?.uid == credential.user?.uid) await _auth.signOut();
      rethrow;
    }
  }

  Future<void> signOut() => _auth.signOut();

  Future<void> sendPasswordResetEmail(String email) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty ||
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(normalizedEmail)) {
      throw const FirebaseAuthStoreException('Enter a valid email address.');
    }
    await _auth.sendPasswordResetEmail(email: normalizedEmail);
  }

  UserProfile _profileFrom(String uid, Map<String, dynamic> data) =>
      UserProfile(
        uid: uid,
        email: data['email'] as String? ?? currentUser?.email ?? '',
        displayName:
            data['displayName'] as String? ?? currentUser?.displayName ?? '',
        role: UserRole.values.byName(data['role'] as String),
        schoolId: data['schoolId'] as String?,
        active: data['active'] as bool? ?? true,
      );
}

class FirebaseAuthStoreException implements Exception {
  const FirebaseAuthStoreException(this.message);
  final String message;
  @override
  String toString() => message;
}
