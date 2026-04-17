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
