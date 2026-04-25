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
      .addMiddleware(_cors())
      .addMiddleware(logRequests())
      .addMiddleware(_jsonResponse())
      .addHandler(service.router.call);
}

Middleware _cors() {
  return (innerHandler) {
    return (request) async {
      final origin = request.headers['origin'];
      final corsHeaders = <String, String>{
        'access-control-allow-origin':
            origin == null || origin.isEmpty ? '*' : origin,
        'vary': 'Origin',
        'access-control-allow-methods': 'GET, POST, PATCH, DELETE, OPTIONS',
        'access-control-allow-headers':
            'Authorization, Content-Type, Accept, Origin',
        'access-control-max-age': '86400',
      };

      if (request.method.toUpperCase() == 'OPTIONS') {
        return Response(
          HttpStatus.noContent,
          headers: corsHeaders,
        );
      }

      final response = await innerHandler(request);
      return response.change(
        headers: <String, String>{
          ...response.headers,
          ...corsHeaders,
        },
      );
    };
  };
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
  static const String _guestConfigCacheControl =
      'public, s-maxage=60, stale-while-revalidate=300';
  static const Duration _clientVersionCacheTtl = Duration(minutes: 5);
  static const Duration _helpContentCacheTtl = Duration(minutes: 5);

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
  static const Duration _subscriptionAccessTtl = Duration(days: 365);
  _TimedCacheEntry<Map<String, dynamic>>? _clientVersionCache;
  final Map<String, _TimedCacheEntry<Object?>> _helpArticlesCache =
      <String, _TimedCacheEntry<Object?>>{};
  final Map<String, _TimedCacheEntry<Map<String, dynamic>>>
      _helpArticleDetailCache =
      <String, _TimedCacheEntry<Map<String, dynamic>>>{};

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
    _router.get('/api/app/v1/account/bootstrap', _accountBootstrap);
    _router.get('/api/app/v1/account/preferences', _userConfig);
    _router.patch('/api/app/v1/account/notifications', _updateNotifications);
    _router.post('/api/app/v1/account/password/change', _changePassword);
    _router.get('/api/app/v1/account/subscription', _subscriptionSummary);
    _router.get(
        '/api/app/v1/account/subscription/content', _subscriptionContent);
    _router.post(
        '/api/app/v1/account/subscription/reset', _resetSubscriptionSecurity);
    _router.post('/api/app/v1/account/subscription/access-link',
        _createSubscriptionAccessLink);
    _router.get('/api/app/v1/account/traffic-logs', _trafficLogs);
    _router.get('/api/app/v1/client/subscription/<accessId>',
        _subscriptionContentByAccess);
    _router.get('/api/app/v1/content/notices', _notices);
    _router.get('/api/app/v1/content/help/articles', _helpArticles);
    _router.get('/api/app/v1/content/help/articles/<articleId>', _helpArticle);

    _router.get('/api/app/v1/client/nodes/status', _nodeStatuses);
    _router.get('/api/app/v1/commerce/payment-methods', _paymentMethods);
    _router.post('/api/app/v1/commerce/coupons/validate', _validateCoupon);
    _router.get('/api/app/v1/commerce/orders', _orders);
    _router.post('/api/app/v1/commerce/orders', _createOrder);
    _router.get('/api/app/v1/commerce/orders/<orderId>', _orderDetail);
    _router.post(
        '/api/app/v1/commerce/orders/<orderId>/checkout', _checkoutOrder);
    _router.get('/api/app/v1/commerce/orders/<orderId>/status', _orderStatus);
    _router.post('/api/app/v1/commerce/orders/<orderId>/cancel', _cancelOrder);

    _router.get('/api/app/v1/referrals/overview', _inviteOverview);
    _router.get('/api/app/v1/referrals/records', _inviteRecords);
    _router.post('/api/app/v1/referrals/codes', _generateInviteCode);
    _router.post(
        '/api/app/v1/referrals/transfer-to-balance', _transferInviteBalance);
    _router.post('/api/app/v1/referrals/withdrawals', _requestWithdrawal);

    _router.get('/api/app/v1/support/tickets', _tickets);
    _router.get('/api/app/v1/support/tickets/<ticketId>', _ticketDetail);
    _router.post('/api/app/v1/support/tickets', _createTicket);
    _router.post('/api/app/v1/support/tickets/<ticketId>/reply', _replyTicket);
    _router.post('/api/app/v1/support/tickets/<ticketId>/close', _closeTicket);

    _router.post('/api/app/v1/rewards/redeem', _redeemGift);

    _router.get('/api/app/v1/client/config', _clientConfig);
    _router.get('/api/app/v1/client/version', _clientVersion);
    _router.get('/api/app/v1/client/downloads', _clientDownloads);
    _router.get('/api/app/v1/client/import-options', _clientImportOptions);
    _router.get('/api/app/v1/web/bootstrap', _webBootstrap);

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
      await _storeSessionOwnerKey(
        record,
        Map<String, dynamic>.from(
          profile['data'] as Map? ?? const <String, dynamic>{},
        ),
      );
      await _jitter();
      return _ok(<String, dynamic>{
        'session': <String, dynamic>{
          'token': record.id,
          'expires_at': record.expiresAt.toIso8601String(),
        },
        'account': _mapAccount(profile['data'] as Map? ?? const {}),
      });
    }, operation: 'auth.login');
  }

  Future<Response> _register(Request request) async {
    final body = await _jsonBody(request);
    return _withUpstreamGuard(() async {
      final auth = await upstreamApi.register(
        email: body['email']?.toString() ?? '',
        password: body['password']?.toString() ?? '',
        inviteCode: _trimmedOrNull(body['invite_code']),
        emailCode: _trimmedOrNull(body['email_code']),
        recaptchaData: _trimmedOrNull(body['captcha_payload']),
      );
      final record = await sessionStore.create(
        upstreamToken: auth.token,
        upstreamAuth: auth.authorization,
        ttl: config.sessionTtl,
      );
      final profile = await upstreamApi.fetchUserProfile(auth);
      await _storeSessionOwnerKey(
        record,
        Map<String, dynamic>.from(
          profile['data'] as Map? ?? const <String, dynamic>{},
        ),
      );
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
      }, headers: <String, String>{
        'cache-control': _guestConfigCacheControl,
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
      final profile = await _fetchProfileData(session);
      return _ok(<String, dynamic>{
        'account': _mapAccount(profile),
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
      final config = Map<String, dynamic>.from(
        configData['data'] as Map? ?? const {},
      );
      return _ok(<String, dynamic>{
        'config': _mapUserConfig(config),
      });
    });
  }

  Future<Response> _accountBootstrap(Request request) async {
    final session = await _requireSession(request);
    if (session == null) {
      return _error(
          'auth.required', 'Authentication required', HttpStatus.unauthorized);
    }
    return _withUpstreamGuard(() async {
      final payload = await _loadAccountBootstrapPayload(
        session,
        includeTelegramBinding: true,
      );
      return _ok(payload.toJson());
    });
  }

  Future<Response> _webBootstrap(Request request) async {
    final session = await _requireSession(request);
    if (session == null) {
      return _error(
          'auth.required', 'Authentication required', HttpStatus.unauthorized);
    }
    return _withUpstreamGuard(() async {
      final auth = _toAuth(session);
      final accountFuture = _loadAccountBootstrapPayload(
        session,
        includeTelegramBinding: false,
      );
      final plansFuture = upstreamApi.fetchPlans(auth);
      final noticesFuture = upstreamApi.fetchNotices(auth);
      final payload = await accountFuture;
      final plans = await plansFuture;
      final notices = await noticesFuture;
      return _ok(<String, dynamic>{
        ...payload.toJson(),
        'plans': plans.map(_mapPlan).toList(),
        'notices': notices.map(_mapNotice).toList(),
      });
    });
  }

  Future<Response> _updateNotifications(Request request) async {
    final session = await _requireSession(request);
    if (session == null) {
      return _error(
          'auth.required', 'Authentication required', HttpStatus.unauthorized);
    }
    final body = await _jsonBody(request);
    return _withUpstreamGuard(() async {
      final auth = _toAuth(session);
      await upstreamApi.updateUserNotifications(
        auth,
        remindExpire: _toBool(body['expiry'] ?? body['remind_expire']),
        remindTraffic: _toBool(body['traffic'] ?? body['remind_traffic']),
      );
      final profile = await upstreamApi.fetchUserProfile(auth);
      return _ok(<String, dynamic>{
        'updated': true,
        'account': _mapAccount(profile['data'] as Map? ?? const {}),
      });
    });
  }

  Future<Response> _changePassword(Request request) async {
    final session = await _requireSession(request);
    if (session == null) {
      return _error(
          'auth.required', 'Authentication required', HttpStatus.unauthorized);
    }
    final body = await _jsonBody(request);
    final oldPassword = body['old_password']?.toString() ?? '';
    final newPassword = body['new_password']?.toString() ?? '';
    if (oldPassword.isEmpty || newPassword.length < 8) {
      return _error('request.invalid', 'Request failed', HttpStatus.badRequest);
    }
    return _withUpstreamGuard(() async {
      await upstreamApi.changePassword(
        _toAuth(session),
        oldPassword: oldPassword,
        newPassword: newPassword,
      );
      return _ok(<String, dynamic>{'changed': true});
    });
  }

  Future<Response> _subscriptionSummary(Request request) async {
    final session = await _requireSession(request);
    if (session == null) {
      return _error(
          'auth.required', 'Authentication required', HttpStatus.unauthorized);
    }
    return _withUpstreamGuard(() async {
      final auth = _toAuth(session);
      final summary = await _loadSubscriptionPayload(
        auth,
        fallbackProfileLoader: () => _fetchProfileData(session),
      );
      return _ok(<String, dynamic>{
        'subscription': summary.subscription,
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

  Future<Response> _resetSubscriptionSecurity(Request request) async {
    final session = await _requireSession(request);
    if (session == null) {
      return _error(
          'auth.required', 'Authentication required', HttpStatus.unauthorized);
    }
    return _withUpstreamGuard(() async {
      final auth = _toAuth(session);
      final summary = await upstreamApi.fetchSubscriptionSummary(auth);
      if (!_hasUsableSubscription(summary['data'])) {
        return _error(
          'subscription.required',
          'Request failed',
          HttpStatus.badRequest,
        );
      }
      final accessContext = await _subscriptionAccessContext(session);
      await upstreamApi.resetSubscriptionSecurity(auth);
      final generation =
          await sessionStore.bumpSubscriptionGeneration(accessContext.ownerKey);
      await sessionStore.revokeSubscriptionAccesses(accessContext.ownerKey);
      final access = await sessionStore.createSubscriptionAccess(
        upstreamToken: session.upstreamToken,
        upstreamAuth: session.upstreamAuth,
        ownerKey: accessContext.ownerKey,
        generation: generation,
        ttl: _subscriptionAccessTtl,
      );
      return _ok(<String, dynamic>{
        'reset': true,
        'subscription': <String, dynamic>{
          'access_url': _subscriptionAccessUrl(request, access.id),
          'expires_at': access.expiresAt.toIso8601String(),
        },
      });
    });
  }

  Future<Response> _createSubscriptionAccessLink(Request request) async {
    final session = await _requireSession(request);
    if (session == null) {
      return _error(
          'auth.required', 'Authentication required', HttpStatus.unauthorized);
    }
    final body = await _jsonBody(request);
    return _withUpstreamGuard(() async {
      final auth = _toAuth(session);
      final summary = await upstreamApi.fetchSubscriptionSummary(auth);
      if (!_hasUsableSubscription(summary['data'])) {
        return _error(
          'subscription.required',
          'Request failed',
          HttpStatus.badRequest,
        );
      }
      final accessContext = await _subscriptionAccessContext(session);
      final flag = _trimmedOrNull(body['flag']);
      final access = await sessionStore.createSubscriptionAccess(
        upstreamToken: session.upstreamToken,
        upstreamAuth: session.upstreamAuth,
        ownerKey: accessContext.ownerKey,
        generation: accessContext.generation,
        flag: flag,
        ttl: _subscriptionAccessTtl,
      );
      return _ok(<String, dynamic>{
        'subscription': <String, dynamic>{
          'access_url': _subscriptionAccessUrl(request, access.id),
          'expires_at': access.expiresAt.toIso8601String(),
        },
      });
    });
  }

  Future<Response> _subscriptionContentByAccess(
    Request request,
    String accessId,
  ) async {
    final record = await sessionStore.readSubscriptionAccess(accessId.trim());
    if (record == null) {
      return _error(
        'subscription.unavailable',
        'Request failed',
        HttpStatus.notFound,
      );
    }
    if (record.ownerKey.trim().isEmpty) {
      return _error(
        'subscription.unavailable',
        'Request failed',
        HttpStatus.notFound,
      );
    }
    final generation = await sessionStore.readSubscriptionGeneration(
      record.ownerKey,
    );
    if (record.generation != generation) {
      return _error(
        'subscription.unavailable',
        'Request failed',
        HttpStatus.notFound,
      );
    }
    try {
      final content = await upstreamApi.fetchSubscriptionContent(
        UpstreamAuth(
          token: record.upstreamToken,
          authorization: record.upstreamAuth,
        ),
        flag: record.flag,
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

  Future<Response> _trafficLogs(Request request) async {
    final session = await _requireSession(request);
    if (session == null) {
      return _error(
          'auth.required', 'Authentication required', HttpStatus.unauthorized);
    }
    return _withUpstreamGuard(() async {
      final logs = await upstreamApi.fetchTrafficLogs(_toAuth(session));
      return _ok(<String, dynamic>{
        'items': logs.map(_mapTrafficLog).toList(),
      });
    });
  }

  Future<Response> _helpArticles(Request request) async {
    final session = await _requireSession(request);
    if (session == null) {
      return _error(
          'auth.required', 'Authentication required', HttpStatus.unauthorized);
    }
    final language =
        _normalizeHelpLanguage(request.url.queryParameters['language']);
    return _withUpstreamGuard(() async {
      final articles = await _loadHelpArticlesData(
        _toAuth(session),
        language: language,
      );
      return _ok(<String, dynamic>{
        'categories': _mapHelpCategories(articles),
      });
    });
  }

  Future<Response> _helpArticle(Request request, String articleId) async {
    final session = await _requireSession(request);
    if (session == null) {
      return _error(
          'auth.required', 'Authentication required', HttpStatus.unauthorized);
    }
    final parsedId = int.tryParse(articleId);
    if (parsedId == null || parsedId <= 0) {
      return _error('request.invalid', 'Request failed', HttpStatus.badRequest);
    }
    final language =
        _normalizeHelpLanguage(request.url.queryParameters['language']);
    return _withUpstreamGuard(() async {
      final article = await _loadHelpArticleDetailData(
        _toAuth(session),
        articleId: parsedId,
        language: language,
      );
      return _ok(<String, dynamic>{
        'article': _mapHelpArticleDetail(article),
      });
    });
  }

  Future<Response> _nodeStatuses(Request request) async {
    final session = await _requireSession(request);
    if (session == null) {
      return _error(
          'auth.required', 'Authentication required', HttpStatus.unauthorized);
    }
    return _withUpstreamGuard(() async {
      final nodes = await upstreamApi.fetchServers(_toAuth(session));
      return _ok(<String, dynamic>{
        'items': nodes.map(_mapNodeStatus).toList(),
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

  Future<Response> _validateCoupon(Request request) async {
    final session = await _requireSession(request);
    if (session == null) {
      return _error(
          'auth.required', 'Authentication required', HttpStatus.unauthorized);
    }
    final body = await _jsonBody(request);
    final planId = (body['plan_id'] as num?)?.toInt() ?? 0;
    final period = _trimmedOrNull(body['period_key']);
    final couponCode = _trimmedOrNull(body['coupon_code']);
    if (planId <= 0 || period == null || couponCode == null) {
      return _error('request.invalid', 'Request failed', HttpStatus.badRequest);
    }
    return _withUpstreamGuard(() async {
      final coupon = await upstreamApi.validateCoupon(
        _toAuth(session),
        planId: planId,
        period: period,
        couponCode: couponCode,
      );
      return _ok(<String, dynamic>{
        'valid': true,
        'coupon': _mapCoupon(coupon['data'] as Map? ?? const {}),
      });
    }, operation: 'commerce.coupon');
  }

  Future<Response> _createOrder(Request request) async {
    final session = await _requireSession(request);
    if (session == null) {
      return _error(
          'auth.required', 'Authentication required', HttpStatus.unauthorized);
    }
    final body = await _jsonBody(request);
    return _withUpstreamGuard(() async {
      String orderRef;
      try {
        orderRef = await upstreamApi.createOrder(
          _toAuth(session),
          planId: (body['plan_id'] as num?)?.toInt() ?? 0,
          period: body['period_key']?.toString() ?? '',
          couponCode: body['coupon_code']?.toString(),
        );
      } on UpstreamException catch (error) {
        if (await _hasPendingOrderConflict(
          _toAuth(session),
          error,
          planId: (body['plan_id'] as num?)?.toInt() ?? 0,
          periodKey: body['period_key']?.toString(),
        )) {
          return _error(
            'commerce.pending_order_exists',
            'Request failed',
            HttpStatus.conflict,
          );
        }
        rethrow;
      }
      return _ok(<String, dynamic>{
        'order_ref': orderRef,
      });
    });
  }

  Future<Response> _orderDetail(Request request, String orderId) async {
    final session = await _requireSession(request);
    if (session == null) {
      return _error(
          'auth.required', 'Authentication required', HttpStatus.unauthorized);
    }
    final normalizedOrderId = orderId.trim();
    if (normalizedOrderId.isEmpty) {
      return _error('request.invalid', 'Request failed', HttpStatus.badRequest);
    }
    return _withUpstreamGuard(() async {
      final detail = await upstreamApi.fetchOrderDetail(
        _toAuth(session),
        tradeNo: normalizedOrderId,
      );
      return _ok(<String, dynamic>{
        'order': _mapOrderDetail(detail['data'] as Map? ?? const {}),
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
    final checkoutOrigin = _checkoutSourceOrigin(request);
    final checkoutReferer = _checkoutSourceReferer(request);
    return _withUpstreamGuard(() async {
      final result = await upstreamApi.checkoutOrder(
        _toAuth(session),
        tradeNo: orderId,
        methodId: (body['payment_method_id'] as num?)?.toInt() ?? 0,
        origin: checkoutOrigin,
        referer: checkoutReferer,
      );
      return _ok(<String, dynamic>{
        'action': _mapCheckoutAction(result),
      });
    }, operation: 'commerce.checkout');
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
    final page = int.tryParse(request.url.queryParameters['page'] ?? '')
            ?.clamp(1, 9999) ??
        1;
    final pageSizeRaw =
        int.tryParse(request.url.queryParameters['page_size'] ?? '') ?? 10;
    final pageSize = pageSizeRaw.clamp(10, 100);
    return _withUpstreamGuard(() async {
      final records = await upstreamApi.fetchInviteRecords(
        _toAuth(session),
        page: page,
        pageSize: pageSize,
      );
      final rawItems = (records['data'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => _mapInviteRecord(Map<String, dynamic>.from(item)))
          .toList();
      final total = _toNum(records['total']).toInt();
      return _ok(<String, dynamic>{
        'items': rawItems,
        'page': page,
        'page_size': pageSize,
        'total': total,
        'has_more': page * pageSize < total,
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

  Future<Response> _transferInviteBalance(Request request) async {
    final session = await _requireSession(request);
    if (session == null) {
      return _error(
          'auth.required', 'Authentication required', HttpStatus.unauthorized);
    }
    final body = await _jsonBody(request);
    final amountCents = _toNum(body['amount_cents']).toInt();
    if (amountCents <= 0) {
      return _error(
        'referrals.no_withdrawable_commission',
        'Request failed',
        HttpStatus.badRequest,
      );
    }
    return _withUpstreamGuard(() async {
      final auth = _toAuth(session);
      final overview = await upstreamApi.fetchInviteOverview(auth);
      final available = _toNum(
        _mapInviteMetrics((overview['data'] as Map? ?? const {})['stat'])[
            'withdrawable_amount'],
      ).toInt();
      if (available <= 0) {
        return _error(
          'referrals.no_withdrawable_commission',
          'Request failed',
          HttpStatus.badRequest,
        );
      }
      if (amountCents > available) {
        return _error(
          'referrals.transfer_amount_invalid',
          'Request failed',
          HttpStatus.badRequest,
        );
      }
      await upstreamApi.transferCommissionToBalance(
        auth,
        amountCents: amountCents,
      );
      final responses = await Future.wait<Map<String, dynamic>>([
        upstreamApi.fetchUserProfile(auth),
        upstreamApi.fetchInviteOverview(auth),
      ]);
      final profile = responses[0]['data'] as Map? ?? const {};
      final refreshedOverview = responses[1]['data'] as Map? ?? const {};
      return _ok(<String, dynamic>{
        'transferred': true,
        'account': _mapAccount(profile),
        'referrals': <String, dynamic>{
          'codes': _mapInviteCodes(
            refreshedOverview['codes'] as List? ?? const [],
          ),
          'metrics': _mapInviteMetrics(refreshedOverview['stat']),
        },
      });
    }, operation: 'referrals.transfer');
  }

  Future<Response> _requestWithdrawal(Request request) async {
    final session = await _requireSession(request);
    if (session == null) {
      return _error(
          'auth.required', 'Authentication required', HttpStatus.unauthorized);
    }
    final body = await _jsonBody(request);
    final method = _trimmedOrNull(body['withdraw_method']);
    final account = _trimmedOrNull(body['withdraw_account']);
    if (method == null || account == null) {
      return _error('request.invalid', 'Request failed', HttpStatus.badRequest);
    }
    return _withUpstreamGuard(() async {
      await upstreamApi.requestCommissionWithdrawal(
        _toAuth(session),
        method: method,
        account: account,
      );
      return _ok(<String, dynamic>{'created': true});
    }, operation: 'referrals.withdrawal');
  }

  Future<Response> _tickets(Request request) async {
    final session = await _requireSession(request);
    if (session == null) {
      return _error(
          'auth.required', 'Authentication required', HttpStatus.unauthorized);
    }
    return _withUpstreamGuard(() async {
      final tickets = await upstreamApi.fetchTickets(_toAuth(session));
      return _ok(<String, dynamic>{
        'items': tickets.map(_mapTicket).toList(),
      });
    });
  }

  Future<Response> _ticketDetail(Request request, String ticketId) async {
    final session = await _requireSession(request);
    if (session == null) {
      return _error(
          'auth.required', 'Authentication required', HttpStatus.unauthorized);
    }
    final parsedId = int.tryParse(ticketId.trim());
    if (parsedId == null || parsedId <= 0) {
      return _error('request.invalid', 'Request failed', HttpStatus.badRequest);
    }
    return _withUpstreamGuard(() async {
      final ticket = await upstreamApi.fetchTicketDetail(
        _toAuth(session),
        ticketId: parsedId,
      );
      return _ok(<String, dynamic>{
        'ticket': _mapTicketDetail(ticket),
      });
    }, operation: 'support.ticket.detail');
  }

  Future<Response> _createTicket(Request request) async {
    final session = await _requireSession(request);
    if (session == null) {
      return _error(
          'auth.required', 'Authentication required', HttpStatus.unauthorized);
    }
    final body = await _jsonBody(request);
    final subject = _trimmedOrNull(body['subject']);
    final message = _trimmedOrNull(body['message']);
    final level = _toNum(body['priority_level'] ?? body['level']).toInt();
    if (subject == null || message == null || level < 0) {
      return _error('request.invalid', 'Request failed', HttpStatus.badRequest);
    }
    return _withUpstreamGuard(() async {
      await upstreamApi.createTicket(
        _toAuth(session),
        subject: subject,
        level: level,
        message: message,
      );
      return _ok(<String, dynamic>{'created': true});
    }, operation: 'support.ticket.create');
  }

  Future<Response> _replyTicket(Request request, String ticketId) async {
    final session = await _requireSession(request);
    if (session == null) {
      return _error(
          'auth.required', 'Authentication required', HttpStatus.unauthorized);
    }
    final parsedId = int.tryParse(ticketId.trim());
    final body = await _jsonBody(request);
    final message = _trimmedOrNull(body['message']);
    if (parsedId == null || parsedId <= 0 || message == null) {
      return _error('request.invalid', 'Request failed', HttpStatus.badRequest);
    }
    return _withUpstreamGuard(() async {
      await upstreamApi.replyTicket(
        _toAuth(session),
        ticketId: parsedId,
        message: message,
      );
      return _ok(<String, dynamic>{'replied': true});
    }, operation: 'support.ticket.reply');
  }

  Future<Response> _closeTicket(Request request, String ticketId) async {
    final session = await _requireSession(request);
    if (session == null) {
      return _error(
          'auth.required', 'Authentication required', HttpStatus.unauthorized);
    }
    final parsedId = int.tryParse(ticketId.trim());
    if (parsedId == null || parsedId <= 0) {
      return _error('request.invalid', 'Request failed', HttpStatus.badRequest);
    }
    return _withUpstreamGuard(() async {
      await upstreamApi.closeTicket(
        _toAuth(session),
        ticketId: parsedId,
      );
      return _ok(<String, dynamic>{'closed': true});
    }, operation: 'support.ticket.close');
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
      final status = result['status']?.toString();
      final rewardData = result['data'];
      if (status != 'success' || rewardData is! Map) {
        return _error(
          'rewards.redeem_failed',
          'Request failed',
          HttpStatus.badRequest,
        );
      }
      return _ok(<String, dynamic>{
        'result': <String, dynamic>{
          'ok': true,
          ..._mapReward(rewardData),
        },
      });
    }, operation: 'rewards.redeem');
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
      final versionData = await _loadClientVersionData(session);
      return _ok(<String, dynamic>{
        'version': versionData,
      });
    });
  }

  Future<Response> _clientDownloads(Request request) async {
    final session = await _requireSession(request);
    if (session == null) {
      return _error(
          'auth.required', 'Authentication required', HttpStatus.unauthorized);
    }
    return _withUpstreamGuard(() async {
      final versionData = await _loadClientVersionData(session);
      return _ok(<String, dynamic>{
        'items': _mapClientDownloads(versionData),
      });
    });
  }

  Future<Response> _clientImportOptions(Request request) async {
    final session = await _requireSession(request);
    if (session == null) {
      return _error(
        'auth.required',
        'Authentication required',
        HttpStatus.unauthorized,
      );
    }
    final platform =
        _normalizePlatform(request.url.queryParameters['platform']);
    if (platform == null) {
      return _error('request.invalid', 'Request failed', HttpStatus.badRequest);
    }
    return _withUpstreamGuard(() async {
      final auth = _toAuth(session);
      final summary = await upstreamApi.fetchSubscriptionSummary(auth);
      if (!_hasUsableSubscription(summary['data'])) {
        return _error(
          'subscription.required',
          'Request failed',
          HttpStatus.badRequest,
        );
      }
      final options = await _buildClientImportOptions(
        request,
        session: session,
        platform: platform,
      );
      return _ok(<String, dynamic>{'items': options});
    });
  }

  Future<Map<String, dynamic>> _fetchProfileData(SessionRecord session) async {
    final profileResponse =
        await upstreamApi.fetchUserProfile(_toAuth(session));
    final profile = Map<String, dynamic>.from(
      profileResponse['data'] as Map? ?? const {},
    );
    await _storeSessionOwnerKey(session, profile);
    return profile;
  }

  Future<void> _storeSessionOwnerKey(
    SessionRecord session,
    Map<String, dynamic> profile,
  ) async {
    final ownerKey = _subscriptionOwnerKeyOrNull(profile);
    if (ownerKey == null || ownerKey == session.ownerKey) {
      return;
    }
    await sessionStore.write(session.copyWith(ownerKey: ownerKey));
  }

  Future<_AccountBootstrapPayload> _loadAccountBootstrapPayload(
    SessionRecord session, {
    required bool includeTelegramBinding,
  }) async {
    final auth = _toAuth(session);
    final profileFuture = _fetchProfileData(session);
    final configFuture = upstreamApi.fetchUserConfig(auth);
    final summaryFuture = upstreamApi.fetchSubscriptionSummary(auth);

    final profile = await profileFuture;
    final configResponse = await configFuture;
    final config = Map<String, dynamic>.from(
      configResponse['data'] as Map? ?? const {},
    );
    final summary = await _loadSubscriptionPayload(
      auth,
      summaryFuture: summaryFuture,
      fallbackProfileLoader: () async => profile,
    );
    final telegramBinding = includeTelegramBinding
        ? await _loadTelegramBindingData(
            auth,
            config: config,
            profile: profile,
            subscribeUrl: summary.subscribeUrl,
          )
        : const _TelegramBindingData();

    return _AccountBootstrapPayload(
      account: _mapAccount(profile),
      config: _mapUserConfig(
        config,
        telegramBindUrl: telegramBinding.bindUrl,
        telegramBindCommand: telegramBinding.bindCommand,
      ),
      subscription: summary.subscription,
    );
  }

  Future<_SubscriptionPayload> _loadSubscriptionPayload(
    UpstreamAuth auth, {
    Future<Map<String, dynamic>>? summaryFuture,
    Future<Map<String, dynamic>> Function()? fallbackProfileLoader,
  }) async {
    try {
      final response =
          await (summaryFuture ?? upstreamApi.fetchSubscriptionSummary(auth));
      final raw = Map<String, dynamic>.from(
        response['data'] as Map? ?? const {},
      );
      return _SubscriptionPayload(
        subscription: _mapSubscription(raw),
        subscribeUrl: _trimmedOrNull(raw['subscribe_url']),
      );
    } on UpstreamException catch (error) {
      if (error.statusCode < 500 || fallbackProfileLoader == null) {
        rethrow;
      }
      _logger.warning(
        'subscription summary upstream ${error.statusCode}; falling back to profile',
      );
      final profile = await fallbackProfileLoader();
      return _SubscriptionPayload(
        subscription: _mapSubscriptionFromAccount(profile),
      );
    }
  }

  Future<_TelegramBindingData> _loadTelegramBindingData(
    UpstreamAuth auth, {
    required Map<String, dynamic> config,
    required Map<String, dynamic> profile,
    String? subscribeUrl,
  }) async {
    if (!_toBool(config['is_telegram']) || _toBool(profile['telegram_id'])) {
      return const _TelegramBindingData();
    }
    try {
      final botInfo = await upstreamApi.fetchTelegramBotInfo(auth);
      final username = _trimmedOrNull(
          botInfo['data'] is Map ? (botInfo['data'] as Map)['username'] : null);
      return _TelegramBindingData(
        bindUrl: username == null ? null : 'https://t.me/$username',
        bindCommand: subscribeUrl == null ? null : '/bind $subscribeUrl',
      );
    } catch (_) {
      return const _TelegramBindingData();
    }
  }

  Future<Map<String, dynamic>> _loadClientVersionData(
    SessionRecord session,
  ) async {
    final cached = _clientVersionCache;
    if (cached != null && !cached.isExpired) {
      return cached.value;
    }
    final response = await upstreamApi.fetchClientVersion(_toAuth(session));
    final data = Map<String, dynamic>.from(
      response['data'] as Map? ?? const {},
    );
    _clientVersionCache = _TimedCacheEntry(
      value: data,
      expiresAt: DateTime.now().add(_clientVersionCacheTtl),
    );
    return data;
  }

  Future<Object?> _loadHelpArticlesData(
    UpstreamAuth auth, {
    required String language,
  }) async {
    final cached = _helpArticlesCache[language];
    if (cached != null && !cached.isExpired) {
      return cached.value;
    }
    final response = await upstreamApi.fetchHelpArticles(
      auth,
      language: language,
    );
    final raw = response['data'];
    final data = raw is Map ? Map<String, dynamic>.from(raw) : raw;
    _helpArticlesCache[language] = _TimedCacheEntry(
      value: data,
      expiresAt: DateTime.now().add(_helpContentCacheTtl),
    );
    return data;
  }

  Future<Map<String, dynamic>> _loadHelpArticleDetailData(
    UpstreamAuth auth, {
    required int articleId,
    required String language,
  }) async {
    final cacheKey = '$language:$articleId';
    final cached = _helpArticleDetailCache[cacheKey];
    if (cached != null && !cached.isExpired) {
      return cached.value;
    }
    final response = await upstreamApi.fetchHelpArticleDetail(
      auth,
      articleId: articleId,
      language: language,
    );
    final data = Map<String, dynamic>.from(
      response['data'] as Map? ?? const {},
    );
    _helpArticleDetailCache[cacheKey] = _TimedCacheEntry(
      value: data,
      expiresAt: DateTime.now().add(_helpContentCacheTtl),
    );
    return data;
  }

  Future<Response> _withUpstreamGuard(
    Future<Response> Function() action, {
    String? operation,
  }) async {
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
      return _error(
        _codeForUpstreamError(error, status, operation),
        _safeMessage(status),
        status,
      );
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

  Response _ok(
    Map<String, dynamic> data, {
    Map<String, String>? headers,
  }) {
    return Response.ok(
      jsonEncode(<String, dynamic>{'data': data}),
      headers: headers,
    );
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
      'remind_expire': _toBool(raw['remind_expire']),
      'remind_traffic': _toBool(raw['remind_traffic']),
      'telegram_bound': _trimmedOrNull(raw['telegram_id']) != null,
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

  Map<String, dynamic> _mapSubscriptionFromAccount(Map raw) {
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
      'transfer_bytes': _normalizePlanTransferBytes(raw['transfer_enable']),
      'monthly_amount': raw['month_price'],
      'quarterly_amount': raw['quarter_price'],
      'half_year_amount': raw['half_year_price'],
      'yearly_amount': raw['year_price'],
      'biennial_amount': raw['two_year_price'],
      'triennial_amount': raw['three_year_price'],
      'once_amount': raw['onetime_price'],
      'reset_amount': raw['reset_price'],
      'reset_method': raw['reset_traffic_method'],
      'device_limit': raw['device_limit'],
      'capacity_limit': raw['capacity_limit'],
      'tags': raw['tags'] ?? const [],
      'sell': raw['sell'],
      'renew': raw['renew'],
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

  Map<String, dynamic> _mapNodeStatus(Map<String, dynamic> raw) {
    return <String, dynamic>{
      'node_id': _toNum(raw['id']).toInt(),
      'display_name': raw['name']?.toString() ?? '',
      'protocol_type': raw['type']?.toString() ?? '',
      'version': raw['version']?.toString() ?? '',
      'rate': _toNum(raw['rate']).toDouble(),
      'tags': (raw['tags'] as List? ?? const [])
          .map((item) => item?.toString() ?? '')
          .where((item) => item.isNotEmpty)
          .toList(),
      'is_online': _toBool(raw['is_online']),
      'last_check_at': _toNum(raw['last_check_at']).toInt(),
    };
  }

  List<Map<String, dynamic>> _mapHelpCategories(Object? raw) {
    if (raw is! Map) return const <Map<String, dynamic>>[];

    final categories = <Map<String, dynamic>>[];
    for (final entry in raw.entries) {
      final articleList = entry.value;
      if (articleList is! List) continue;
      final articles = articleList
          .whereType<Map>()
          .map(
              (item) => _mapHelpArticleSummary(Map<String, dynamic>.from(item)))
          .where((item) => item['article_id'] != 0)
          .toList();
      if (articles.isEmpty) continue;
      categories.add(<String, dynamic>{
        'name': entry.key.toString(),
        'articles': articles,
      });
    }
    return categories;
  }

  Map<String, dynamic> _mapHelpArticleSummary(Map<String, dynamic> raw) {
    return <String, dynamic>{
      'article_id': raw['id'] ?? 0,
      'category': raw['category'] ?? '',
      'title': raw['title'] ?? '',
      'updated_at': raw['updated_at'] ?? 0,
    };
  }

  Map<String, dynamic> _mapHelpArticleDetail(Map raw) {
    return <String, dynamic>{
      'article_id': raw['id'] ?? 0,
      'category': raw['category'] ?? '',
      'title': raw['title'] ?? '',
      'body_html': raw['body'] ?? '',
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

  Map<String, dynamic> _mapCoupon(Map raw) {
    return <String, dynamic>{
      'coupon_id': raw['id'] ?? 0,
      'code': raw['code'] ?? '',
      'name': raw['name'] ?? '',
      'type_code': raw['type'] ?? 0,
      'value': raw['value'] ?? 0,
      'limit_periods': raw['limit_period'] ?? const [],
      'limit_plan_ids': raw['limit_plan_ids'] ?? const [],
    };
  }

  Map<String, dynamic> _mapOrder(Map<String, dynamic> raw) {
    final plan = raw['plan'];
    final amounts = _mapNormalizedOrderAmounts(
      raw,
      plan is Map ? Map<String, dynamic>.from(plan) : null,
    );
    return <String, dynamic>{
      'order_ref': raw['trade_no'] ?? '',
      'state_code': raw['status'] ?? 0,
      'period_key': raw['period'] ?? '',
      'amount_total': raw['total_amount'] ?? 0,
      ...amounts,
      'created_at': raw['created_at'] ?? 0,
      'updated_at': raw['updated_at'] ?? 0,
      'plan': plan is Map ? _mapPlan(Map<String, dynamic>.from(plan)) : null,
    };
  }

  Map<String, dynamic> _mapOrderDetail(Map raw) {
    final plan = raw['plan'];
    final payment = raw['payment'];
    final amounts = _mapNormalizedOrderAmounts(
      raw,
      plan is Map ? Map<String, dynamic>.from(plan) : null,
    );
    return <String, dynamic>{
      'order_ref': raw['trade_no'] ?? '',
      'state_code': raw['status'] ?? 0,
      'period_key': raw['period'] ?? '',
      ...amounts,
      'created_at': raw['created_at'] ?? 0,
      'updated_at': raw['updated_at'] ?? 0,
      'plan': plan is Map ? _mapPlan(Map<String, dynamic>.from(plan)) : null,
      'payment_method': payment is Map
          ? _mapPaymentMethod(Map<String, dynamic>.from(payment))
          : null,
    };
  }

  Map<String, dynamic> _mapCheckoutAction(Map<String, dynamic> raw) {
    final payload = raw['data'];
    final type = _toNum(raw['type']).toInt();
    return <String, dynamic>{
      'kind': switch (type) {
        1 => 'redirect',
        0 => 'qr_code',
        -1 => 'completed',
        _ => payload is String ? 'redirect' : 'inline',
      },
      'payload': payload,
      'code': type,
    };
  }

  String? _checkoutSourceOrigin(Request request) {
    final headerOrigin = _normalizedOrigin(request.headers['origin']);
    if (headerOrigin != null) {
      return headerOrigin;
    }

    final headerReferer = _trimmedOrNull(request.headers['referer']);
    final refererUri =
        headerReferer == null ? null : Uri.tryParse(headerReferer);
    final refererOrigin = _uriOrigin(refererUri);
    if (refererOrigin != null) {
      return refererOrigin;
    }

    return _uriOrigin(request.requestedUri);
  }

  String? _checkoutSourceReferer(Request request) {
    final headerReferer = _trimmedOrNull(request.headers['referer']);
    final refererUri =
        headerReferer == null ? null : Uri.tryParse(headerReferer);
    if (_uriOrigin(refererUri) != null) {
      return refererUri.toString();
    }

    final origin = _checkoutSourceOrigin(request);
    if (origin != null) {
      return '$origin/';
    }
    return null;
  }

  String? _normalizedOrigin(String? raw) {
    final value = _trimmedOrNull(raw);
    if (value == null) return null;
    final uri = Uri.tryParse(value);
    return _uriOrigin(uri);
  }

  String? _uriOrigin(Uri? uri) {
    if (uri == null) return null;
    final scheme = uri.scheme.toLowerCase();
    if ((scheme != 'http' && scheme != 'https') || uri.host.isEmpty) {
      return null;
    }
    return '${uri.scheme}://${uri.authority}';
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
      'registered_users': stat.isNotEmpty ? stat[0] ?? 0 : 0,
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

  Map<String, dynamic> _mapTicket(Map<String, dynamic> raw) {
    return <String, dynamic>{
      'ticket_id': _toNum(raw['id']).toInt(),
      'subject': raw['subject']?.toString() ?? '',
      'priority_level': _toNum(raw['level']).toInt(),
      'reply_state': _toNum(raw['reply_status']).toInt(),
      'state_code': _toNum(raw['status']).toInt(),
      'created_at': _toNum(raw['created_at']).toInt(),
      'updated_at': _toNum(raw['updated_at']).toInt(),
    };
  }

  Map<String, dynamic> _mapTicketDetail(Map<String, dynamic> raw) {
    final rawMessages = (raw['message'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => _mapTicketMessage(Map<String, dynamic>.from(item)))
        .toList();
    final firstMessage =
        rawMessages.isNotEmpty ? rawMessages.first : const <String, dynamic>{};
    return <String, dynamic>{
      ..._mapTicket(raw),
      'body': firstMessage['body']?.toString() ?? '',
      'messages':
          rawMessages.length > 1 ? rawMessages.skip(1).toList() : const [],
    };
  }

  Map<String, dynamic> _mapTicketMessage(Map<String, dynamic> raw) {
    return <String, dynamic>{
      'message_id': _toNum(raw['id']).toInt(),
      'ticket_id': _toNum(raw['ticket_id']).toInt(),
      'is_mine': _toBool(raw['is_me']),
      'body': raw['message']?.toString() ?? '',
      'created_at': _toNum(raw['created_at']).toInt(),
      'updated_at': _toNum(raw['updated_at']).toInt(),
    };
  }

  Map<String, dynamic> _mapTrafficLog(Map<String, dynamic> raw) {
    final uploaded = _toNum(raw['u']).toInt();
    final downloaded = _toNum(raw['d']).toInt();
    final rateMultiplier = _toNum(raw['server_rate']).toDouble();
    return <String, dynamic>{
      'uploaded_amount': uploaded,
      'downloaded_amount': downloaded,
      'charged_amount': ((uploaded + downloaded) * rateMultiplier).round(),
      'rate_multiplier': rateMultiplier,
      'recorded_at': _toNum(raw['record_at']).toInt(),
    };
  }

  Map<String, dynamic> _mapReward(Map raw) {
    return <String, dynamic>{
      'message': raw['message'] ?? 'ok',
      'rewards': raw['rewards'],
      'referral_rewards': raw['invite_rewards'],
      'label': raw['template_name'],
    };
  }

  Future<bool> _hasPendingOrderConflict(
    UpstreamAuth auth,
    UpstreamException error, {
    required int planId,
    String? periodKey,
  }) async {
    if (error.statusCode != HttpStatus.badRequest) {
      return false;
    }
    try {
      final orders = await upstreamApi.fetchOrders(auth);
      return orders.any((item) {
        if (_toNum(item['status']).toInt() != 0) {
          return false;
        }
        final orderPlan = item['plan'];
        final orderPlanId =
            orderPlan is Map ? _toNum(orderPlan['id']).toInt() : 0;
        if (planId > 0 && orderPlanId > 0 && planId != orderPlanId) {
          return false;
        }
        final orderPeriod = item['period']?.toString().trim();
        if (periodKey != null &&
            periodKey.isNotEmpty &&
            orderPeriod != null &&
            orderPeriod.isNotEmpty &&
            periodKey != orderPeriod) {
          return false;
        }
        return true;
      });
    } catch (_) {
      return false;
    }
  }

  bool _hasUsableSubscription(Object? raw) {
    if (raw is! Map) {
      return false;
    }
    final subscribeUrl = raw['subscribe_url']?.toString().trim() ?? '';
    final totalBytes = _toNum(raw['transfer_enable']).toInt();
    return subscribeUrl.isNotEmpty && totalBytes > 0;
  }

  int _normalizePlanTransferBytes(Object? rawValue) {
    final value = _toNum(rawValue).toInt();
    if (value <= 0) {
      return 0;
    }
    if (value < 1024 * 1024) {
      return value * 1024 * 1024 * 1024;
    }
    return value;
  }

  Map<String, dynamic> _mapNormalizedOrderAmounts(
    Map raw,
    Map<String, dynamic>? rawPlan,
  ) {
    final dueBeforeFee = _toNum(raw['total_amount']).toInt();
    final handling = _toNum(raw['handling_amount']).toInt();
    final discount = _toNum(raw['discount_amount']).toInt();
    final balance = _toNum(raw['balance_amount']).toInt();
    final surplus = _toNum(raw['surplus_amount']).toInt();
    final refund = _toNum(raw['refund_amount']).toInt();
    final original = _resolveOriginalOrderAmount(
      rawPlan,
      raw['period']?.toString(),
      dueBeforeFee: dueBeforeFee,
      discountApplied: discount,
      balanceUsed: balance,
    );
    return <String, dynamic>{
      'amount_total': dueBeforeFee,
      'amount_payable': dueBeforeFee + handling,
      'amount_discount': discount,
      'amount_balance': balance,
      'amount_refund': refund,
      'amount_surplus': surplus,
      'amount_handling': handling,
      'amount_original': original,
      'amount_due_before_fee': dueBeforeFee,
      'amount_due_after_fee': dueBeforeFee + handling,
      'amount_discount_applied': discount,
      'amount_balance_used': balance,
      'amount_surplus_credit': surplus,
      'amount_refund_value': refund,
    };
  }

  int _resolveOriginalOrderAmount(
    Map<String, dynamic>? rawPlan,
    String? periodKey, {
    required int dueBeforeFee,
    required int discountApplied,
    required int balanceUsed,
  }) {
    final periodAmount = _resolveOrderPeriodAmount(rawPlan, periodKey);
    if (periodAmount > 0) {
      return periodAmount;
    }
    return dueBeforeFee + discountApplied + balanceUsed;
  }

  int _resolveOrderPeriodAmount(
    Map<String, dynamic>? rawPlan,
    String? periodKey,
  ) {
    if (rawPlan == null) {
      return 0;
    }
    final field = switch (periodKey?.trim()) {
      'month_price' => 'month_price',
      'quarter_price' => 'quarter_price',
      'half_year_price' => 'half_year_price',
      'year_price' => 'year_price',
      'two_year_price' => 'two_year_price',
      'three_year_price' => 'three_year_price',
      'onetime_price' => 'onetime_price',
      'reset_price' => 'reset_price',
      _ => null,
    };
    if (field == null) {
      return 0;
    }
    return _toNum(rawPlan[field]).toInt();
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

  Map<String, dynamic> _mapUserConfig(
    Map raw, {
    String? telegramBindUrl,
    String? telegramBindCommand,
  }) {
    return <String, dynamic>{
      'telegram_enabled': raw['is_telegram'] ?? 0,
      'telegram_discuss_link': raw['telegram_discuss_link'],
      'telegram_bind_url': telegramBindUrl,
      'telegram_bind_command': telegramBindCommand,
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

  List<Map<String, dynamic>> _mapClientDownloads(Object? raw) {
    final data = raw is Map ? raw : const <String, dynamic>{};
    return <Map<String, dynamic>>[
      _mapClientDownload(
        data,
        platform: 'windows',
        label: 'Windows',
        versionField: 'windows_version',
        urlField: 'windows_download_url',
      ),
      _mapClientDownload(
        data,
        platform: 'macos',
        label: 'macOS',
        versionField: 'macos_version',
        urlField: 'macos_download_url',
      ),
      _mapClientDownload(
        data,
        platform: 'android',
        label: 'Android',
        versionField: 'android_version',
        urlField: 'android_download_url',
      ),
      <String, dynamic>{
        'platform': 'ios',
        'label': 'iOS',
        'version': '',
        'download_url': '',
        'available': false,
      },
    ];
  }

  Map<String, dynamic> _mapClientDownload(
    Map data, {
    required String platform,
    required String label,
    required String versionField,
    required String urlField,
  }) {
    final url = data[urlField]?.toString().trim() ?? '';
    return <String, dynamic>{
      'platform': platform,
      'label': label,
      'version': data[versionField]?.toString() ?? '',
      'download_url': url,
      'available': url.isNotEmpty,
    };
  }

  String? _normalizePlatform(String? raw) {
    final value = raw?.trim().toLowerCase();
    switch (value) {
      case 'ios':
      case 'android':
      case 'macos':
      case 'windows':
        return value;
      default:
        return null;
    }
  }

  Future<List<Map<String, dynamic>>> _buildClientImportOptions(
    Request request, {
    required SessionRecord session,
    required String platform,
  }) async {
    final label = Uri.encodeComponent('Capybara');
    final accessUrlCache = <String, Future<String>>{};
    final accessContext = await _subscriptionAccessContext(session);

    Future<String> accessUrlFor(String flag) async {
      return accessUrlCache.putIfAbsent(flag, () async {
        final access = await sessionStore.createSubscriptionAccess(
          upstreamToken: session.upstreamToken,
          upstreamAuth: session.upstreamAuth,
          ownerKey: accessContext.ownerKey,
          generation: accessContext.generation,
          flag: flag,
          ttl: _subscriptionAccessTtl,
        );
        return _subscriptionAccessUrl(request, access.id);
      });
    }

    Future<Map<String, dynamic>> build({
      required String clientKey,
      required String displayName,
      required String actionType,
      required String protocolHint,
      required Future<String> Function() actionValue,
    }) async {
      return <String, dynamic>{
        'client_key': clientKey,
        'display_name': displayName,
        'icon_url': '',
        'supported': true,
        'action_type': actionType,
        'action_value': await actionValue(),
        'protocol_hint': protocolHint,
      };
    }

    switch (platform) {
      case 'ios':
        final shadowrocketUrl = await accessUrlFor('shadowrocket');
        final shadowrocketEncoded = base64.encode(utf8.encode(shadowrocketUrl));
        final quantumultUrl = await accessUrlFor('shadowrocket');
        return <Map<String, dynamic>>[
          await build(
            clientKey: 'shadowrocket',
            displayName: 'Shadowrocket',
            actionType: 'deep_link',
            protocolHint: 'shadowrocket',
            actionValue: () async =>
                'shadowrocket://add/sub://$shadowrocketEncoded?remark=$label',
          ),
          await build(
            clientKey: 'quantumult_x',
            displayName: 'Quantumult X',
            actionType: 'copy_link',
            protocolHint: 'quantumult-x',
            actionValue: () async => quantumultUrl,
          ),
        ];
      case 'android':
        final clashUrl =
            Uri.encodeComponent(await accessUrlFor('clashmetaforandroid'));
        final hiddifyUrl = await accessUrlFor('hiddify');
        final singBoxUrl = Uri.encodeComponent(await accessUrlFor('sing-box'));
        return <Map<String, dynamic>>[
          await build(
            clientKey: 'clash',
            displayName: 'Clash',
            actionType: 'deep_link',
            protocolHint: 'clash',
            actionValue: () async =>
                'clash://install-config?url=$clashUrl&name=$label',
          ),
          await build(
            clientKey: 'hiddify',
            displayName: 'Hiddify',
            actionType: 'deep_link',
            protocolHint: 'hiddify',
            actionValue: () async => 'hiddify://import/$hiddifyUrl#$label',
          ),
          await build(
            clientKey: 'sing_box',
            displayName: 'sing-box',
            actionType: 'deep_link',
            protocolHint: 'sing-box',
            actionValue: () async =>
                'sing-box://import-remote-profile?url=$singBoxUrl#$label',
          ),
        ];
      case 'macos':
        final clashUrl = await accessUrlFor('clash');
        final singBoxUrl = await accessUrlFor('sing-box');
        final surgeUrl = await accessUrlFor('clash');
        return <Map<String, dynamic>>[
          await build(
            clientKey: 'clash',
            displayName: 'Clash',
            actionType: 'copy_link',
            protocolHint: 'clash',
            actionValue: () async => clashUrl,
          ),
          await build(
            clientKey: 'sing_box',
            displayName: 'sing-box',
            actionType: 'deep_link',
            protocolHint: 'sing-box',
            actionValue: () async =>
                'sing-box://import-remote-profile?url=${Uri.encodeComponent(singBoxUrl)}#$label',
          ),
          await build(
            clientKey: 'surge',
            displayName: 'Surge',
            actionType: 'deep_link',
            protocolHint: 'surge',
            actionValue: () async =>
                'surge:///install-config?url=${Uri.encodeComponent(surgeUrl)}&name=$label',
          ),
        ];
      case 'windows':
        final clashUrl = await accessUrlFor('clash');
        final singBoxUrl = await accessUrlFor('sing-box');
        return <Map<String, dynamic>>[
          await build(
            clientKey: 'clash',
            displayName: 'Clash',
            actionType: 'deep_link',
            protocolHint: 'clash',
            actionValue: () async =>
                'clash://install-config?url=${Uri.encodeComponent(clashUrl)}&name=$label',
          ),
          await build(
            clientKey: 'sing_box',
            displayName: 'sing-box',
            actionType: 'copy_link',
            protocolHint: 'sing-box',
            actionValue: () async => singBoxUrl,
          ),
        ];
      default:
        return const <Map<String, dynamic>>[];
    }
  }

  String _subscriptionAccessUrl(Request request, String accessId) {
    final origin = _requestOrigin(request);
    return origin.replace(
      path: '/api/app/v1/client/subscription/$accessId',
      queryParameters: const <String, String>{},
    ).toString();
  }

  Future<_SubscriptionAccessContext> _subscriptionAccessContext(
    SessionRecord session,
  ) async {
    final ownerKey = session.ownerKey ?? await _resolveSessionOwnerKey(session);
    final generation = await sessionStore.readSubscriptionGeneration(ownerKey);
    return _SubscriptionAccessContext(
      ownerKey: ownerKey,
      generation: generation,
    );
  }

  Future<String> _resolveSessionOwnerKey(SessionRecord session) async {
    final profile = await _fetchProfileData(session);
    final ownerKey = _subscriptionOwnerKeyOrNull(profile);
    if (ownerKey != null) {
      return ownerKey;
    }
    throw StateError('subscription owner key unavailable');
  }

  String? _subscriptionOwnerKeyOrNull(Map<String, dynamic> profile) {
    final rawId = _trimmedOrNull(profile['id']?.toString());
    if (rawId != null) {
      return 'uid:$rawId';
    }
    final rawEmail = _trimmedOrNull(profile['email']?.toString());
    if (rawEmail != null) {
      return 'email:${rawEmail.toLowerCase()}';
    }
    return null;
  }

  Uri _requestOrigin(Request request) {
    final forwardedProto = request.headers['x-forwarded-proto'];
    final forwardedHost = request.headers['x-forwarded-host'];
    final host = forwardedHost ?? request.headers['host'];
    if (host != null && host.isNotEmpty) {
      return Uri(
        scheme: forwardedProto ?? request.requestedUri.scheme,
        host: host.split(':').first,
        port: host.contains(':') ? int.tryParse(host.split(':').last) : null,
      );
    }
    return request.requestedUri.replace(path: '', queryParameters: const {});
  }

  String _codeForStatus(int status) {
    return switch (status) {
      401 => 'auth.invalid',
      404 => 'route.not_found',
      502 => 'upstream.failed',
      _ => 'request.failed',
    };
  }

  String _codeForUpstreamError(
    UpstreamException error,
    int status,
    String? operation,
  ) {
    if (status == HttpStatus.badGateway) {
      return 'upstream.failed';
    }
    if (status == HttpStatus.unauthorized) {
      return 'auth.invalid';
    }
    if (status == HttpStatus.notFound) {
      return 'route.not_found';
    }
    if (status != HttpStatus.badRequest || operation == null) {
      return _codeForStatus(status);
    }
    return switch (operation) {
      'auth.login' => 'auth.invalid',
      'commerce.coupon' => 'commerce.coupon_invalid',
      'commerce.checkout' => 'commerce.payment_method_unavailable',
      'referrals.transfer' => 'referrals.no_withdrawable_commission',
      'referrals.withdrawal' => 'referrals.withdrawal_unavailable',
      'support.ticket.create' => 'support.ticket_invalid',
      'support.ticket.reply' => 'support.ticket_reply_unavailable',
      'support.ticket.close' => 'support.ticket_close_unavailable',
      'support.ticket.detail' => 'support.ticket_not_found',
      'rewards.redeem' => 'rewards.redeem_failed',
      _ => _codeForStatus(status),
    };
  }

  String _safeMessage(int status) {
    return switch (status) {
      401 => 'Authentication required',
      404 => 'Request failed',
      _ => 'Request failed',
    };
  }

  String _normalizeHelpLanguage(String? raw) {
    final value = raw?.trim().toLowerCase();
    if (value == null || value.isEmpty) {
      return 'zh-CN';
    }
    if (value.startsWith('zh')) {
      return 'zh-CN';
    }
    return 'en-US';
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
}

String? _trimmedOrNull(Object? raw) {
  final value = raw?.toString().trim();
  if (value == null || value.isEmpty) return null;
  return value;
}

class _SubscriptionAccessContext {
  const _SubscriptionAccessContext({
    required this.ownerKey,
    required this.generation,
  });

  final String ownerKey;
  final int generation;
}

class _AccountBootstrapPayload {
  const _AccountBootstrapPayload({
    required this.account,
    required this.config,
    required this.subscription,
  });

  final Map<String, dynamic> account;
  final Map<String, dynamic> config;
  final Map<String, dynamic> subscription;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'account': account,
        'config': config,
        'subscription': subscription,
      };
}

class _SubscriptionPayload {
  const _SubscriptionPayload({
    required this.subscription,
    this.subscribeUrl,
  });

  final Map<String, dynamic> subscription;
  final String? subscribeUrl;
}

class _TelegramBindingData {
  const _TelegramBindingData({
    this.bindUrl,
    this.bindCommand,
  });

  final String? bindUrl;
  final String? bindCommand;
}

class _TimedCacheEntry<T> {
  const _TimedCacheEntry({
    required this.value,
    required this.expiresAt,
  });

  final T value;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
