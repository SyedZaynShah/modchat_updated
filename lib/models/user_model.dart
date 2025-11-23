import 'package:cloud_firestore/cloud_firestore.dart';

class ModUser {
  final String userId;
  final String name;
  final String email;
  final String? profileImageUrl;
  final String? about;
  final Timestamp createdAt;
  final Timestamp? lastSeen;
  final List<String> blockedUsers;
  final int messageLimitDaily;
  final int messageSentToday;
  final String dmPrivacy;
  final String role;

  ModUser({
    required this.userId,
    required this.name,
    required this.email,
    required this.createdAt,
    this.profileImageUrl,
    this.about,
    this.lastSeen,
    this.blockedUsers = const [],
    this.messageLimitDaily = 0,
    this.messageSentToday = 0,
    this.dmPrivacy = 'everyone',
    this.role = 'user',
  });

  factory ModUser.fromMap(Map<String, dynamic> data) {
    return ModUser(
      userId: data['userId'] as String,
      name: data['name'] as String? ?? '',
      email: data['email'] as String? ?? '',
      profileImageUrl: data['profileImageUrl'] as String?,
      about: data['about'] as String?,
      createdAt: data['createdAt'] as Timestamp? ?? Timestamp.now(),
      lastSeen: data['lastSeen'] as Timestamp?,
      blockedUsers:
          (data['blockedUsers'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      messageLimitDaily: (data['messageLimitDaily'] as num?)?.toInt() ?? 0,
      messageSentToday: (data['messageSentToday'] as num?)?.toInt() ?? 0,
      dmPrivacy: data['dmPrivacy'] as String? ?? 'everyone',
      role: data['role'] as String? ?? 'user',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'name': name,
      'email': email,
      'profileImageUrl': profileImageUrl,
      'about': about,
      'createdAt': createdAt,
      'lastSeen': lastSeen,
      'blockedUsers': blockedUsers,
      'messageLimitDaily': messageLimitDaily,
      'messageSentToday': messageSentToday,
      'dmPrivacy': dmPrivacy,
      'role': role,
    };
  }
}
