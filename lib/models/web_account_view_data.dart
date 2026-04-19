class WebAccountProfileData {
  const WebAccountProfileData({
    required this.balanceAmount,
    required this.expireReminder,
    required this.trafficReminder,
    required this.telegramEnabled,
    required this.telegramBound,
    this.telegramDiscussLink,
    this.telegramBindUrl,
    this.telegramBindCommand,
  });

  final int balanceAmount;
  final bool expireReminder;
  final bool trafficReminder;
  final bool telegramEnabled;
  final bool telegramBound;
  final String? telegramDiscussLink;
  final String? telegramBindUrl;
  final String? telegramBindCommand;

  factory WebAccountProfileData.fromResponse(Map<String, dynamic> response) {
    final data = Map<String, dynamic>.from(
      response['data'] as Map? ?? const {},
    );
    final account = Map<String, dynamic>.from(
      data['account'] as Map? ?? const {},
    );
    final config = Map<String, dynamic>.from(
      data['config'] as Map? ?? const {},
    );
    return WebAccountProfileData.fromJson(account, config: config);
  }

  factory WebAccountProfileData.fromJson(
    Map<String, dynamic> json, {
    Map<String, dynamic>? config,
  }) {
    final preferences = Map<String, dynamic>.from(config ?? const {});
    return WebAccountProfileData(
      balanceAmount: _toInt(json['balance_amount']),
      expireReminder: _toBool(json['remind_expire']),
      trafficReminder: _toBool(json['remind_traffic']),
      telegramEnabled: _toBool(preferences['telegram_enabled']),
      telegramBound: _toBool(json['telegram_bound']),
      telegramDiscussLink: _trimmedOrNull(preferences['telegram_discuss_link']),
      telegramBindUrl: _trimmedOrNull(preferences['telegram_bind_url']),
      telegramBindCommand: _trimmedOrNull(preferences['telegram_bind_command']),
    );
  }
}

int _toInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
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

String? _trimmedOrNull(Object? value) {
  final normalized = value?.toString().trim();
  if (normalized == null || normalized.isEmpty) return null;
  return normalized;
}
