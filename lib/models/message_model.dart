import 'package:cloud_firestore/cloud_firestore.dart';

enum MessageType { text, image, video, file, audio }

extension MessageTypeExt on MessageType {
  String get nameStr => toString().split('.').last;
  static MessageType from(String v) {
    return MessageType.values.firstWhere((e) => e.name == v || e.toString().split('.').last == v,
        orElse: () => MessageType.text);
  }
}

class MessageModel {
  final String id;
  final String chatId;
  final String senderId;
  final String receiverId;
  final String? text;
  final MessageType messageType;
  final String? mediaUrl;
  final int? mediaSize;
  final Timestamp timestamp;
  final bool isSeen;
  final Timestamp? seenAt;
  final Timestamp? deliveredAt;
  final int status; // 1 sent, 2 delivered, 3 seen

  MessageModel({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.receiverId,
    required this.messageType,
    required this.timestamp,
    this.text,
    this.mediaUrl,
    this.mediaSize,
    this.isSeen = false,
    this.seenAt,
    this.deliveredAt,
    this.status = 1,
  });

  factory MessageModel.fromMap(Map<String, dynamic> data, String id) {
    return MessageModel(
      id: id,
      chatId: data['chatId'] as String,
      senderId: data['senderId'] as String,
      receiverId: data['receiverId'] as String,
      text: data['text'] as String?,
      messageType: MessageTypeExt.from(data['messageType'] as String? ?? 'text'),
      mediaUrl: data['mediaUrl'] as String?,
      mediaSize: (data['mediaSize'] as num?)?.toInt(),
      timestamp: data['timestamp'] as Timestamp? ?? Timestamp.now(),
      isSeen: data['isSeen'] as bool? ?? false,
      seenAt: data['seenAt'] as Timestamp?,
      deliveredAt: data['deliveredAt'] as Timestamp?,
      status: (data['status'] as num?)?.toInt() ?? 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'chatId': chatId,
      'senderId': senderId,
      'receiverId': receiverId,
      'text': text,
      'messageType': messageType.nameStr,
      'mediaUrl': mediaUrl,
      'mediaSize': mediaSize,
      'timestamp': timestamp,
      'isSeen': isSeen,
      'seenAt': seenAt,
      'deliveredAt': deliveredAt,
      'status': status,
    };
  }
}
