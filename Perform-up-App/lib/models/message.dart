class Message {
  final String id;
  final String senderId;
  final String receiverId;
  final String chatGroupId;
  final String content;
  final DateTime timestamp;
  final String senderName;

  Message({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.chatGroupId,
    required this.content,
    required this.timestamp,
    required this.senderName,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id']?.toString() ?? '',
      senderId: json['senderId']?.toString() ?? '',
      receiverId: json['receiverId']?.toString() ?? '',
      chatGroupId: json['chatGroupId']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      timestamp: json['timestamp'] != null 
          ? DateTime.parse(json['timestamp'].toString()) 
          : DateTime.now(),
      senderName: json['senderName']?.toString() ?? 'Unknown',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'senderId': senderId,
      'receiverId': receiverId,
      'chatGroupId': chatGroupId,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'senderName': senderName,
    };
  }
} 