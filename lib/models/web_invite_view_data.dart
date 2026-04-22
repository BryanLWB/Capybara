class WebInviteViewData {
  WebInviteViewData({
    required this.codes,
    required this.metrics,
    required this.records,
    this.page = 1,
    this.pageSize = 10,
    this.total = 0,
    this.hasMore = false,
  });

  final List<WebInviteCodeData> codes;
  final WebInviteMetricsData metrics;
  final List<WebInviteRecordData> records;
  final int page;
  final int pageSize;
  final int total;
  final bool hasMore;

  WebInviteCodeData? get primaryCode {
    for (final code in codes) {
      if (code.code.isNotEmpty && code.stateCode == 0) return code;
    }
    for (final code in codes) {
      if (code.code.isNotEmpty) return code;
    }
    return null;
  }

  factory WebInviteViewData.fromResponses(
    Map<String, dynamic> overview,
    Map<String, dynamic> records,
  ) {
    final overviewData =
        Map<String, dynamic>.from(overview['data'] as Map? ?? const {});
    final recordsData =
        Map<String, dynamic>.from(records['data'] as Map? ?? const {});
    final codes = (overviewData['codes'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => WebInviteCodeData.fromMap(
              Map<String, dynamic>.from(item),
            ))
        .toList();
    final recordItems = (recordsData['items'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => WebInviteRecordData.fromMap(
              Map<String, dynamic>.from(item),
            ))
        .toList();

    final page = _toInt(recordsData['page']);
    final pageSize = _toInt(recordsData['page_size']);

    return WebInviteViewData(
      codes: codes,
      metrics: WebInviteMetricsData.fromMap(
        Map<String, dynamic>.from(overviewData['metrics'] as Map? ?? const {}),
      ),
      records: recordItems,
      page: page <= 0 ? 1 : page,
      pageSize: pageSize <= 0 ? 10 : pageSize,
      total: _toInt(recordsData['total']),
      hasMore: _toBool(recordsData['has_more']),
    );
  }
}

class WebInviteMetricsData {
  WebInviteMetricsData({
    required this.registeredUsers,
    required this.settledAmount,
    required this.pendingAmount,
    required this.ratePercent,
    required this.withdrawableAmount,
  });

  final int registeredUsers;
  final int settledAmount;
  final int pendingAmount;
  final int ratePercent;
  final int withdrawableAmount;

  factory WebInviteMetricsData.fromMap(Map<String, dynamic> map) {
    return WebInviteMetricsData(
      registeredUsers: _toInt(map['registered_users']),
      settledAmount: _toInt(map['settled_amount']),
      pendingAmount: _toInt(map['pending_amount']),
      ratePercent: _toInt(map['rate_percent']),
      withdrawableAmount: _toInt(map['withdrawable_amount']),
    );
  }
}

class WebInviteCodeData {
  WebInviteCodeData({
    required this.id,
    required this.code,
    required this.stateCode,
    required this.visitCount,
    required this.createdAt,
  });

  final int id;
  final String code;
  final int stateCode;
  final int visitCount;
  final int createdAt;

  factory WebInviteCodeData.fromMap(Map<String, dynamic> map) {
    return WebInviteCodeData(
      id: _toInt(map['code_id']),
      code: map['invite_code']?.toString() ?? '',
      stateCode: _toInt(map['state_code']),
      visitCount: _toInt(map['visit_count']),
      createdAt: _toInt(map['created_at']),
    );
  }
}

class WebInviteRecordData {
  WebInviteRecordData({
    required this.id,
    required this.amount,
    required this.orderAmount,
    required this.tradeRef,
    required this.createdAt,
    required this.statusText,
  });

  final int id;
  final int amount;
  final int orderAmount;
  final String? tradeRef;
  final int createdAt;
  final String? statusText;

  factory WebInviteRecordData.fromMap(Map<String, dynamic> map) {
    return WebInviteRecordData(
      id: _toInt(map['record_id']),
      amount: _toInt(map['amount']),
      orderAmount: _toInt(map['order_amount']),
      tradeRef: map['trade_ref']?.toString(),
      createdAt: _toInt(map['created_at']),
      statusText: map['status_text']?.toString(),
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
