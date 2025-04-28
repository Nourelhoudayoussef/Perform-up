class NotificationModel {
  final String id;
  final String title;
  final String message;
  final String senderId;
  final List<String> recipientIds;
  final String type;
  final DateTime createdAt;
  final bool isRead;
  final String? senderProfilePicture;

  NotificationModel({
    required this.id,
    required this.title,
    required this.message,
    required this.senderId,
    required this.recipientIds,
    required this.type,
    required this.createdAt,
    required this.isRead,
    this.senderProfilePicture,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      message: json['message'] ?? '',
      senderId: json['senderId'] ?? '',
      recipientIds: List<String>.from(json['recipientIds'] ?? []),
      type: json['type'] ?? '',
      createdAt: json['createdAt'] != null 
          ? DateTime.parse(json['createdAt'].toString())
          : DateTime.now(),
      isRead: json['isRead'] ?? false,
      senderProfilePicture: json['senderProfilePicture'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'message': message,
      'senderId': senderId,
      'recipientIds': recipientIds,
      'type': type,
      'createdAt': createdAt.toIso8601String(),
      'isRead': isRead,
      'senderProfilePicture': senderProfilePicture,
    };
  }
} 