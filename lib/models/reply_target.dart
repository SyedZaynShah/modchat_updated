class ReplyTarget {
  final String messageId;
  final String senderId;
  final String previewText;
  final String messageType; // text | image | video | file | audio
  final String? senderName;

  const ReplyTarget({
    required this.messageId,
    required this.senderId,
    required this.previewText,
    required this.messageType,
    this.senderName,
  });

  Map<String, dynamic> toMap() {
    return {
      'messageId': messageId,
      'senderId': senderId,
      'text': previewText,
      'messageType': messageType,
    };
  }
}
