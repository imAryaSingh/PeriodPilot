enum UserRole { administrator, teacher, principal }

extension UserRoleLabel on UserRole {
  String get label => switch (this) {
    UserRole.administrator => 'Administrator',
    UserRole.teacher => 'Teacher',
    UserRole.principal => 'Principal / Head of Department',
  };
}

class UserProfile {
  const UserProfile({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.role,
    this.schoolId,
    this.active = true,
  });

  final String uid;
  final String email;
  final String displayName;
  final UserRole role;
  final String? schoolId;
  final bool active;

  Map<String, Object?> toJson() => {
    'uid': uid,
    'email': email,
    'displayName': displayName,
    'role': role.name,
    'schoolId': schoolId,
    'active': active,
  };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    uid: json['uid'] as String,
    email: json['email'] as String,
    displayName: json['displayName'] as String,
    role: UserRole.values.byName(json['role'] as String),
    schoolId: json['schoolId'] as String?,
    active: json['active'] as bool? ?? true,
  );
}
