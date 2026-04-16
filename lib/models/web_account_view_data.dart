class WebAccountProfileData {
  const WebAccountProfileData({
    required this.balanceAmount,
    required this.expireReminder,
    required this.trafficReminder,
  });

  final int balanceAmount;
  final bool expireReminder;
  final bool trafficReminder;

  factory WebAccountProfileData.fromResponse(Map<String, dynamic> response) {
    final data = Map<String, dynamic>.from(
      response['data'] as Map? ?? const {},
    );
    final account = Map<String, dynamic>.from(
      data['account'] as Map? ?? const {},
    );
    return WebAccountProfileData.fromJson(account);
  }

  factory WebAccountProfileData.fromJson(Map<String, dynamic> json) {
    return WebAccountProfileData(
      balanceAmount: _toInt(json['balance_amount']),
      expireReminder: _toBool(json['remind_expire']),
      trafficReminder: _toBool(json['remind_traffic']),
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
