class WebClientImportOptionData {
  const WebClientImportOptionData({
    required this.clientKey,
    required this.displayName,
    required this.supported,
    required this.actionType,
    required this.actionValue,
    this.iconUrl,
    this.protocolHint,
  });

  final String clientKey;
  final String displayName;
  final bool supported;
  final String actionType;
  final String actionValue;
  final String? iconUrl;
  final String? protocolHint;

  bool get isDeepLink => actionType == 'deep_link';
  bool get isCopyLink => actionType == 'copy_link';

  factory WebClientImportOptionData.fromJson(Map<String, dynamic> json) {
    return WebClientImportOptionData(
      clientKey: json['client_key']?.toString() ?? '',
      displayName: json['display_name']?.toString() ?? '',
      supported: _toBool(json['supported']),
      actionType: json['action_type']?.toString() ?? '',
      actionValue: json['action_value']?.toString() ?? '',
      iconUrl: _trimmedOrNull(json['icon_url']),
      protocolHint: _trimmedOrNull(json['protocol_hint']),
    );
  }
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

String? _trimmedOrNull(Object? value) {
  final normalized = value?.toString().trim();
  if (normalized == null || normalized.isEmpty) return null;
  return normalized;
}
