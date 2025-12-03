import 'package:cloud_firestore/cloud_firestore.dart';

enum MessageType { text, image, video, file, audio }

extension MessageTypeExt on MessageType {
  String get nameStr => toString().split('.').last;
  static MessageType from(String v) {
    return MessageType.values.firstWhere(
      (e) => e.name == v || e.toString().split('.').last == v,
      orElse: () => MessageType.text,
    );
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
  final bool edited;
  final bool isDeletedForAll;

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
    this.edited = false,
    this.isDeletedForAll = false,
  });

  factory MessageModel.fromMap(Map<String, dynamic> data, String id) {
    final url = (data['mediaUrl'] as String?) ?? '';
    final text = data['text'] as String?;
    final mediaType = (data['mediaType'] as String?)?.toLowerCase();
    final legacyMessageType = data['messageType'] as String?; // backward compat
    MessageType type;
    if (mediaType != null) {
      switch (mediaType) {
        case 'image':
          type = MessageType.image;
          break;
        case 'video':
          type = MessageType.video;
          break;
        case 'audio':
          type = MessageType.audio;
          break;
        case 'pdf':
        case 'doc':
        case 'ppt':
        case 'zip':
          type = MessageType.file;
          break;
        default:
          type = (text != null && text.isNotEmpty)
              ? MessageType.text
              : MessageType.file;
      }
    } else {
      // legacy path using messageType or infer from url/text
      type = MessageTypeExt.from(legacyMessageType ?? 'text');
      if ((legacyMessageType == null || legacyMessageType == 'text') &&
          (url.isNotEmpty || (text != null && _looksLikeUrl(text)))) {
        final probe = url.isNotEmpty ? url : text!;
        type = _guessTypeFromUrl(probe);
      }
    }
    final effectiveUrl = url.isNotEmpty
        ? url
        : (text != null && _looksLikeUrl(text) ? text : null);
    return MessageModel(
      id: id,
      chatId: data['chatId'] as String,
      senderId: data['senderId'] as String,
      receiverId: data['receiverId'] as String,
      text: (effectiveUrl != null && type != MessageType.text) ? null : text,
      messageType: type,
      mediaUrl: effectiveUrl,
      mediaSize: (data['mediaSize'] as num?)?.toInt(),
      timestamp: data['timestamp'] as Timestamp? ?? Timestamp.now(),
      isSeen: data['isSeen'] as bool? ?? false,
      seenAt: data['seenAt'] as Timestamp?,
      deliveredAt: data['deliveredAt'] as Timestamp?,
      status: (data['status'] as num?)?.toInt() ?? 1,
      edited: data['edited'] as bool? ?? false,
      isDeletedForAll:
          (data['isDeletedForAll'] as bool?) ??
          (data['deletedForEveryone'] as bool?) ??
          false,
    );
  }

  static bool _looksLikeUrl(String t) {
    final s = t.trim().toLowerCase();
    return s.startsWith('http://') || s.startsWith('https://');
  }

  static MessageType _guessTypeFromUrl(String url) {
    final u = url.toLowerCase();
    if (u.endsWith('.png') ||
        u.endsWith('.jpg') ||
        u.endsWith('.jpeg') ||
        u.endsWith('.webp') ||
        u.contains('/image')) {
      return MessageType.image;
    }
    if (u.endsWith('.mp4') ||
        u.endsWith('.webm') ||
        u.endsWith('.mov') ||
        u.contains('/video')) {
      return MessageType.video;
    }
    if (u.endsWith('.mp3') ||
        u.endsWith('.wav') ||
        u.endsWith('.m4a') ||
        u.endsWith('.ogg') ||
        u.contains('/audio')) {
      return MessageType.audio;
    }
    if (u.endsWith('.pdf') ||
        u.endsWith('.doc') ||
        u.endsWith('.docx') ||
        u.endsWith('.ppt') ||
        u.endsWith('.pptx') ||
        u.endsWith('.zip') ||
        u.endsWith('.rar')) {
      return MessageType.file;
    }
    return MessageType.text;
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
