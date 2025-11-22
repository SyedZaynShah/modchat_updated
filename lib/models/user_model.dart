import 'package:cloud_firestore/cloud_firestore.dart';

class ModUser {
  final String userId;
  final String name;
  final String email;
  final String? profilePicUrl;
  final String? about;
  final Timestamp createdAt;

  ModUser({
    required this.userId,
    required this.name,
    required this.email,
    required this.createdAt,
    this.profilePicUrl,
    this.about,
  });

  factory ModUser.fromMap(Map<String, dynamic> data) {
    return ModUser(
      userId: data['userId'] as String,
      name: data['name'] as String? ?? '',
      email: data['email'] as String? ?? '',
      profilePicUrl: data['profilePicUrl'] as String?,
      about: data['about'] as String?,
      createdAt: data['createdAt'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'name': name,
      'email': email,
      'profilePicUrl': profilePicUrl,
      'about': about,
      'createdAt': createdAt,
    };
  }
}
