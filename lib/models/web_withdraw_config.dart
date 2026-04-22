class WebWithdrawConfig {
  const WebWithdrawConfig({
    required this.methods,
    required this.closed,
  });

  final List<String> methods;
  final bool closed;

  factory WebWithdrawConfig.fromResponse(Map<String, dynamic> response) {
    final data = Map<String, dynamic>.from(
      response['data'] as Map? ?? const {},
    );
    final config = Map<String, dynamic>.from(
      data['config'] as Map? ?? const {},
    );
    return WebWithdrawConfig(
      methods: parseWithdrawMethods(config['payout_methods']),
      closed: _toBool(config['payout_closed']),
    );
  }
}

class WebWithdrawalRequest {
  const WebWithdrawalRequest({
    required this.method,
    required this.account,
  });

  final String method;
  final String account;
}

List<String> parseWithdrawMethods(Object? raw) {
  if (raw is List) {
    return raw
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
  if (raw is String) {
    return raw
        .split(RegExp(r'[,，\n]'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
  return const <String>[];
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
