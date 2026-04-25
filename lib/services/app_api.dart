import 'dart:convert';

import 'package:http/http.dart' as http;

import '../utils/user_agent_utils.dart';
import 'api_config.dart';

class AppApiException implements Exception {
  AppApiException({
    required this.statusCode,
    required this.message,
    this.code,
    this.body,
  });

  final int statusCode;
  final String message;
  final String? code;
  final String? body;

  @override
  String toString() => message;
}

class AppApi {
  AppApi({ApiConfig? config, http.Client? client})
      : _config = config ?? ApiConfig(),
        _client = client ?? http.Client();

  final ApiConfig _config;
  final http.Client _client;

  Future<Map<String, dynamic>> login(String email, String password) {
    return _post(
      '/session/login',
      body: <String, dynamic>{'email': email, 'password': password},
      withSession: false,
    );
  }

  Future<Map<String, dynamic>> register(
    String email,
    String password, {
    String? inviteCode,
    String? emailCode,
    String? recaptchaData,
  }) {
    final trimmedInviteCode = _trimmedOrNull(inviteCode);
    final trimmedEmailCode = _trimmedOrNull(emailCode);
    final trimmedRecaptchaData = _trimmedOrNull(recaptchaData);
    return _post(
      '/session/register',
      body: <String, dynamic>{
        'email': email,
        'password': password,
        if (trimmedInviteCode != null) 'invite_code': trimmedInviteCode,
        if (trimmedEmailCode != null) 'email_code': trimmedEmailCode,
        if (trimmedRecaptchaData != null)
          'captcha_payload': trimmedRecaptchaData,
      },
      withSession: false,
    );
  }

  Future<Map<String, dynamic>> sendEmailCode(
    String email, {
    String? recaptchaData,
  }) {
    return _post(
      '/session/email-code',
      body: <String, dynamic>{
        'email': email,
        if (recaptchaData?.isNotEmpty == true) 'captcha_payload': recaptchaData,
      },
      withSession: false,
    );
  }

  Future<Map<String, dynamic>> resetPassword(
    String email,
    String emailCode,
    String password,
  ) {
    return _post(
      '/session/password/reset',
      body: <String, dynamic>{
        'email': email,
        'email_code': emailCode,
        'password': password,
      },
      withSession: false,
    );
  }

  Future<Map<String, dynamic>> getGuestConfig() {
    return _get('/public/config', withSession: false);
  }

  Future<Map<String, dynamic>> getUserConfig() {
    return _get('/account/preferences');
  }

  Future<Map<String, dynamic>> updateNotifications({
    required bool expiry,
    required bool traffic,
  }) {
    return _patch(
      '/account/notifications',
      body: <String, dynamic>{
        'expiry': expiry,
        'traffic': traffic,
      },
    );
  }

  Future<Map<String, dynamic>> changePassword({
    required String oldPassword,
    required String newPassword,
  }) {
    return _post(
      '/account/password/change',
      body: <String, dynamic>{
        'old_password': oldPassword,
        'new_password': newPassword,
      },
    );
  }

  Future<Map<String, dynamic>> getPlans() {
    return _get('/catalog/plans');
  }

  Future<Map<String, dynamic>> getProfile() {
    return _get('/account/profile');
  }

  Future<Map<String, dynamic>> getAccountBootstrap() {
    return _get('/account/bootstrap');
  }

  Future<Map<String, dynamic>> getSubscriptionSummary() {
    return _get('/account/subscription');
  }

  Future<String> getSubscriptionContent({String? flag}) async {
    final response = await _getRaw(
      '/account/subscription/content',
      query: <String, String>{if (flag?.isNotEmpty == true) 'flag': flag!},
    );
    if (response.statusCode >= 400) {
      throw _errorFromResponse(response);
    }
    return response.body;
  }

  Future<Map<String, dynamic>> createSubscriptionAccessLink({String? flag}) {
    return _post(
      '/account/subscription/access-link',
      body: <String, dynamic>{
        if (flag?.trim().isNotEmpty == true) 'flag': flag!.trim(),
      },
    );
  }

  Future<Map<String, dynamic>> resetSubscriptionSecurity() {
    return _post(
      '/account/subscription/reset',
      body: const <String, dynamic>{},
    );
  }

  Future<Map<String, dynamic>> getTrafficLogs() {
    return _get('/account/traffic-logs');
  }

  Future<Map<String, dynamic>> getNotices() {
    return _get('/content/notices');
  }

  Future<Map<String, dynamic>> getHelpArticles({required String language}) {
    return _get(
      '/content/help/articles',
      query: <String, String>{'language': language},
    );
  }

  Future<Map<String, dynamic>> getHelpArticle(
    int articleId, {
    required String language,
  }) {
    return _get(
      '/content/help/articles/$articleId',
      query: <String, String>{'language': language},
    );
  }

  Future<Map<String, dynamic>> getNodeStatuses() {
    return _get('/client/nodes/status');
  }

  Future<Map<String, dynamic>> getPaymentMethods() {
    return _get('/commerce/payment-methods');
  }

  Future<Map<String, dynamic>> validateCoupon(
    int planId,
    String periodKey,
    String couponCode,
  ) {
    return _post(
      '/commerce/coupons/validate',
      body: <String, dynamic>{
        'plan_id': planId,
        'period_key': periodKey,
        'coupon_code': couponCode.trim(),
      },
    );
  }

  Future<Map<String, dynamic>> createOrder(
    int planId,
    String periodKey, {
    String? couponCode,
  }) {
    return _post(
      '/commerce/orders',
      body: <String, dynamic>{
        'plan_id': planId,
        'period_key': periodKey,
        if (couponCode?.isNotEmpty == true) 'coupon_code': couponCode,
      },
    );
  }

  Future<Map<String, dynamic>> getOrderDetail(String tradeNo) {
    return _get('/commerce/orders/$tradeNo');
  }

  Future<Map<String, dynamic>> checkoutOrder(
    String tradeNo,
    int methodId,
  ) {
    return _post(
      '/commerce/orders/$tradeNo/checkout',
      body: <String, dynamic>{'payment_method_id': methodId},
    );
  }

  Future<Map<String, dynamic>> getOrderStatus(String tradeNo) {
    return _get('/commerce/orders/$tradeNo/status');
  }

  Future<Map<String, dynamic>> cancelOrder(String tradeNo) {
    return _post('/commerce/orders/$tradeNo/cancel',
        body: const <String, dynamic>{});
  }

  Future<Map<String, dynamic>> getOrders() {
    return _get('/commerce/orders');
  }

  Future<Map<String, dynamic>> getInviteOverview() {
    return _get('/referrals/overview');
  }

  Future<Map<String, dynamic>> getInviteRecords({
    int page = 1,
    int pageSize = 10,
  }) {
    return _get(
      '/referrals/records',
      query: <String, String>{
        'page': '$page',
        'page_size': '$pageSize',
      },
    );
  }

  Future<Map<String, dynamic>> createInviteCode() {
    return _post('/referrals/codes', body: const <String, dynamic>{});
  }

  Future<Map<String, dynamic>> transferReferralBalance(int amountCents) {
    return _post(
      '/referrals/transfer-to-balance',
      body: <String, dynamic>{'amount_cents': amountCents},
    );
  }

  Future<Map<String, dynamic>> requestReferralWithdrawal({
    required String method,
    required String account,
  }) {
    return _post(
      '/referrals/withdrawals',
      body: <String, dynamic>{
        'withdraw_method': method.trim(),
        'withdraw_account': account.trim(),
      },
    );
  }

  Future<Map<String, dynamic>> getTickets() {
    return _get('/support/tickets');
  }

  Future<Map<String, dynamic>> getTicketDetail(int ticketId) {
    return _get('/support/tickets/$ticketId');
  }

  Future<Map<String, dynamic>> createTicket({
    required String subject,
    required int priorityLevel,
    required String message,
  }) {
    return _post(
      '/support/tickets',
      body: <String, dynamic>{
        'subject': subject.trim(),
        'priority_level': priorityLevel,
        'message': message.trim(),
      },
    );
  }

  Future<Map<String, dynamic>> replyTicket({
    required int ticketId,
    required String message,
  }) {
    return _post(
      '/support/tickets/$ticketId/reply',
      body: <String, dynamic>{'message': message.trim()},
    );
  }

  Future<Map<String, dynamic>> closeTicket(int ticketId) {
    return _post(
      '/support/tickets/$ticketId/close',
      body: const <String, dynamic>{},
    );
  }

  Future<Map<String, dynamic>> redeemGiftCode(String code) {
    return _post(
      '/rewards/redeem',
      body: <String, dynamic>{'code': code},
    );
  }

  Future<Map<String, dynamic>> getClientConfig() {
    return _get('/client/config');
  }

  Future<Map<String, dynamic>> getClientVersion() {
    return _get('/client/version');
  }

  Future<Map<String, dynamic>> getClientDownloads() {
    return _get('/client/downloads');
  }

  Future<Map<String, dynamic>> getClientImportOptions(String platform) {
    return _get(
      '/client/import-options',
      query: <String, String>{'platform': platform},
    );
  }

  Future<Map<String, dynamic>> getWebBootstrap() {
    return _get('/web/bootstrap');
  }

  Future<void> logout() async {
    final response = await _delete('/session/current');
    if (response.statusCode >= 400) {
      throw _errorFromResponse(response);
    }
  }

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, String>? query,
    bool withSession = true,
  }) async {
    final response = await _getRaw(
      path,
      query: query,
      withSession: withSession,
    );
    if (response.statusCode >= 400) {
      throw _errorFromResponse(response);
    }
    return _decode(response.body);
  }

  Future<http.Response> _getRaw(
    String path, {
    Map<String, String>? query,
    bool withSession = true,
  }) async {
    final uri = await _buildUri(path, query);
    return _client.get(uri, headers: await _headers(withSession: withSession));
  }

  Future<Map<String, dynamic>> _post(
    String path, {
    required Map<String, dynamic> body,
    bool withSession = true,
  }) async {
    final uri = await _buildUri(path, null);
    final response = await _client.post(
      uri,
      headers: await _headers(withSession: withSession, isJson: true),
      body: jsonEncode(body),
    );
    if (response.statusCode >= 400) {
      throw _errorFromResponse(response);
    }
    return _decode(response.body);
  }

  Future<Map<String, dynamic>> _patch(
    String path, {
    required Map<String, dynamic> body,
    bool withSession = true,
  }) async {
    final uri = await _buildUri(path, null);
    final response = await _client.patch(
      uri,
      headers: await _headers(withSession: withSession, isJson: true),
      body: jsonEncode(body),
    );
    if (response.statusCode >= 400) {
      throw _errorFromResponse(response);
    }
    return _decode(response.body);
  }

  Future<http.Response> _delete(String path) async {
    final uri = await _buildUri(path, null);
    return _client.delete(uri, headers: await _headers(withSession: true));
  }

  Future<Map<String, String>> _headers({
    required bool withSession,
    bool isJson = false,
  }) async {
    final headers = <String, String>{
      'Accept': 'application/json, text/plain, */*',
    };
    final userAgent = UserAgentUtils.userAgent;
    if (userAgent.isNotEmpty) {
      headers['User-Agent'] = userAgent;
    }
    if (isJson) {
      headers['Content-Type'] = 'application/json';
    }
    if (!withSession) {
      return headers;
    }
    final session = await _config.getSessionToken();
    if (session?.isNotEmpty == true) {
      headers['Authorization'] = 'Bearer $session';
    }
    return headers;
  }

  Future<Uri> _buildUri(String path, Map<String, String>? query) async {
    final base = await _config.getBaseUrl();
    final normalized =
        base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return Uri.parse('$normalized$path').replace(queryParameters: query);
  }

  Map<String, dynamic> _decode(String body) {
    if (body.trim().isEmpty) {
      return <String, dynamic>{};
    }
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return <String, dynamic>{'data': decoded};
  }

  String? _trimmedOrNull(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  AppApiException _errorFromResponse(http.Response response) {
    final body = response.body;
    String message = 'Request failed';
    String? code;
    try {
      final decoded = _decode(body);
      final error = decoded['error'];
      if (error is Map) {
        if (error['message'] is String) {
          message = error['message'] as String;
        }
        final rawCode = error['code']?.toString().trim();
        if (rawCode != null && rawCode.isNotEmpty) {
          code = rawCode;
        }
      }
    } catch (_) {
      // ignore
    }
    return AppApiException(
      statusCode: response.statusCode,
      message: message,
      code: code,
      body: body.isEmpty ? null : body,
    );
  }
}
