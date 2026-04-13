import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../config/service_config.dart';
import '../storage/session_store.dart';
import '../upstream/upstream_api.dart';

Handler createAppApiHandler({
  required ServiceConfig config,
  required SessionStore sessionStore,
  required UpstreamApi upstreamApi,
  Logger? logger,
}) {
  final service = _AppApiService(
    config: config,
    sessionStore: sessionStore,
    upstreamApi: upstreamApi,
    logger: logger ?? Logger('AppApi'),
  );
  return Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_jsonResponse())
      .addHandler(service.router.call);
}

Middleware _jsonResponse() {
  return (innerHandler) {
    return (request) async {
      final response = await innerHandler(request);
      return response.change(
        headers: <String, String>{
          ...response.headers,
          'content-type': response.headers['content-type'] ??
              'application/json; charset=utf-8',
        },
      );
    };
  };
}

class _AppApiService {
  _AppApiService({
    required this.config,
    required this.sessionStore,
    required this.upstreamApi,
    required Logger logger,
  })  : _logger = logger,
        _router = Router() {
    _mountRoutes();
  }

  final ServiceConfig config;
  final SessionStore sessionStore;
  final UpstreamApi upstreamApi;
  final Logger _logger;
  final Router _router;
  final Random _random = Random.secure();

  Router get router => _router;

  void _mountRoutes() {
    _router.get(
        '/',
        (Request request) => _ok(<String, dynamic>{
              'service': 'ok',
            }));

    _router.post('/api/app/v1/session/login', _login);
    _router.post('/api/app/v1/session/register', _register);
    _router.post('/api/app/v1/session/password/reset', _resetPassword);
    _router.post('/api/app/v1/session/email-code', _sendEmailCode);
    _router.delete('/api/app/v1/session/current', _logout);

    _router.get('/api/app/v1/public/config', _guestConfig);
    _router.get('/api/app/v1/catalog/plans', _plans);
    _router.get('/api/app/v1/account/profile', _profile);
    _router.get('/api/app/v1/account/preferences', _userConfig);
    _router.get('/api/app/v1/account/subscription', _subscriptionSummary);
    _router.get(
        '/api/app/v1/account/subscription/content', _subscriptionContent);
    _router.get('/api/app/v1/content/notices', _notices);

    _router.get('/api/app/v1/commerce/payment-methods', _paymentMethods);
    _router.get('/api/app/v1/commerce/orders', _orders);
    _router.post('/api/app/v1/commerce/orders', _createOrder);
    _router.post(
        '/api/app/v1/commerce/orders/<orderId>/checkout', _checkoutOrder);
    _router.get('/api/app/v1/commerce/orders/<orderId>/status', _orderStatus);
    _router.post('/api/app/v1/commerce/orders/<orderId>/cancel', _cancelOrder);

    _router.get('/api/app/v1/referrals/overview', _inviteOverview);
    _router.get('/api/app/v1/referrals/records', _inviteRecords);
    _router.post('/api/app/v1/referrals/codes', _generateInviteCode);

    _router.post('/api/app/v1/rewards/redeem', _redeemGift);

    _router.get('/api/app/v1/client/config', _clientConfig);
    _router.get('/api/app/v1/client/version', _clientVersion);

    _router.all('/<ignored|.*>', (Request request) {
      return _error('route.not_found', 'Request failed', HttpStatus.notFound);
    });
  }

  Future<Response> _login(Request request) async {
    final body = await _jsonBody(request);
    return _withUpstreamGuard(() async {
      final auth = await upstreamApi.login(
        email: body['email']?.toString() ?? '',
        password: body['password']?.toString() ?? '',
      );
      final record = await sessionStore.create(
        upstreamToken: auth.token,
        upstreamAuth: auth.authorization,
        ttl: config.sessionTtl,
      );
      final profile = await upstreamApi.fetchUserProfile(auth);
      await _jitter();
      return _ok(<String, dynamic>{
        'session': <String, dynamic>{
          'token': record.id,
          'expires_at': record.expiresAt.toIso8601String(),
        },
        'account': _mapAccount(profile['data'] as Map? ?? const {}),
      });
    });
  }

  Future<Response> _register(Request request) async {
    final body = await _jsonBody(request);
    return _withUpstreamGuard(() async {
      final auth = await upstreamApi.register(
        email: body['email']?.toString() ?? '',
        password: body['password']?.toString() ?? '',
        inviteCode: body['invite_code']?.toString(),
        emailCode: body['email_code']?.toString(),
        recaptchaData: body['captcha_payload']?.toString(),
      );
      final record = await sessionStore.create(
        upstreamToken: auth.token,
        upstreamAuth: auth.authorization,
        ttl: config.sessionTtl,
      );
      final profile = await upstreamApi.fetchUserProfile(auth);
      await _jitter();
      return _ok(<String, dynamic>{
        'session': <String, dynamic>{
          'token': record.id,
          'expires_at': record.expiresAt.toIso8601String(),
        },
        'account': _mapAccount(profile['data'] as Map? ?? const {}),
      });
    });
  }

  Future<Response> _sendEmailCode(Request request) async {
    final body = await _jsonBody(request);
    return _withUpstreamGuard(() async {
      await upstreamApi.sendEmailCode(
        email: body['email']?.toString() ?? '',
        recaptchaData: body['captcha_payload']?.toString(),
      );
      await _jitter();
      return _ok(<String, dynamic>{'sent': true});
    });
  }

  Future<Response> _resetPassword(Request request) async {
    final body = await _jsonBody(request);
    return _withUpstreamGuard(() async {
      await upstreamApi.resetPassword(
        email: body['email']?.toString() ?? '',
        emailCode: body['email_code']?.toString() ?? '',
        password: body['password']?.toString() ?? '',
      );
      await _jitter();
      return _ok(<String, dynamic>{'changed': true});
    });
  }

  Future<Response> _logout(Request request) async {
    final session = await _requireSession(request);
    if (session == null) {
      return _error(
          'auth.required', 'Authentication required', HttpStatus.unauthorized);
    }
    await sessionStore.delete(session.id);
    return _ok(<String, dynamic>{'cleared': true});
  }

  Future<Response> _plans(Request request) async {
    final session = await _requireSession(request);
    return _withUpstreamGuard(() async {
      final items = session == null
          ? await upstreamApi.fetchGuestPlans()
          : await upstreamApi.fetchPlans(_toAuth(session));
      return _ok(<String, dynamic>{
        'items': items.map(_mapPlan).toList(),
      });
    });
  }

  Future<Response> _guestConfig(Request request) async {
    return _withUpstreamGuard(() async {
      final configData = await upstreamApi.fetchGuestConfig();
      return _ok(<String, dynamic>{
        'config': _mapGuestConfig(configData['data'] as Map? ?? const {}),
      });
    });
  }

  Future<Response> _profile(Request request) async {
    final session = await _requireSession(request);
    if (session == null) {
      return _error(
          'auth.required', 'Authentication required', HttpStatus.unauthorized);
    }
    return _withUpstreamGuard(() async {
      final profile = await upstreamApi.fetchUserProfile(_toAuth(session));
      return _ok(<String, dynamic>{
        'account': _mapAccount(profile['data'] as Map? ?? const {}),
      });
    });
  }

  Future<Response> _userConfig(Request request) async {
    final session = await _requireSession(request);
    if (session == null) {
      return _error(
          'auth.required', 'Authentication required', HttpStatus.unauthorized);
    }
    return _withUpstreamGuard(() async {
      final configData = await upstreamApi.fetchUserConfig(_toAuth(session));
      return _ok(<String, dynamic>{
        'config': _mapUserConfig(configData['data'] as Map? ?? const {}),
      });
    });
  }

  Future<Response> _subscriptionSummary(Request request) async {
    final session = await _requireSession(request);
    if (session == null) {
      return _error(
          'auth.required', 'Authentication required', HttpStatus.unauthorized);
    }
    return _withUpstreamGuard(() async {
      final summary =
          await upstreamApi.fetchSubscriptionSummary(_toAuth(session));
      return _ok(<String, dynamic>{
        'subscription': _mapSubscription(summary['data'] as Map? ?? const {}),
      });
    });
  }

  Future<Response> _subscriptionContent(Request request) async {
    final session = await _requireSession(request);
    if (session == null) {
      return _error(
          'auth.required', 'Authentication required', HttpStatus.unauthorized);
    }
    try {
      final content = await upstreamApi.fetchSubscriptionContent(
        _toAuth(session),
        flag: request.url.queryParameters['flag'],
      );
      return Response.ok(
        content,
        headers: <String, String>{'content-type': 'text/plain; charset=utf-8'},
      );
    } on UpstreamException catch (error) {
      return _error(
        'subscription.unavailable',
        _safeMessage(error.statusCode),
        error.statusCode >= 500 ? HttpStatus.badGateway : HttpStatus.badRequest,
      );
    }
  }

  Future<Response> _notices(Request request) async {
    final session = await _requireSession(request);
    if (session == null) {
      return _error(
          'auth.required', 'Authentication required', HttpStatus.unauthorized);
    }
    return _withUpstreamGuard(() async {
      final notices = await upstreamApi.fetchNotices(_toAuth(session));
      return _ok(<String, dynamic>{
        'items': notices.map(_mapNotice).toList(),
      });
    });
  }

  Future<Response> _paymentMethods(Request request) async {
    final session = await _requireSession(request);
    if (session == null) {
      return _error(
          'auth.required', 'Authentication required', HttpStatus.unauthorized);
    }
    return _withUpstreamGuard(() async {
      final methods = await upstreamApi.fetchPaymentMethods(_toAuth(session));
      return _ok(<String, dynamic>{
        'items': methods.map(_mapPaymentMethod).toList(),
      });
    });
  }

  Future<Response> _orders(Request request) async {
    final session = await _requireSession(request);
    if (session == null) {
      return _error(
          'auth.required', 'Authentication required', HttpStatus.unauthorized);
    }
    return _withUpstreamGuard(() async {
      final orders = await upstreamApi.fetchOrders(_toAuth(session));
      return _ok(<String, dynamic>{
        'items': orders.map(_mapOrder).toList(),
      });
    });
  }

  Future<Response> _createOrder(Request request) async {
    final session = await _requireSession(request);
    if (session == null) {
      return _error(
          'auth.required', 'Authentication required', HttpStatus.unauthorized);
    }
    final body = await _jsonBody(request);
    return _withUpstreamGuard(() async {
      final orderRef = await upstreamApi.createOrder(
        _toAuth(session),
        planId: (body['plan_id'] as num?)?.toInt() ?? 0,
        period: body['period_key']?.toString() ?? '',
        couponCode: body['coupon_code']?.toString(),
      );
      return _ok(<String, dynamic>{
        'order_ref': orderRef,
      });
    });
  }

  Future<Response> _checkoutOrder(Request request, String orderId) async {
    final session = await _requireSession(request);
    if (session == null) {
      return _error(
          'auth.required', 'Authentication required', HttpStatus.unauthorized);
    }
    final body = await _jsonBody(request);
    return _withUpstreamGuard(() async {
      final result = await upstreamApi.checkoutOrder(
        _toAuth(session),
        tradeNo: orderId,
        methodId: (body['payment_method_id'] as num?)?.toInt() ?? 0,
      );
      return _ok(<String, dynamic>{
        'action': _mapCheckoutAction(result),
      });
    });
  }

  Future<Response> _orderStatus(Request request, String orderId) async {
    final session = await _requireSession(request);
    if (session == null) {
      return _error(
          'auth.required', 'Authentication required', HttpStatus.unauthorized);
    }
    return _withUpstreamGuard(() async {
      final status =
          await upstreamApi.checkOrder(_toAuth(session), tradeNo: orderId);
      return _ok(<String, dynamic>{'state_code': status});
    });
  }

  Future<Response> _cancelOrder(Request request, String orderId) async {
    final session = await _requireSession(request);
    if (session == null) {
      return _error(
          'auth.required', 'Authentication required', HttpStatus.unauthorized);
    }
    return _withUpstreamGuard(() async {
      await upstreamApi.cancelOrder(_toAuth(session), tradeNo: orderId);
      return _ok(<String, dynamic>{'canceled': true});
    });
  }

  Future<Response> _inviteOverview(Request request) async {
    final session = await _requireSession(request);
    if (session == null) {
      return _error(
          'auth.required', 'Authentication required', HttpStatus.unauthorized);
    }
    return _withUpstreamGuard(() async {
      final overview = await upstreamApi.fetchInviteOverview(_toAuth(session));
      final data = overview['data'] as Map? ?? const {};
      return _ok(<String, dynamic>{
        'codes': _mapInviteCodes((data['codes'] as List?) ?? const []),
        'metrics': _mapInviteMetrics(data['stat']),
      });
    });
  }

  Future<Response> _inviteRecords(Request request) async {
    final session = await _requireSession(request);
    if (session == null) {
      return _error(
          'auth.required', 'Authentication required', HttpStatus.unauthorized);
    }
    return _withUpstreamGuard(() async {
      final records = await upstreamApi.fetchInviteRecords(_toAuth(session));
      return _ok(<String, dynamic>{
        'items': records.map(_mapInviteRecord).toList(),
      });
    });
  }

  Future<Response> _generateInviteCode(Request request) async {
    final session = await _requireSession(request);
    if (session == null) {
      return _error(
          'auth.required', 'Authentication required', HttpStatus.unauthorized);
    }
    return _withUpstreamGuard(() async {
      await upstreamApi.generateInviteCode(_toAuth(session));
      return _ok(<String, dynamic>{'created': true});
    });
  }

  Future<Response> _redeemGift(Request request) async {
    final session = await _requireSession(request);
    if (session == null) {
      return _error(
          'auth.required', 'Authentication required', HttpStatus.unauthorized);
    }
    final body = await _jsonBody(request);
    return _withUpstreamGuard(() async {
      final result = await upstreamApi.redeemGiftCard(
        _toAuth(session),
        code: body['code']?.toString() ?? '',
      );
      return _ok(<String, dynamic>{
        'result': _mapReward(result['data'] as Map? ?? const {}),
      });
    });
  }

  Future<Response> _clientConfig(Request request) async {
    final session = await _requireSession(request);
    if (session == null) {
      return _error(
          'auth.required', 'Authentication required', HttpStatus.unauthorized);
    }
    return _withUpstreamGuard(() async {
      final configData = await upstreamApi.fetchClientConfig(_toAuth(session));
      return _ok(<String, dynamic>{
        'config': configData['data'] ?? const <String, dynamic>{},
      });
    });
  }

  Future<Response> _clientVersion(Request request) async {
    final session = await _requireSession(request);
    if (session == null) {
      return _error(
          'auth.required', 'Authentication required', HttpStatus.unauthorized);
    }
    return _withUpstreamGuard(() async {
      final versionData =
          await upstreamApi.fetchClientVersion(_toAuth(session));
      return _ok(<String, dynamic>{
        'version': versionData['data'] ?? const <String, dynamic>{},
      });
    });
  }

  Future<Response> _withUpstreamGuard(
      Future<Response> Function() action) async {
    try {
      return await action();
    } on UpstreamException catch (error) {
      _logger.warning('upstream error ${error.statusCode}: ${error.message}');
      final status = switch (error.statusCode) {
        401 || 403 => HttpStatus.unauthorized,
        404 => HttpStatus.notFound,
        >= 500 => HttpStatus.badGateway,
        _ => HttpStatus.badRequest,
      };
      return _error(_codeForStatus(status), _safeMessage(status), status);
    } on FormatException catch (error) {
      _logger.warning('invalid json request: $error');
      return _error('request.invalid', 'Request failed', HttpStatus.badRequest);
    }
  }

  Future<Map<String, dynamic>> _jsonBody(Request request) async {
    final body = await request.readAsString();
    if (body.trim().isEmpty) {
      return <String, dynamic>{};
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('expected a json object');
    }
    return decoded;
  }

  Future<SessionRecord?> _requireSession(Request request) async {
    final raw = request.headers['authorization'];
    if (raw == null || raw.isEmpty) return null;
    final prefix = 'Bearer ';
    if (!raw.startsWith(prefix)) return null;
    final sessionId = raw.substring(prefix.length).trim();
    if (sessionId.isEmpty) return null;
    return sessionStore.read(sessionId);
  }

  UpstreamAuth _toAuth(SessionRecord session) {
    return UpstreamAuth(
      token: session.upstreamToken,
      authorization: session.upstreamAuth,
    );
  }

  Response _ok(Map<String, dynamic> data) {
    return Response.ok(jsonEncode(<String, dynamic>{'data': data}));
  }

  Response _error(String code, String message, int statusCode) {
    return Response(
      statusCode,
      body: jsonEncode(
        <String, dynamic>{
          'error': <String, dynamic>{'code': code, 'message': message},
        },
      ),
    );
  }

  Map<String, dynamic> _mapAccount(Map raw) {
    return <String, dynamic>{
      'email': raw['email'] ?? '',
      'balance_amount': raw['balance'] ?? 0,
      'plan_id': raw['plan_id'] ?? 0,
      'transfer_bytes': raw['transfer_enable'] ?? 0,
      'expiry_at': raw['expired_at'] ?? 0,
      'avatar_url': raw['avatar_url'],
      'user_ref': raw['uuid'],
    };
  }

  Map<String, dynamic> _mapSubscription(Map raw) {
    return <String, dynamic>{
      'upload_bytes': raw['u'] ?? 0,
      'download_bytes': raw['d'] ?? 0,
      'total_bytes': raw['transfer_enable'] ?? 0,
      'expiry_at': raw['expired_at'] ?? 0,
      'reset_days': raw['reset_day'] ?? 0,
      'plan_id': raw['plan_id'] ?? 0,
      'download_endpoint': '/api/app/v1/account/subscription/content',
    };
  }

  Map<String, dynamic> _mapPlan(Map<String, dynamic> raw) {
    return <String, dynamic>{
      'plan_id': raw['id'] ?? 0,
      'title': raw['name'] ?? 'Plan',
      'summary': raw['content'],
      'transfer_bytes':
          _toNum(raw['transfer_enable']).toInt() * 1024 * 1024 * 1024,
      'monthly_amount': raw['month_price'],
      'quarterly_amount': raw['quarter_price'],
      'half_year_amount': raw['half_year_price'],
      'yearly_amount': raw['year_price'],
      'biennial_amount': raw['two_year_price'],
      'triennial_amount': raw['three_year_price'],
      'once_amount': raw['onetime_price'],
      'reset_amount': raw['reset_price'],
      'reset_method': raw['reset_traffic_method'],
    };
  }

  Map<String, dynamic> _mapNotice(Map<String, dynamic> raw) {
    return <String, dynamic>{
      'notice_id': raw['id'] ?? 0,
      'headline': raw['title'] ?? '',
      'body': raw['content'] ?? '',
      'created_at': raw['created_at'] ?? 0,
      'updated_at': raw['updated_at'] ?? 0,
    };
  }

  Map<String, dynamic> _mapPaymentMethod(Map<String, dynamic> raw) {
    return <String, dynamic>{
      'method_id': raw['id'] ?? 0,
      'label': raw['name'] ?? '',
      'provider': raw['payment'] ?? '',
      'icon_url': raw['icon'],
      'fee_fixed': raw['handling_fee_fixed'] ?? 0,
      'fee_rate': raw['handling_fee_percent'] ?? 0,
    };
  }

  Map<String, dynamic> _mapOrder(Map<String, dynamic> raw) {
    final plan = raw['plan'];
    return <String, dynamic>{
      'order_ref': raw['trade_no'] ?? '',
      'state_code': raw['status'] ?? 0,
      'amount_total': raw['total_amount'] ?? 0,
      'created_at': raw['created_at'] ?? 0,
      'updated_at': raw['updated_at'] ?? 0,
      'plan': plan is Map ? _mapPlan(Map<String, dynamic>.from(plan)) : null,
    };
  }

  Map<String, dynamic> _mapCheckoutAction(Map<String, dynamic> raw) {
    final payload = raw['data'];
    final type = raw['type'];
    return <String, dynamic>{
      'kind': payload is String ? 'redirect' : 'inline',
      'payload': payload,
      'code': type,
    };
  }

  List<Map<String, dynamic>> _mapInviteCodes(List rawCodes) {
    return rawCodes
        .whereType<Map>()
        .map(
          (raw) => <String, dynamic>{
            'code_id': raw['id'] ?? 0,
            'owner_ref': raw['user_id'] ?? 0,
            'invite_code': raw['code'] ?? '',
            'state_code': raw['status'] ?? 0,
            'visit_count': raw['pv'] ?? 0,
            'created_at': raw['created_at'] ?? 0,
            'updated_at': raw['updated_at'] ?? 0,
          },
        )
        .toList();
  }

  Map<String, dynamic> _mapInviteMetrics(Object? rawStat) {
    final stat = rawStat is List ? rawStat : const [];
    return <String, dynamic>{
      'registered_users': stat.length > 0 ? stat[0] ?? 0 : 0,
      'settled_amount': stat.length > 1 ? stat[1] ?? 0 : 0,
      'pending_amount': stat.length > 2 ? stat[2] ?? 0 : 0,
      'rate_percent': stat.length > 3 ? stat[3] ?? 0 : 0,
      'withdrawable_amount': stat.length > 4 ? stat[4] ?? 0 : 0,
    };
  }

  Map<String, dynamic> _mapInviteRecord(Map<String, dynamic> raw) {
    return <String, dynamic>{
      'record_id': raw['id'] ?? 0,
      'amount': raw['get_amount'] ?? 0,
      'order_amount': raw['order_amount'] ?? 0,
      'trade_ref': raw['trade_no'],
      'created_at': raw['created_at'] ?? 0,
      'status_text': raw['status_text'],
    };
  }

  Map<String, dynamic> _mapReward(Map raw) {
    return <String, dynamic>{
      'ok': true,
      'message': raw['message'] ?? 'ok',
      'rewards': raw['rewards'],
      'referral_rewards': raw['invite_rewards'],
      'label': raw['template_name'],
    };
  }

  Map<String, dynamic> _mapGuestConfig(Map raw) {
    return <String, dynamic>{
      'tos_link': raw['tos_url'],
      'email_verification_required': raw['is_email_verify'] ?? 0,
      'invite_code_required': raw['is_invite_force'] ?? 0,
      'email_whitelist_suffix': raw['email_whitelist_suffix'] ?? 0,
      'captcha_enabled': raw['is_captcha'] ?? 0,
      'captcha_kind': raw['captcha_type'],
      'captcha_site_key': raw['recaptcha_site_key'],
      'captcha_site_key_v3': raw['recaptcha_v3_site_key'],
      'captcha_score_threshold': raw['recaptcha_v3_score_threshold'],
      'turnstile_site_key': raw['turnstile_site_key'],
      'service_summary': raw['app_description'],
      'website_link': raw['app_url'],
      'logo_url': raw['logo'],
    };
  }

  Map<String, dynamic> _mapUserConfig(Map raw) {
    return <String, dynamic>{
      'telegram_enabled': raw['is_telegram'] ?? 0,
      'telegram_discuss_link': raw['telegram_discuss_link'],
      'stripe_publishable_key': raw['stripe_pk'],
      'payout_methods': raw['withdraw_methods'] ?? const [],
      'payout_closed': raw['withdraw_close'] ?? 0,
      'currency_code': raw['currency'] ?? 'CNY',
      'currency_symbol': raw['currency_symbol'] ?? '¥',
      'commission_tiers_enabled': raw['commission_distribution_enable'] ?? 0,
      'commission_l1': raw['commission_distribution_l1'],
      'commission_l2': raw['commission_distribution_l2'],
      'commission_l3': raw['commission_distribution_l3'],
    };
  }

  String _codeForStatus(int status) {
    return switch (status) {
      401 => 'auth.invalid',
      404 => 'route.not_found',
      502 => 'upstream.failed',
      _ => 'request.failed',
    };
  }

  String _safeMessage(int status) {
    return switch (status) {
      401 => 'Authentication required',
      404 => 'Request failed',
      _ => 'Request failed',
    };
  }

  Future<void> _jitter() async {
    final spread = config.requestJitterSpread.inMilliseconds;
    final delay = config.requestJitterBase.inMilliseconds +
        (spread <= 0 ? 0 : _random.nextInt(spread));
    await Future<void>.delayed(Duration(milliseconds: delay));
  }

  num _toNum(Object? value) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value) ?? 0;
    return 0;
  }
}
