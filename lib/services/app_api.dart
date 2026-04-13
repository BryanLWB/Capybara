import 'dart:convert';

import 'package:http/http.dart' as http;

import '../utils/user_agent_utils.dart';
import 'api_config.dart';

class AppApiException implements Exception {
  AppApiException({
    required this.statusCode,
    required this.message,
    this.body,
  });

  final int statusCode;
  final String message;
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
    return _post(
      '/session/register',
      body: <String, dynamic>{
        'email': email,
        'password': password,
        if (inviteCode?.isNotEmpty == true) 'invite_code': inviteCode,
        if (emailCode?.isNotEmpty == true) 'email_code': emailCode,
        if (recaptchaData?.isNotEmpty == true) 'captcha_payload': recaptchaData,
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

  Future<Map<String, dynamic>> getPlans() {
    return _get('/catalog/plans');
  }

  Future<Map<String, dynamic>> getProfile() {
    return _get('/account/profile');
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

  Future<Map<String, dynamic>> getPaymentMethods() {
    return _get('/commerce/payment-methods');
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

  Future<Map<String, dynamic>> getInviteRecords() {
    return _get('/referrals/records');
  }

  Future<Map<String, dynamic>> createInviteCode() {
    return _post('/referrals/codes', body: const <String, dynamic>{});
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

  AppApiException _errorFromResponse(http.Response response) {
    final body = response.body;
    String message = 'Request failed';
    try {
      final decoded = _decode(body);
      final error = decoded['error'];
      if (error is Map && error['message'] is String) {
        message = error['message'] as String;
      }
    } catch (_) {
      // ignore
    }
    return AppApiException(
      statusCode: response.statusCode,
      message: message,
      body: body.isEmpty ? null : body,
    );
  }
}
