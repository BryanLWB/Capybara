class WebNodeStatusItemData {
  const WebNodeStatusItemData({
    required this.nodeId,
    required this.displayName,
    required this.protocolType,
    required this.version,
    required this.rate,
    required this.tags,
    required this.isOnline,
    required this.lastCheckAt,
  });

  final int nodeId;
  final String displayName;
  final String protocolType;
  final String version;
  final double rate;
  final List<String> tags;
  final bool isOnline;
  final int lastCheckAt;

  factory WebNodeStatusItemData.fromJson(Map<String, dynamic> json) {
    return WebNodeStatusItemData(
      nodeId: _toInt(json['node_id']),
      displayName: json['display_name']?.toString() ?? '',
      protocolType: json['protocol_type']?.toString() ?? '',
      version: json['version']?.toString() ?? '',
      rate: _toDouble(json['rate']),
      tags: (json['tags'] as List? ?? const [])
          .map((item) => item?.toString() ?? '')
          .where((item) => item.isNotEmpty)
          .toList(),
      isOnline: _toBool(json['is_online']),
      lastCheckAt: _toInt(json['last_check_at']),
    );
  }
}

class WebTicketListItemData {
  const WebTicketListItemData({
    required this.ticketId,
    required this.subject,
    required this.priorityLevel,
    required this.replyState,
    required this.stateCode,
    required this.createdAt,
    required this.updatedAt,
  });

  final int ticketId;
  final String subject;
  final int priorityLevel;
  final int replyState;
  final int stateCode;
  final int createdAt;
  final int updatedAt;

  bool get isClosed => stateCode != 0;

  factory WebTicketListItemData.fromJson(Map<String, dynamic> json) {
    return WebTicketListItemData(
      ticketId: _toInt(json['ticket_id']),
      subject: json['subject']?.toString() ?? '',
      priorityLevel: _toInt(json['priority_level']),
      replyState: _toInt(json['reply_state']),
      stateCode: _toInt(json['state_code']),
      createdAt: _toInt(json['created_at']),
      updatedAt: _toInt(json['updated_at']),
    );
  }
}

class WebTicketDetailData extends WebTicketListItemData {
  const WebTicketDetailData({
    required super.ticketId,
    required super.subject,
    required super.priorityLevel,
    required super.replyState,
    required super.stateCode,
    required super.createdAt,
    required super.updatedAt,
    required this.body,
    required this.messages,
  });

  final String body;
  final List<WebTicketMessageData> messages;

  factory WebTicketDetailData.fromJson(Map<String, dynamic> json) {
    return WebTicketDetailData(
      ticketId: _toInt(json['ticket_id']),
      subject: json['subject']?.toString() ?? '',
      priorityLevel: _toInt(json['priority_level']),
      replyState: _toInt(json['reply_state']),
      stateCode: _toInt(json['state_code']),
      createdAt: _toInt(json['created_at']),
      updatedAt: _toInt(json['updated_at']),
      body: json['body']?.toString() ?? '',
      messages: (json['messages'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => WebTicketMessageData.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .toList(),
    );
  }
}

class WebTicketMessageData {
  const WebTicketMessageData({
    required this.messageId,
    required this.ticketId,
    required this.isMine,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
  });

  final int messageId;
  final int ticketId;
  final bool isMine;
  final String body;
  final int createdAt;
  final int updatedAt;

  factory WebTicketMessageData.fromJson(Map<String, dynamic> json) {
    return WebTicketMessageData(
      messageId: _toInt(json['message_id']),
      ticketId: _toInt(json['ticket_id']),
      isMine: _toBool(json['is_mine']),
      body: json['body']?.toString() ?? '',
      createdAt: _toInt(json['created_at']),
      updatedAt: _toInt(json['updated_at']),
    );
  }
}

class WebTrafficLogItemData {
  const WebTrafficLogItemData({
    required this.uploadedAmount,
    required this.downloadedAmount,
    required this.chargedAmount,
    required this.rateMultiplier,
    required this.recordedAt,
  });

  final int uploadedAmount;
  final int downloadedAmount;
  final int chargedAmount;
  final double rateMultiplier;
  final int recordedAt;

  factory WebTrafficLogItemData.fromJson(Map<String, dynamic> json) {
    return WebTrafficLogItemData(
      uploadedAmount: _toInt(json['uploaded_amount']),
      downloadedAmount: _toInt(json['downloaded_amount']),
      chargedAmount: _toInt(json['charged_amount']),
      rateMultiplier: _toDouble(json['rate_multiplier']),
      recordedAt: _toInt(json['recorded_at']),
    );
  }
}

int _toInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

double _toDouble(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}

bool _toBool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    return normalized == '1' ||
        normalized == 'true' ||
        normalized == 'yes' ||
        normalized == 'on';
  }
  return false;
}
