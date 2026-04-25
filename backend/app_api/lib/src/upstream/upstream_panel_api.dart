import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import 'upstream_api.dart';

class UpstreamPanelApi implements UpstreamApi {
  UpstreamPanelApi({
    required Uri baseUri,
    Duration? timeout,
    http.Client? client,
    Logger? logger,
  })  : _baseUri = _normalizeBaseUri(baseUri),
        _timeout = timeout ?? const Duration(seconds: 20),
        _client = client ?? http.Client(),
        _logger = logger ?? Logger('UpstreamPanelApi');

  final Uri _baseUri;
  final Duration _timeout;
  final http.Client _client;
  final Logger _logger;

  static Uri _normalizeBaseUri(Uri uri) {
    var normalized = uri;
    if (normalized.path.endsWith('/')) {
      normalized = normalized.replace(
        path: normalized.path.substring(0, normalized.path.length - 1),
      );
    }
    return normalized;
  }

  @override
  Future<UpstreamAuth> login({
    required String email,
    required String password,
  }) async {
    final response = await _post(
      '/api/v1/passport/auth/login',
      body: {
        'email': email,
        'password': password,
      },
    );
    return _authFromResponse(response);
  }

  @override
  Future<UpstreamAuth> register({
    required String email,
    required String password,
    String? inviteCode,
    String? emailCode,
    String? recaptchaData,
  }) async {
    final normalizedInviteCode = _trimmedOrNull(inviteCode);
    final normalizedEmailCode = _trimmedOrNull(emailCode);
    final normalizedRecaptchaData = _trimmedOrNull(recaptchaData);
    final response = await _post(
      '/api/v1/passport/auth/register',
      body: {
        'email': email,
        'password': password,
        if (normalizedInviteCode != null) 'invite_code': normalizedInviteCode,
        if (normalizedEmailCode != null) 'email_code': normalizedEmailCode,
        if (normalizedRecaptchaData != null)
          'recaptcha_data': normalizedRecaptchaData,
      },
    );
    return _authFromResponse(response);
  }

  @override
  Future<void> resetPassword({
    required String email,
    required String emailCode,
    required String password,
  }) async {
    await _post(
      '/api/v1/passport/auth/forget',
      body: {
        'email': email,
        'email_code': emailCode,
        'password': password,
      },
    );
  }

  @override
  Future<void> sendEmailCode({
    required String email,
    String? recaptchaData,
  }) async {
    await _post(
      '/api/v1/passport/comm/sendEmailVerify',
      body: {
        'email': email,
        if (recaptchaData?.isNotEmpty == true) 'recaptcha_data': recaptchaData,
      },
    );
  }

  @override
  Future<Map<String, dynamic>> fetchGuestConfig() {
    return _get('/api/v1/guest/comm/config');
  }

  @override
  Future<List<Map<String, dynamic>>> fetchGuestPlans() async {
    final response = await _get('/api/v1/guest/plan/fetch');
    final data = response['data'];
    if (data is List) {
      return data.map((item) => Map<String, dynamic>.from(item)).toList();
    }
    return <Map<String, dynamic>>[];
  }

  @override
  Future<Map<String, dynamic>> fetchUserConfig(UpstreamAuth auth) {
    return _get('/api/v1/user/comm/config', auth: auth);
  }

  @override
  Future<void> updateUserNotifications(
    UpstreamAuth auth, {
    required bool remindExpire,
    required bool remindTraffic,
  }) async {
    await _post(
      '/api/v1/user/update',
      auth: auth,
      body: {
        'remind_expire': remindExpire ? 1 : 0,
        'remind_traffic': remindTraffic ? 1 : 0,
      },
    );
  }

  @override
  Future<void> changePassword(
    UpstreamAuth auth, {
    required String oldPassword,
    required String newPassword,
  }) async {
    await _post(
      '/api/v1/user/changePassword',
      auth: auth,
      body: {
        'old_password': oldPassword,
        'new_password': newPassword,
      },
    );
  }

  @override
  Future<List<Map<String, dynamic>>> fetchPlans(UpstreamAuth auth) async {
    final response = await _get('/api/v1/user/plan/fetch', auth: auth);
    final data = response['data'];
    if (data is List) {
      return data.map((item) => Map<String, dynamic>.from(item)).toList();
    }
    return <Map<String, dynamic>>[];
  }

  @override
  Future<Map<String, dynamic>> fetchUserProfile(UpstreamAuth auth) {
    return _get('/api/v1/user/info', auth: auth);
  }

  @override
  Future<Map<String, dynamic>> fetchSubscriptionSummary(UpstreamAuth auth) {
    return _get('/api/v1/user/getSubscribe', auth: auth);
  }

  @override
  Future<String> fetchSubscriptionContent(UpstreamAuth auth,
      {String? flag}) async {
    final summary = await fetchSubscriptionSummary(auth);
    final data = summary['data'];
    if (data is! Map || data['subscribe_url'] == null) {
      throw UpstreamException(
        statusCode: 502,
        message: 'subscription unavailable',
        body: jsonEncode(summary),
      );
    }
    final subscribeUrl = Uri.parse(data['subscribe_url'].toString());
    var target = subscribeUrl;
    if (flag != null && flag.isNotEmpty) {
      final query = Map<String, String>.from(target.queryParameters);
      query['flag'] = flag;
      target = target.replace(queryParameters: query);
    }
    final response =
        await _client.get(target, headers: _neutralHeaders()).timeout(_timeout);
    if (response.statusCode >= 400) {
      throw UpstreamException(
        statusCode: response.statusCode,
        message: _extractMessage(response.body) ?? 'subscription fetch failed',
        body: response.body,
      );
    }
    return response.body;
  }

  @override
  Future<void> resetSubscriptionSecurity(UpstreamAuth auth) async {
    await _get('/api/v1/user/resetSecurity', auth: auth);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchNotices(UpstreamAuth auth) async {
    final response = await _get('/api/v1/user/notice/fetch', auth: auth);
    final data = response['data'];
    if (data is List) {
      return data.map((item) => Map<String, dynamic>.from(item)).toList();
    }
    return <Map<String, dynamic>>[];
  }

  @override
  Future<List<Map<String, dynamic>>> fetchServers(UpstreamAuth auth) async {
    final response = await _get('/api/v1/user/server/fetch', auth: auth);
    final data = response['data'];
    if (data is List) {
      return data.map((item) => Map<String, dynamic>.from(item)).toList();
    }
    return <Map<String, dynamic>>[];
  }

  @override
  Future<List<Map<String, dynamic>>> fetchTrafficLogs(UpstreamAuth auth) async {
    final response = await _get('/api/v1/user/stat/getTrafficLog', auth: auth);
    final data = response['data'];
    if (data is List) {
      return data.map((item) => Map<String, dynamic>.from(item)).toList();
    }
    return <Map<String, dynamic>>[];
  }

  @override
  Future<List<Map<String, dynamic>>> fetchPaymentMethods(
      UpstreamAuth auth) async {
    final response = await _get(
      '/api/v1/user/order/getPaymentMethod',
      auth: auth,
    );
    final data = response['data'];
    if (data is List) {
      return data.map((item) => Map<String, dynamic>.from(item)).toList();
    }
    return <Map<String, dynamic>>[];
  }

  @override
  Future<String> createOrder(
    UpstreamAuth auth, {
    required int planId,
    required String period,
    String? couponCode,
  }) async {
    final response = await _post(
      '/api/v1/user/order/save',
      auth: auth,
      body: {
        'plan_id': '$planId',
        'period': period,
        if (couponCode?.isNotEmpty == true) 'coupon_code': couponCode,
      },
    );
    final tradeNo = response['data']?.toString();
    if (tradeNo == null || tradeNo.isEmpty) {
      throw UpstreamException(
        statusCode: 502,
        message: 'order creation failed',
        body: jsonEncode(response),
      );
    }
    return tradeNo;
  }

  @override
  Future<Map<String, dynamic>> validateCoupon(
    UpstreamAuth auth, {
    required int planId,
    required String period,
    required String couponCode,
  }) {
    return _post(
      '/api/v1/user/coupon/check',
      auth: auth,
      body: {
        'plan_id': '$planId',
        'period': period,
        'code': couponCode,
      },
    );
  }

  @override
  Future<Map<String, dynamic>> fetchOrderDetail(
    UpstreamAuth auth, {
    required String tradeNo,
  }) {
    return _get(
      '/api/v1/user/order/detail',
      auth: auth,
      query: {'trade_no': tradeNo},
    );
  }

  @override
  Future<Map<String, dynamic>> checkoutOrder(
    UpstreamAuth auth, {
    required String tradeNo,
    required int methodId,
    String? origin,
    String? referer,
  }) {
    return _post(
      '/api/v1/user/order/checkout',
      auth: auth,
      body: {
        'trade_no': tradeNo,
        'method': '$methodId',
      },
      headers: <String, String>{
        if (_trimmedOrNull(origin) != null) 'Origin': origin!.trim(),
        if (_trimmedOrNull(referer) != null) 'Referer': referer!.trim(),
      },
    );
  }

  @override
  Future<int> checkOrder(UpstreamAuth auth, {required String tradeNo}) async {
    final response = await _get(
      '/api/v1/user/order/check',
      auth: auth,
      query: {'trade_no': tradeNo},
    );
    final data = response['data'];
    if (data is num) return data.toInt();
    return int.tryParse(data?.toString() ?? '') ?? 0;
  }

  @override
  Future<void> cancelOrder(UpstreamAuth auth, {required String tradeNo}) async {
    await _post(
      '/api/v1/user/order/cancel',
      auth: auth,
      body: {'trade_no': tradeNo},
    );
  }

  @override
  Future<List<Map<String, dynamic>>> fetchOrders(UpstreamAuth auth) async {
    final response = await _get('/api/v1/user/order/fetch', auth: auth);
    final data = response['data'];
    if (data is List) {
      return data.map((item) => Map<String, dynamic>.from(item)).toList();
    }
    return <Map<String, dynamic>>[];
  }

  @override
  Future<Map<String, dynamic>> fetchInviteOverview(UpstreamAuth auth) {
    return _get('/api/v1/user/invite/fetch', auth: auth);
  }

  @override
  Future<Map<String, dynamic>> fetchInviteRecords(
    UpstreamAuth auth, {
    required int page,
    required int pageSize,
  }) {
    return _get(
      '/api/v1/user/invite/details',
      auth: auth,
      query: <String, String>{
        'current': '$page',
        'page_size': '$pageSize',
      },
    );
  }

  @override
  Future<void> generateInviteCode(UpstreamAuth auth) async {
    await _get('/api/v1/user/invite/save', auth: auth);
  }

  @override
  Future<void> transferCommissionToBalance(
    UpstreamAuth auth, {
    required int amountCents,
  }) async {
    await _post(
      '/api/v1/user/transfer',
      auth: auth,
      body: {'transfer_amount': amountCents},
    );
  }

  @override
  Future<void> requestCommissionWithdrawal(
    UpstreamAuth auth, {
    required String method,
    required String account,
  }) async {
    await _post(
      '/api/v1/user/ticket/withdraw',
      auth: auth,
      body: {
        'withdraw_method': method,
        'withdraw_account': account,
      },
    );
  }

  @override
  Future<List<Map<String, dynamic>>> fetchTickets(UpstreamAuth auth) async {
    final response = await _get('/api/v1/user/ticket/fetch', auth: auth);
    final data = response['data'];
    if (data is List) {
      return data.map((item) => Map<String, dynamic>.from(item)).toList();
    }
    return <Map<String, dynamic>>[];
  }

  @override
  Future<Map<String, dynamic>> fetchTicketDetail(
    UpstreamAuth auth, {
    required int ticketId,
  }) async {
    final response = await _get(
      '/api/v1/user/ticket/fetch',
      auth: auth,
      query: {'id': '$ticketId'},
    );
    final data = response['data'];
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return <String, dynamic>{};
  }

  @override
  Future<void> createTicket(
    UpstreamAuth auth, {
    required String subject,
    required int level,
    required String message,
  }) async {
    await _post(
      '/api/v1/user/ticket/save',
      auth: auth,
      body: {
        'subject': subject,
        'level': '$level',
        'message': message,
      },
    );
  }

  @override
  Future<void> replyTicket(
    UpstreamAuth auth, {
    required int ticketId,
    required String message,
  }) async {
    await _post(
      '/api/v1/user/ticket/reply',
      auth: auth,
      body: {
        'id': '$ticketId',
        'message': message,
      },
    );
  }

  @override
  Future<void> closeTicket(
    UpstreamAuth auth, {
    required int ticketId,
  }) async {
    await _post(
      '/api/v1/user/ticket/close',
      auth: auth,
      body: {'id': '$ticketId'},
    );
  }

  @override
  Future<Map<String, dynamic>> redeemGiftCard(
    UpstreamAuth auth, {
    required String code,
  }) {
    return _post(
      '/api/v1/user/gift-card/redeem',
      auth: auth,
      body: {'code': code},
    );
  }

  @override
  Future<Map<String, dynamic>> fetchClientConfig(UpstreamAuth auth) {
    return _get(
      '/api/v1/client/app/getConfig',
      query: {'token': auth.token},
    );
  }

  @override
  Future<Map<String, dynamic>> fetchClientVersion(UpstreamAuth auth) {
    return _get(
      '/api/v1/client/app/getVersion',
      query: {'token': auth.token},
    );
  }

  @override
  Future<Map<String, dynamic>> fetchTelegramBotInfo(UpstreamAuth auth) {
    return _get('/api/v1/user/telegram/getBotInfo', auth: auth);
  }

  @override
  Future<Map<String, dynamic>> fetchHelpArticles(
    UpstreamAuth auth, {
    required String language,
  }) {
    return _get(
      '/api/v1/user/knowledge/fetch',
      auth: auth,
      query: {'language': language},
    );
  }

  @override
  Future<Map<String, dynamic>> fetchHelpArticleDetail(
    UpstreamAuth auth, {
    required int articleId,
    required String language,
  }) {
    return _get(
      '/api/v1/user/knowledge/fetch',
      auth: auth,
      query: {
        'id': '$articleId',
        'language': language,
      },
    );
  }

  Future<Map<String, dynamic>> _get(
    String path, {
    UpstreamAuth? auth,
    Map<String, String>? query,
  }) async {
    return _send('GET', path, auth: auth, query: query);
  }

  Future<Map<String, dynamic>> _post(
    String path, {
    UpstreamAuth? auth,
    required Map<String, dynamic> body,
    Map<String, String>? headers,
  }) async {
    return _send('POST', path, auth: auth, body: body, headers: headers);
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    UpstreamAuth? auth,
    Map<String, String>? query,
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    final target = _baseUri
        .replace(
          path: '${_baseUri.path}$path'.replaceAll('//', '/'),
          queryParameters: query,
        )
        .replace(queryParameters: query);
    final requestHeaders = <String, String>{
      ..._neutralHeaders(),
      if (headers != null) ...headers,
    };
    if (auth != null && auth.authorization.isNotEmpty) {
      requestHeaders['Authorization'] = auth.authorization;
    }
    if (body != null) {
      requestHeaders['Content-Type'] = 'application/json';
    }

    final response = method == 'GET'
        ? await _client.get(target, headers: requestHeaders).timeout(_timeout)
        : await _client
            .post(target, headers: requestHeaders, body: jsonEncode(body))
            .timeout(_timeout);

    _logger.fine('$method $target -> ${response.statusCode}');

    if (response.statusCode >= 400) {
      throw UpstreamException(
        statusCode: response.statusCode,
        message: _extractMessage(response.body) ?? 'upstream request failed',
        body: response.body,
      );
    }

    if (response.body.trim().isEmpty) {
      return <String, dynamic>{};
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return <String, dynamic>{'data': decoded};
  }

  UpstreamAuth _authFromResponse(Map<String, dynamic> response) {
    final data = response['data'];
    if (data is! Map) {
      throw UpstreamException(
        statusCode: 502,
        message: 'auth response malformed',
        body: jsonEncode(response),
      );
    }
    final token = data['token']?.toString() ?? '';
    final auth = data['auth_data']?.toString() ?? '';
    if (token.isEmpty || auth.isEmpty) {
      throw UpstreamException(
        statusCode: 502,
        message: 'auth response incomplete',
        body: jsonEncode(response),
      );
    }
    return UpstreamAuth(token: token, authorization: auth);
  }

  Map<String, String> _neutralHeaders() {
    return <String, String>{
      'Accept': 'application/json, text/plain, */*',
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Safari/537.36',
    };
  }

  String? _trimmedOrNull(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  String? _extractMessage(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return null;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        final message = decoded['message']?.toString();
        if (message != null && message.trim().isNotEmpty) {
          return message.trim();
        }
        final errors = decoded['errors'];
        if (errors is Map) {
          for (final value in errors.values) {
            if (value is List && value.isNotEmpty) {
              return value.first?.toString();
            }
            if (value is String && value.trim().isNotEmpty) {
              return value.trim();
            }
          }
        }
      }
    } catch (_) {
      // ignore
    }
    return null;
  }
}
