import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/user_profile.dart';

class LocalAuthException implements Exception {
  const LocalAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Stores profile/session data and salted password verifiers on this device.
class LocalAuthStore {
  LocalAuthStore({Random? random}) : _random = random ?? Random.secure();

  static const _profilesKey = 'teacher_substitute.local_profiles.v1';
  static const _sessionKey = 'teacher_substitute.local_session.v1';
  static const _credentialsKey = 'teacher_substitute.local_credentials.v1';
  static const _minimumPasswordLength = 10;

  final Random _random;

  final Argon2id _passwordHasher = Argon2id(
    memory: 19 * 1024,
    parallelism: 1,
    iterations: 2,
    hashLength: 32,
  );

  Future<List<UserProfile>> getProfiles() async {
    final preferences = await SharedPreferences.getInstance();
    final encodedProfiles = preferences.getString(_profilesKey);
    if (encodedProfiles == null || encodedProfiles.isEmpty) return [];

    final decoded = jsonDecode(encodedProfiles);
    if (decoded is! List) {
      throw const LocalAuthException(
        'Local profile data is damaged. Clear app storage and set up the device again.',
      );
    }
    try {
      return decoded
          .map((value) => UserProfile.fromJson(value as Map<String, dynamic>))
          .toList(growable: false);
    } on Object {
      throw const LocalAuthException(
        'Local profile data is damaged. Clear app storage and set up the device again.',
      );
    }
  }

  Future<UserProfile?> loadSession() async {
    final preferences = await SharedPreferences.getInstance();
    final uid = preferences.getString(_sessionKey);
    if (uid == null) return null;
    for (final profile in await getProfiles()) {
      if (profile.uid == uid && profile.active) return profile;
    }
    await preferences.remove(_sessionKey);
    return null;
  }

  Future<UserProfile> createFirstAdministrator({
    required String displayName,
    required String email,
    required String password,
  }) async {
    final profiles = await getProfiles();
    if (profiles.isNotEmpty) {
      throw const LocalAuthException(
        'This device is already set up. Sign in with an existing account.',
      );
    }
    final cleanedName = displayName.trim();
    final cleanedEmail = email.trim().toLowerCase();
    if (cleanedName.isEmpty || !_isValidEmail(cleanedEmail)) {
      throw const LocalAuthException('Enter a name and a valid email address.');
    }
    if (password.length < _minimumPasswordLength ||
        !RegExp(r'[A-Za-z]').hasMatch(password) ||
        !RegExp(r'[0-9]').hasMatch(password)) {
      throw const LocalAuthException(
        'Use at least 10 characters with at least one letter and one number.',
      );
    }

    final profile = UserProfile(
      uid: _randomId(),
      email: cleanedEmail,
      displayName: cleanedName,
      role: UserRole.administrator,
    );
    final salt = List<int>.generate(16, (_) => _random.nextInt(256));
    final hash = await _deriveHash(password, salt);

    final preferences = await SharedPreferences.getInstance();
    await _saveCredential(preferences, profile.uid, salt, hash);
    await preferences.setString(_profilesKey, jsonEncode([profile.toJson()]));
    await preferences.setString(_sessionKey, profile.uid);
    return profile;
  }

  Future<UserProfile> signIn({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final profiles = await getProfiles();
    UserProfile? profile;
    for (final candidate in profiles) {
      if (candidate.email == normalizedEmail) {
        profile = candidate;
        break;
      }
    }
    if (profile == null || !profile.active) {
      throw const LocalAuthException('Email or password is incorrect.');
    }

    final preferences = await SharedPreferences.getInstance();
    final credentialsJson = preferences.getString(_credentialsKey);
    if (credentialsJson == null) {
      throw const LocalAuthException(
        'This account credential is missing. Clear app storage and set up the device again.',
      );
    }
    final credentials = jsonDecode(credentialsJson) as Map<String, dynamic>;
    final credential = credentials[profile.uid];
    if (credential is! Map<String, dynamic> ||
        credential['salt'] is! String ||
        credential['hash'] is! String) {
      throw const LocalAuthException(
        'This account credential is missing. Clear app storage and set up the device again.',
      );
    }
    final salt = base64Url.decode(
      base64Url.normalize(credential['salt'] as String),
    );
    final storedHash = base64Url.decode(
      base64Url.normalize(credential['hash'] as String),
    );
    final suppliedHash = await _deriveHash(password, salt);
    if (!_constantTimeEquals(storedHash, suppliedHash)) {
      throw const LocalAuthException('Email or password is incorrect.');
    }

    await preferences.setString(_sessionKey, profile.uid);
    return profile;
  }

  Future<void> signOut() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_sessionKey);
  }

  Future<List<int>> _deriveHash(String password, List<int> salt) async {
    final secretKey = await _passwordHasher.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
    return secretKey.extractBytes();
  }

  Future<void> _saveCredential(
    SharedPreferences preferences,
    String uid,
    List<int> salt,
    List<int> hash,
  ) async {
    final credentials = <String, dynamic>{};
    final existing = preferences.getString(_credentialsKey);
    if (existing != null) {
      credentials.addAll(jsonDecode(existing) as Map<String, dynamic>);
    }
    credentials[uid] = {
      'salt': base64UrlEncode(salt),
      'hash': base64UrlEncode(hash),
    };
    await preferences.setString(_credentialsKey, jsonEncode(credentials));
  }

  String _randomId() => List<int>.generate(
    16,
    (_) => _random.nextInt(256),
  ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  bool _isValidEmail(String email) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);

  bool _constantTimeEquals(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var index = 0; index < left.length; index++) {
      difference |= left[index] ^ right[index];
    }
    return difference == 0;
  }
}
