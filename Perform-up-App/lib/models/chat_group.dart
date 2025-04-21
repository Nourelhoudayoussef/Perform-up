class ChatGroup {
  final String id;
  final String name;
  final String creatorId;
  final List<String> memberIds;
  final DateTime createdAt;
  final String? lastMessage;
  final DateTime? lastMessageTime;

  ChatGroup({
    required this.id,
    required this.name,
    required this.creatorId,
    required this.memberIds,
    required this.createdAt,
    this.lastMessage,
    this.lastMessageTime,
  });

  factory ChatGroup.fromJson(Map<String, dynamic> json) {
    return ChatGroup(
      id: json['id'],
      name: json['name'],
      creatorId: json['creatorId'],
      memberIds: List<String>.from(json['memberIds']),
      createdAt: DateTime.parse(json['createdAt']),
      lastMessage: json['lastMessage'],
      lastMessageTime: json['lastMessageTime'] != null 
          ? DateTime.parse(json['lastMessageTime'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'creatorId': creatorId,
      'memberIds': memberIds,
      'createdAt': createdAt.toIso8601String(),
      'lastMessage': lastMessage,
      'lastMessageTime': lastMessageTime?.toIso8601String(),
    };
  }

  ChatGroup copyWith({
    String? id,
    String? name,
    String? creatorId,
    List<String>? memberIds,
    DateTime? createdAt,
    String? lastMessage,
    DateTime? lastMessageTime,
  }) {
    return ChatGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      creatorId: creatorId ?? this.creatorId,
      memberIds: memberIds ?? this.memberIds,
      createdAt: createdAt ?? this.createdAt,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
    );
  }
} 