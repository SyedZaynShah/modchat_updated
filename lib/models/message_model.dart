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
  final String kind; // user | system
  final String? text;
  final MessageType messageType;
  final String? mediaUrl;
  final String? storagePath;
  final String? localPath;
  final String? thumbnailUrl;
  final int? mediaSize;
  final String uploadStatus; // done | uploading | failed
  final bool forwarded;
  final String? originalSenderId;
  final String? originalMessageId;
  final String? replyToMessageId;
  final String? replyToSenderId;
  final String? replyToText;
  final String? replyToMessageType;
  final int? threadReplyCount;
  final Map<String, String>? userReactions;
  final Map<String, int>? reactions;
  final Timestamp timestamp;
  final bool isSeen;
  final Timestamp? seenAt;
  final Timestamp? deliveredAt;
  final int status; // 1 sent, 2 delivered, 3 seen
  final bool edited;
  final bool isDeletedForAll;
  final bool hasPendingWrites;
  final Map<String, dynamic>? meta;

  MessageModel({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.receiverId,
    this.kind = 'user',
    required this.messageType,
    required this.timestamp,
    this.text,
    this.mediaUrl,
    this.storagePath,
    this.localPath,
    this.thumbnailUrl,
    this.mediaSize,
    this.uploadStatus = 'done',
    this.forwarded = false,
    this.originalSenderId,
    this.originalMessageId,
    this.replyToMessageId,
    this.replyToSenderId,
    this.replyToText,
    this.replyToMessageType,
    this.threadReplyCount,
    this.userReactions,
    this.reactions,
    this.isSeen = false,
    this.seenAt,
    this.deliveredAt,
    this.status = 1,
    this.edited = false,
    this.isDeletedForAll = false,
    this.hasPendingWrites = false,
    this.meta,
  });

  factory MessageModel.fromMap(Map<String, dynamic> data, String id) {
    final url = (data['mediaUrl'] as String?) ?? '';
    final storagePath = data['storagePath'] as String?;
    final localPath = data['localPath'] as String?;
    final thumbnailUrl = data['thumbnailUrl'] as String?;
    final text = data['text'] as String?;
    final mediaType = (data['mediaType'] as String?)?.toLowerCase();
    final legacyMessageType = data['messageType'] as String?; // backward compat
    final uploadStatus = (data['uploadStatus'] as String?) ?? 'done';
    final kind = ((data['type'] as String?) ?? 'user').toLowerCase();
    final meta = (data['meta'] as Map?)?.cast<String, dynamic>();
    final replyTo = (data['replyTo'] as Map?)?.cast<String, dynamic>();
    final userReactionsRaw =
      (data['userReactions'] as Map?)?.cast<String, dynamic>();
    final reactionsRaw = (data['reactions'] as Map?)?.cast<String, dynamic>();
    final forwarded = (data['forwarded'] as bool?) ?? false;
    final originalSenderId = data['originalSender'] as String?;
    final originalMessageId = data['originalMessageId'] as String?;
    MessageType type;
    if (kind == 'system') {
      type = MessageType.text;
    } else if (mediaType != null) {
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
      kind: kind,
      text: (effectiveUrl != null && type != MessageType.text) ? null : text,
      messageType: type,
      mediaUrl: effectiveUrl,
      storagePath: storagePath,
      localPath: localPath,
      thumbnailUrl: thumbnailUrl,
      mediaSize: (data['mediaSize'] as num?)?.toInt(),
      uploadStatus: uploadStatus,
      forwarded: forwarded,
      originalSenderId: originalSenderId,
      originalMessageId: originalMessageId,
      replyToMessageId: replyTo?['messageId'] as String?,
      replyToSenderId: replyTo?['senderId'] as String?,
      replyToText: replyTo?['text'] as String?,
      replyToMessageType: replyTo?['messageType'] as String?,
      threadReplyCount: (data['threadReplyCount'] as num?)?.toInt(),
        userReactions: _userReactionsFromRaw(userReactionsRaw),
        reactions:
          _reactionCountsFromUserReactions(userReactionsRaw) ??
          _reactionCountsFromRaw(reactionsRaw),
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
      hasPendingWrites: false,
      meta: meta,
    );
  }

  factory MessageModel.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final url = (data['mediaUrl'] as String?) ?? '';
    final storagePath = data['storagePath'] as String?;
    final localPath = data['localPath'] as String?;
    final thumbnailUrl = data['thumbnailUrl'] as String?;
    final text = data['text'] as String?;
    final mediaType = (data['mediaType'] as String?)?.toLowerCase();
    final legacyMessageType = data['messageType'] as String?;
    final uploadStatus = (data['uploadStatus'] as String?) ?? 'done';
    final kind = ((data['type'] as String?) ?? 'user').toLowerCase();
    final meta = (data['meta'] as Map?)?.cast<String, dynamic>();
    final replyTo = (data['replyTo'] as Map?)?.cast<String, dynamic>();
    final userReactionsRaw =
      (data['userReactions'] as Map?)?.cast<String, dynamic>();
    final reactionsRaw = (data['reactions'] as Map?)?.cast<String, dynamic>();
    final forwarded = (data['forwarded'] as bool?) ?? false;
    final originalSenderId = data['originalSender'] as String?;
    final originalMessageId = data['originalMessageId'] as String?;
    MessageType type;
    if (kind == 'system') {
      type = MessageType.text;
    } else if (mediaType != null) {
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
      id: doc.id,
      chatId: data['chatId'] as String,
      senderId: data['senderId'] as String,
      receiverId: data['receiverId'] as String,
      kind: kind,
      text: (effectiveUrl != null && type != MessageType.text) ? null : text,
      messageType: type,
      mediaUrl: effectiveUrl,
      storagePath: storagePath,
      localPath: localPath,
      thumbnailUrl: thumbnailUrl,
      mediaSize: (data['mediaSize'] as num?)?.toInt(),
      uploadStatus: uploadStatus,
      forwarded: forwarded,
      originalSenderId: originalSenderId,
      originalMessageId: originalMessageId,
      replyToMessageId: replyTo?['messageId'] as String?,
      replyToSenderId: replyTo?['senderId'] as String?,
      replyToText: replyTo?['text'] as String?,
      replyToMessageType: replyTo?['messageType'] as String?,
      threadReplyCount: (data['threadReplyCount'] as num?)?.toInt(),
        userReactions: _userReactionsFromRaw(userReactionsRaw),
        reactions:
          _reactionCountsFromUserReactions(userReactionsRaw) ??
          _reactionCountsFromRaw(reactionsRaw),
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
      hasPendingWrites: doc.metadata.hasPendingWrites,
      meta: meta,
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

  static Map<String, int>? _reactionCountsFromRaw(
    Map<String, dynamic>? reactionsRaw,
  ) {
    if (reactionsRaw == null) return null;
    if (reactionsRaw.isEmpty) return <String, int>{};
    final out = <String, int>{};
    reactionsRaw.forEach((k, v) {
      if (v is num) {
        out[k] = v.toInt();
      } else if (v is List) {
        out[k] = v.length;
      } else {
        out[k] = 0;
      }
    });
    return out;
  }

  static Map<String, String>? _userReactionsFromRaw(
    Map<String, dynamic>? raw,
  ) {
    if (raw == null) return null;
    if (raw.isEmpty) return <String, String>{};
    final out = <String, String>{};
    raw.forEach((k, v) {
      final uid = k.trim();
      final emoji = v.toString().trim();
      if (uid.isEmpty || emoji.isEmpty) return;
      out[uid] = emoji;
    });
    return out;
  }

  static Map<String, int>? _reactionCountsFromUserReactions(
    Map<String, dynamic>? raw,
  ) {
    final userMap = _userReactionsFromRaw(raw);
    if (userMap == null) return null;
    final out = <String, int>{};
    for (final emoji in userMap.values) {
      out[emoji] = (out[emoji] ?? 0) + 1;
    }
    return out;
  }

  Map<String, dynamic> toMap() {
    return {
      'chatId': chatId,
      'senderId': senderId,
      'receiverId': receiverId,
      'type': kind,
      'text': text,
      'messageType': messageType.nameStr,
      'mediaUrl': mediaUrl,
      'storagePath': storagePath,
      'localPath': localPath,
      'thumbnailUrl': thumbnailUrl,
      'mediaSize': mediaSize,
      if (meta != null) 'meta': meta,
      'timestamp': timestamp,
      'isSeen': isSeen,
      'seenAt': seenAt,
      'deliveredAt': deliveredAt,
      'status': status,
    };
  }
}
