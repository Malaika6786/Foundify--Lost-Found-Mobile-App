// lib/models/message.dart
class ChatMessage {
  final int id;
  final String chatId;
  final String sender;
  final String content;
  final DateTime createdAt;

  ChatMessage({
    required this.id,
    required this.chatId,
    required this.sender,
    required this.content,
    required this.createdAt,
  });

  factory ChatMessage.fromMap(Map<String, dynamic> m) {
    return ChatMessage(
      id: m['id'] as int,
      chatId: m['chat_id'] as String,
      sender: m['sender'] as String,
      content: m['content'] as String,
      createdAt: DateTime.parse(m['created_at'] as String),
    );
  }
}
