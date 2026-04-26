import 'user_info.dart';
import '../utils/rich_content_utils.dart';

class WebHomeViewData {
  WebHomeViewData({
    required this.user,
    required this.planName,
    required this.balance,
    required this.totalBytes,
    required this.usedBytes,
    required this.uploadBytes,
    required this.downloadBytes,
    required this.expiryAt,
    required this.resetDay,
    required this.notices,
  });

  final UserInfo user;
  final String planName;
  final int balance;
  final int totalBytes;
  final int usedBytes;
  final int uploadBytes;
  final int downloadBytes;
  final int expiryAt;
  final int resetDay;
  final List<WebNoticeViewData> notices;

  bool get hasSubscription => user.planId > 0 && totalBytes > 0;
  double get usagePercent {
    if (totalBytes <= 0) return 0;
    return (usedBytes / totalBytes).clamp(0.0, 1.0);
  }

  WebNoticeViewData? get latestNotice => notices.isEmpty ? null : notices.first;
  WebNoticeViewData? currentNoticeAt(int index) {
    if (notices.isEmpty) {
      return null;
    }
    final safeIndex = index % notices.length;
    return notices[safeIndex];
  }

  factory WebHomeViewData.fromSources({
    required UserInfo user,
    required Map<String, dynamic> subscription,
    required List<Map<String, dynamic>> plans,
    required List<Map<String, dynamic>> notices,
  }) {
    final uploadBytes = _toInt(subscription['u']);
    final downloadBytes = _toInt(subscription['d']);
    final totalBytes = _toInt(subscription['transfer_enable']);
    final normalizedNotices = notices
        .map(WebNoticeViewData.fromMap)
        .where((notice) => notice.title.isNotEmpty || notice.body.isNotEmpty)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final matchedPlan = plans.cast<Map<String, dynamic>?>().firstWhere(
          (plan) => (plan?['id'] ?? 0) == user.planId,
          orElse: () => null,
        );

    return WebHomeViewData(
      user: user,
      planName: matchedPlan?['name']?.toString() ?? '',
      balance: user.balance,
      totalBytes: totalBytes,
      usedBytes: uploadBytes + downloadBytes,
      uploadBytes: uploadBytes,
      downloadBytes: downloadBytes,
      expiryAt: _toInt(subscription['expired_at']),
      resetDay: _toInt(subscription['reset_day']),
      notices: normalizedNotices,
    );
  }

  factory WebHomeViewData.fromAppApi(Map<String, dynamic> data) {
    final account = Map<String, dynamic>.from(
      data['account'] as Map? ?? const {},
    );
    final subscription = Map<String, dynamic>.from(
      data['subscription'] as Map? ?? const {},
    );
    final plans = (data['plans'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final notices = (data['notices'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final planId = _toInt(account['plan_id'] ?? subscription['plan_id']);
    final matchedPlan = plans.cast<Map<String, dynamic>?>().firstWhere(
          (plan) => _toInt(plan?['plan_id']) == planId,
          orElse: () => null,
        );

    return WebHomeViewData(
      user: UserInfo(
        email: account['email']?.toString() ?? '',
        transferEnable: _toInt(account['transfer_bytes']),
        expiredAt: _toInt(account['expiry_at']),
        balance: _toInt(account['balance_amount']),
        planId: planId,
        avatarUrl: account['avatar_url']?.toString(),
        uuid: account['user_ref']?.toString(),
      ),
      planName: matchedPlan?['title']?.toString() ?? '',
      balance: _toInt(account['balance_amount']),
      totalBytes: _toInt(subscription['total_bytes']),
      usedBytes: _toInt(subscription['upload_bytes']) +
          _toInt(subscription['download_bytes']),
      uploadBytes: _toInt(subscription['upload_bytes']),
      downloadBytes: _toInt(subscription['download_bytes']),
      expiryAt: _toInt(subscription['expiry_at']),
      resetDay: _toInt(subscription['reset_days']),
      notices: notices
          .map(WebNoticeViewData.fromAppApi)
          .where((notice) => notice.title.isNotEmpty || notice.body.isNotEmpty)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
    );
  }

  factory WebHomeViewData.fromJson(Map<String, dynamic> json) {
    return WebHomeViewData(
      user: UserInfo.fromJson(
        Map<String, dynamic>.from(json['user'] as Map? ?? const {}),
      ),
      planName: json['plan_name']?.toString() ?? '',
      balance: _toInt(json['balance']),
      totalBytes: _toInt(json['total_bytes']),
      usedBytes: _toInt(json['used_bytes']),
      uploadBytes: _toInt(json['upload_bytes']),
      downloadBytes: _toInt(json['download_bytes']),
      expiryAt: _toInt(json['expiry_at']),
      resetDay: _toInt(json['reset_day']),
      notices: (json['notices'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => WebNoticeViewData.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .where((notice) => notice.title.isNotEmpty || notice.body.isNotEmpty)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'user': user.toJson(),
        'plan_name': planName,
        'balance': balance,
        'total_bytes': totalBytes,
        'used_bytes': usedBytes,
        'upload_bytes': uploadBytes,
        'download_bytes': downloadBytes,
        'expiry_at': expiryAt,
        'reset_day': resetDay,
        'notices': notices.map((notice) => notice.toJson()).toList(),
      };

  static int _toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}

class WebNoticeViewData {
  WebNoticeViewData({
    required this.id,
    required this.title,
    required this.body,
    required this.bodyHtml,
    required this.createdAt,
  });

  final int id;
  final String title;
  final String body;
  final String bodyHtml;
  final int createdAt;

  factory WebNoticeViewData.fromMap(Map<String, dynamic> map) {
    final content = buildRichContentData(map['content']?.toString() ?? '');
    return WebNoticeViewData(
      id: WebHomeViewData._toInt(map['id']),
      title: contentTitle(map['title']?.toString() ?? ''),
      body: content.plainText,
      bodyHtml: content.html,
      createdAt: WebHomeViewData._toInt(map['created_at']),
    );
  }

  factory WebNoticeViewData.fromAppApi(Map<String, dynamic> map) {
    final content = buildRichContentData(map['body']?.toString() ?? '');
    return WebNoticeViewData(
      id: WebHomeViewData._toInt(map['notice_id']),
      title: contentTitle(map['headline']?.toString() ?? ''),
      body: content.plainText,
      bodyHtml: content.html,
      createdAt: WebHomeViewData._toInt(map['created_at']),
    );
  }

  factory WebNoticeViewData.fromJson(Map<String, dynamic> json) {
    return WebNoticeViewData(
      id: WebHomeViewData._toInt(json['id']),
      title: json['title']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      bodyHtml: json['body_html']?.toString() ?? '',
      createdAt: WebHomeViewData._toInt(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'body': body,
        'body_html': bodyHtml,
        'created_at': createdAt,
      };

  static String contentTitle(String value) {
    if (value.isEmpty) return '';

    final decoded = value
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");

    return decoded
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }
}
