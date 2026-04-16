import 'dart:convert';

import 'package:app_api/app_api.dart';
import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  late Handler handler;
  late _FakeUpstreamApi upstreamApi;
  late MemorySessionStore sessionStore;

  setUp(() {
    upstreamApi = _FakeUpstreamApi();
    sessionStore = MemorySessionStore();
    handler = createAppApiHandler(
      config: ServiceConfig(
        upstreamBaseUri: Uri.parse('https://panel.example.test'),
        port: 8787,
        sessionTtl: const Duration(hours: 12),
        redisUrl: null,
        upstreamTimeout: const Duration(seconds: 20),
        requestJitterBase: Duration.zero,
        requestJitterSpread: Duration.zero,
      ),
      sessionStore: sessionStore,
      upstreamApi: upstreamApi,
      logger: Logger('test'),
    );
  });

  test('login returns opaque session token without upstream auth fields',
      () async {
    final response = await handler(
      Request(
        'POST',
        Uri.parse('http://localhost/api/app/v1/session/login'),
        body: jsonEncode(<String, dynamic>{
          'email': 'u@example.com',
          'password': 'secret',
        }),
      ),
    );

    expect(response.statusCode, 200);
    final payload =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    final data = payload['data'] as Map<String, dynamic>;
    final session = data['session'] as Map<String, dynamic>;

    expect(session['token'], isNotEmpty);
    expect(jsonEncode(payload).toLowerCase(), isNot(contains('auth_data')));
    expect(jsonEncode(payload).toLowerCase(), isNot(contains('xboard')));
  });

  test('register trims and forwards invite code to upstream', () async {
    final response = await handler(
      Request(
        'POST',
        Uri.parse('http://localhost/api/app/v1/session/register'),
        body: jsonEncode(<String, dynamic>{
          'email': 'new@example.com',
          'password': 'secret-pass',
          'invite_code': '  ABCDEFGH  ',
          'email_code': '  123456  ',
          'captcha_payload': '  captcha-token  ',
        }),
      ),
    );

    expect(response.statusCode, 200);
    expect(upstreamApi.registeredInviteCode, 'ABCDEFGH');
    expect(upstreamApi.registeredEmailCode, '123456');
    expect(upstreamApi.registeredRecaptchaData, 'captcha-token');
  });

  test('logout clears server session', () async {
    final session = await sessionStore.create(
      upstreamToken: 'upstream-token',
      upstreamAuth: 'Bearer upstream-auth',
      ttl: const Duration(hours: 1),
    );

    final response = await handler(
      Request(
        'DELETE',
        Uri.parse('http://localhost/api/app/v1/session/current'),
        headers: <String, String>{'authorization': 'Bearer ${session.id}'},
      ),
    );

    expect(response.statusCode, 200);
    final payload =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    expect(
      payload['data'],
      <String, dynamic>{'cleared': true},
    );

    final profileResponse = await handler(
      Request(
        'GET',
        Uri.parse('http://localhost/api/app/v1/account/profile'),
        headers: <String, String>{'authorization': 'Bearer ${session.id}'},
      ),
    );
    expect(profileResponse.statusCode, 401);
  });

  test('subscription summary does not expose upstream subscribe url', () async {
    final session = await sessionStore.create(
      upstreamToken: 'upstream-token',
      upstreamAuth: 'Bearer upstream-auth',
      ttl: const Duration(hours: 1),
    );

    final response = await handler(
      Request(
        'GET',
        Uri.parse('http://localhost/api/app/v1/account/subscription'),
        headers: <String, String>{'authorization': 'Bearer ${session.id}'},
      ),
    );

    expect(response.statusCode, 200);
    final payload =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    final encoded = jsonEncode(payload).toLowerCase();
    expect(encoded, isNot(contains('subscribe_url')));
    expect(encoded, contains('download_endpoint'));
  });

  test('catalog plans can be fetched without authentication', () async {
    final response = await handler(
      Request(
        'GET',
        Uri.parse('http://localhost/api/app/v1/catalog/plans'),
      ),
    );

    expect(response.statusCode, 200);
    final payload =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    final data = payload['data'] as Map<String, dynamic>;
    final items = data['items'] as List<dynamic>;
    expect(items, isNotEmpty);
    expect(
      (items.first as Map<String, dynamic>)['transfer_bytes'],
      10 * 1024 * 1024 * 1024,
    );
  });

  test('help knowledge list is grouped by category', () async {
    final session = await sessionStore.create(
      upstreamToken: 'upstream-token',
      upstreamAuth: 'Bearer upstream-auth',
      ttl: const Duration(hours: 1),
    );

    final response = await handler(
      Request(
        'GET',
        Uri.parse(
            'http://localhost/api/app/v1/content/help/articles?language=zh-CN'),
        headers: <String, String>{'authorization': 'Bearer ${session.id}'},
      ),
    );

    expect(response.statusCode, 200);
    final payload =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    final data = payload['data'] as Map<String, dynamic>;
    final categories = data['categories'] as List<dynamic>;
    expect(categories, hasLength(2));
    expect(
      categories.first,
      <String, dynamic>{
        'name': '客户端下载',
        'articles': <Map<String, dynamic>>[
          <String, dynamic>{
            'article_id': 11,
            'category': '客户端下载',
            'title': 'Windows 客户端',
            'updated_at': 1700000001,
          },
        ],
      },
    );
  });

  test('help knowledge detail exposes article html body', () async {
    final session = await sessionStore.create(
      upstreamToken: 'upstream-token',
      upstreamAuth: 'Bearer upstream-auth',
      ttl: const Duration(hours: 1),
    );

    final response = await handler(
      Request(
        'GET',
        Uri.parse(
            'http://localhost/api/app/v1/content/help/articles/11?language=zh-CN'),
        headers: <String, String>{'authorization': 'Bearer ${session.id}'},
      ),
    );

    expect(response.statusCode, 200);
    final payload =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    final data = payload['data'] as Map<String, dynamic>;
    expect(
      data['article'],
      <String, dynamic>{
        'article_id': 11,
        'category': '客户端下载',
        'title': 'Windows 客户端',
        'body_html': '<p>正文</p>',
        'updated_at': 1700000001,
      },
    );
  });

  test('help knowledge list returns empty categories when upstream is empty',
      () async {
    upstreamApi.helpArticleCategories = const <String, dynamic>{'data': []};
    final session = await sessionStore.create(
      upstreamToken: 'upstream-token',
      upstreamAuth: 'Bearer upstream-auth',
      ttl: const Duration(hours: 1),
    );

    final response = await handler(
      Request(
        'GET',
        Uri.parse(
            'http://localhost/api/app/v1/content/help/articles?language=en-US'),
        headers: <String, String>{'authorization': 'Bearer ${session.id}'},
      ),
    );

    expect(response.statusCode, 200);
    final payload =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    final data = payload['data'] as Map<String, dynamic>;
    expect(data['categories'], isEmpty);
  });

  test('help knowledge endpoints require authentication', () async {
    final response = await handler(
      Request(
        'GET',
        Uri.parse(
            'http://localhost/api/app/v1/content/help/articles?language=zh-CN'),
      ),
    );

    expect(response.statusCode, 401);
  });

  test('referral overview maps codes and metrics', () async {
    final session = await sessionStore.create(
      upstreamToken: 'upstream-token',
      upstreamAuth: 'Bearer upstream-auth',
      ttl: const Duration(hours: 1),
    );

    final response = await handler(
      Request(
        'GET',
        Uri.parse('http://localhost/api/app/v1/referrals/overview'),
        headers: <String, String>{'authorization': 'Bearer ${session.id}'},
      ),
    );

    expect(response.statusCode, 200);
    final payload =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    final data = payload['data'] as Map<String, dynamic>;
    expect(
      data['codes'],
      <Map<String, dynamic>>[
        <String, dynamic>{
          'code_id': 7,
          'owner_ref': 9,
          'invite_code': 'ABCDEFGH',
          'state_code': 0,
          'visit_count': 3,
          'created_at': 1700000000,
          'updated_at': 1700000001,
        },
      ],
    );
    expect(
      data['metrics'],
      <String, dynamic>{
        'registered_users': 2,
        'settled_amount': 1200,
        'pending_amount': 300,
        'rate_percent': 10,
        'withdrawable_amount': 900,
      },
    );
  });

  test('referral records maps commission log entries', () async {
    final session = await sessionStore.create(
      upstreamToken: 'upstream-token',
      upstreamAuth: 'Bearer upstream-auth',
      ttl: const Duration(hours: 1),
    );

    final response = await handler(
      Request(
        'GET',
        Uri.parse('http://localhost/api/app/v1/referrals/records'),
        headers: <String, String>{'authorization': 'Bearer ${session.id}'},
      ),
    );

    expect(response.statusCode, 200);
    final payload =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    final data = payload['data'] as Map<String, dynamic>;
    expect(
      data['items'],
      <Map<String, dynamic>>[
        <String, dynamic>{
          'record_id': 31,
          'amount': 450,
          'order_amount': 4500,
          'trade_ref': 'T20260414001',
          'created_at': 1700000020,
          'status_text': '已发放',
        },
      ],
    );
  });

  test('referral code generation returns created flag', () async {
    final session = await sessionStore.create(
      upstreamToken: 'upstream-token',
      upstreamAuth: 'Bearer upstream-auth',
      ttl: const Duration(hours: 1),
    );

    final response = await handler(
      Request(
        'POST',
        Uri.parse('http://localhost/api/app/v1/referrals/codes'),
        headers: <String, String>{'authorization': 'Bearer ${session.id}'},
      ),
    );

    expect(response.statusCode, 200);
    final payload =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    expect(payload['data'], <String, dynamic>{'created': true});
    expect(upstreamApi.inviteCodeGenerated, isTrue);
  });

  test('referral transfer forwards cents and returns refreshed balances',
      () async {
    final session = await sessionStore.create(
      upstreamToken: 'upstream-token',
      upstreamAuth: 'Bearer upstream-auth',
      ttl: const Duration(hours: 1),
    );

    final response = await handler(
      Request(
        'POST',
        Uri.parse('http://localhost/api/app/v1/referrals/transfer-to-balance'),
        headers: <String, String>{
          'authorization': 'Bearer ${session.id}',
          'content-type': 'application/json',
        },
        body: jsonEncode(<String, dynamic>{'amount_cents': 900}),
      ),
    );

    expect(response.statusCode, 200);
    final payload =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    final data = payload['data'] as Map<String, dynamic>;
    expect(data['transferred'], isTrue);
    expect(
      data['account'],
      containsPair('balance_amount', 1023),
    );
    expect(
      (data['referrals'] as Map<String, dynamic>)['metrics'],
      containsPair('withdrawable_amount', 0),
    );
    expect(upstreamApi.transferredCommissionCents, 900);
  });

  test('referral transfer requires authentication', () async {
    final response = await handler(
      Request(
        'POST',
        Uri.parse('http://localhost/api/app/v1/referrals/transfer-to-balance'),
        body: jsonEncode(<String, dynamic>{'amount_cents': 900}),
      ),
    );

    expect(response.statusCode, 401);
    expect(upstreamApi.transferredCommissionCents, 0);
  });

  test('account notification update forwards reminder flags', () async {
    final session = await sessionStore.create(
      upstreamToken: 'upstream-token',
      upstreamAuth: 'Bearer upstream-auth',
      ttl: const Duration(hours: 1),
    );

    final response = await handler(
      Request(
        'PATCH',
        Uri.parse('http://localhost/api/app/v1/account/notifications'),
        headers: <String, String>{
          'authorization': 'Bearer ${session.id}',
          'content-type': 'application/json',
        },
        body: jsonEncode(<String, dynamic>{
          'expiry': false,
          'traffic': true,
        }),
      ),
    );

    expect(response.statusCode, 200);
    expect(upstreamApi.updatedRemindExpire, isFalse);
    expect(upstreamApi.updatedRemindTraffic, isTrue);
    final payload =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    final data = payload['data'] as Map<String, dynamic>;
    expect(data['updated'], isTrue);
    expect(data['account'], containsPair('remind_expire', false));
    expect(data['account'], containsPair('remind_traffic', true));
  });

  test('password change forwards old and new password', () async {
    final session = await sessionStore.create(
      upstreamToken: 'upstream-token',
      upstreamAuth: 'Bearer upstream-auth',
      ttl: const Duration(hours: 1),
    );

    final response = await handler(
      Request(
        'POST',
        Uri.parse('http://localhost/api/app/v1/account/password/change'),
        headers: <String, String>{
          'authorization': 'Bearer ${session.id}',
          'content-type': 'application/json',
        },
        body: jsonEncode(<String, dynamic>{
          'old_password': 'old-secret',
          'new_password': 'new-secret',
        }),
      ),
    );

    expect(response.statusCode, 200);
    expect(upstreamApi.changedOldPassword, 'old-secret');
    expect(upstreamApi.changedNewPassword, 'new-secret');
  });

  test('subscription access link proxies content without upstream url exposure',
      () async {
    final session = await sessionStore.create(
      upstreamToken: 'upstream-token',
      upstreamAuth: 'Bearer upstream-auth',
      ttl: const Duration(hours: 1),
    );

    final response = await handler(
      Request(
        'POST',
        Uri.parse(
            'http://localhost/api/app/v1/account/subscription/access-link'),
        headers: <String, String>{
          'authorization': 'Bearer ${session.id}',
          'content-type': 'application/json',
          'host': 'localhost',
        },
        body: jsonEncode(<String, dynamic>{'flag': 'clash'}),
      ),
    );

    expect(response.statusCode, 200);
    final payload =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    final encoded = jsonEncode(payload).toLowerCase();
    expect(encoded, isNot(contains('subscribe_url')));
    expect(encoded, isNot(contains('xboard')));
    expect(encoded, isNot(contains('v2board')));
    expect(encoded, isNot(contains('flux')));
    expect(encoded, isNot(contains('capybara')));
    final data = payload['data'] as Map<String, dynamic>;
    final subscription = data['subscription'] as Map<String, dynamic>;
    final accessUrl = subscription['access_url'] as String;
    expect(accessUrl, contains('/api/app/v1/client/subscription/cl_'));

    final subscriptionResponse = await handler(
      Request('GET', Uri.parse(accessUrl)),
    );
    expect(subscriptionResponse.statusCode, 200);
    expect(await subscriptionResponse.readAsString(), 'vmess://test');
    expect(upstreamApi.fetchedSubscriptionFlag, 'clash');
  });

  test('subscription reset returns neutral access link only', () async {
    final session = await sessionStore.create(
      upstreamToken: 'upstream-token',
      upstreamAuth: 'Bearer upstream-auth',
      ttl: const Duration(hours: 1),
    );

    final response = await handler(
      Request(
        'POST',
        Uri.parse('http://localhost/api/app/v1/account/subscription/reset'),
        headers: <String, String>{
          'authorization': 'Bearer ${session.id}',
          'content-type': 'application/json',
        },
      ),
    );

    expect(response.statusCode, 200);
    expect(upstreamApi.subscriptionSecurityReset, isTrue);
    final payload =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    final encoded = jsonEncode(payload).toLowerCase();
    expect(encoded, isNot(contains('subscribe_url')));
    expect(encoded, contains('/api/app/v1/client/subscription/'));
  });

  test('client downloads maps configured platform urls', () async {
    final session = await sessionStore.create(
      upstreamToken: 'upstream-token',
      upstreamAuth: 'Bearer upstream-auth',
      ttl: const Duration(hours: 1),
    );

    final response = await handler(
      Request(
        'GET',
        Uri.parse('http://localhost/api/app/v1/client/downloads'),
        headers: <String, String>{'authorization': 'Bearer ${session.id}'},
      ),
    );

    expect(response.statusCode, 200);
    final payload =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    final items =
        (payload['data'] as Map<String, dynamic>)['items'] as List<dynamic>;
    expect(items, hasLength(4));
    expect(items.first, containsPair('platform', 'windows'));
    expect(items.first, containsPair('available', true));
    expect(items.last, containsPair('platform', 'ios'));
    expect(items.last, containsPair('available', false));
  });

  test('withdrawal request forwards method and account', () async {
    final session = await sessionStore.create(
      upstreamToken: 'upstream-token',
      upstreamAuth: 'Bearer upstream-auth',
      ttl: const Duration(hours: 1),
    );

    final response = await handler(
      Request(
        'POST',
        Uri.parse('http://localhost/api/app/v1/referrals/withdrawals'),
        headers: <String, String>{
          'authorization': 'Bearer ${session.id}',
          'content-type': 'application/json',
        },
        body: jsonEncode(<String, dynamic>{
          'withdraw_method': ' alipay ',
          'withdraw_account': ' user@example.com ',
        }),
      ),
    );

    expect(response.statusCode, 200);
    expect(upstreamApi.withdrawalMethod, 'alipay');
    expect(upstreamApi.withdrawalAccount, 'user@example.com');
  });

  test('withdrawal request requires authentication', () async {
    final response = await handler(
      Request(
        'POST',
        Uri.parse('http://localhost/api/app/v1/referrals/withdrawals'),
        body: jsonEncode(<String, dynamic>{
          'withdraw_method': 'alipay',
          'withdraw_account': 'user@example.com',
        }),
      ),
    );

    expect(response.statusCode, 401);
    expect(upstreamApi.withdrawalMethod, isNull);
  });

  test('coupon validation forwards plan period and coupon code', () async {
    final session = await sessionStore.create(
      upstreamToken: 'upstream-token',
      upstreamAuth: 'Bearer upstream-auth',
      ttl: const Duration(hours: 1),
    );

    final response = await handler(
      Request(
        'POST',
        Uri.parse('http://localhost/api/app/v1/commerce/coupons/validate'),
        headers: <String, String>{
          'authorization': 'Bearer ${session.id}',
          'content-type': 'application/json',
        },
        body: jsonEncode(<String, dynamic>{
          'plan_id': 8,
          'period_key': 'month_price',
          'coupon_code': ' SAVE10 ',
        }),
      ),
    );

    expect(response.statusCode, 200);
    final payload =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    final data = payload['data'] as Map<String, dynamic>;
    expect(data['valid'], isTrue);
    expect((data['coupon'] as Map<String, dynamic>)['code'], 'SAVE10');
    expect(upstreamApi.validatedCouponPlanId, 8);
    expect(upstreamApi.validatedCouponPeriod, 'month_price');
    expect(upstreamApi.validatedCouponCode, 'SAVE10');
  });

  test('order detail maps public order fields', () async {
    final session = await sessionStore.create(
      upstreamToken: 'upstream-token',
      upstreamAuth: 'Bearer upstream-auth',
      ttl: const Duration(hours: 1),
    );

    final response = await handler(
      Request(
        'GET',
        Uri.parse('http://localhost/api/app/v1/commerce/orders/T20260414001'),
        headers: <String, String>{'authorization': 'Bearer ${session.id}'},
      ),
    );

    expect(response.statusCode, 200);
    final payload =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    final data = payload['data'] as Map<String, dynamic>;
    final order = data['order'] as Map<String, dynamic>;
    expect(order['order_ref'], 'T20260414001');
    expect(order['period_key'], 'month_price');
    expect(order['amount_total'], 380);
    expect(order['amount_handling'], 10);
    expect(order['amount_payable'], 390);
    final plan = order['plan'] as Map<String, dynamic>;
    expect(plan['title'], 'Starter');
    expect(plan['transfer_bytes'], 10 * 1024 * 1024 * 1024);
    expect(upstreamApi.fetchedOrderDetailRef, 'T20260414001');
  });

  test('checkout action maps redirect qr and completed results', () async {
    final session = await sessionStore.create(
      upstreamToken: 'upstream-token',
      upstreamAuth: 'Bearer upstream-auth',
      ttl: const Duration(hours: 1),
    );

    Future<Map<String, dynamic>> checkout(Map<String, dynamic> result) async {
      upstreamApi.checkoutResult = result;
      final response = await handler(
        Request(
          'POST',
          Uri.parse(
              'http://localhost/api/app/v1/commerce/orders/T20260414001/checkout'),
          headers: <String, String>{
            'authorization': 'Bearer ${session.id}',
            'content-type': 'application/json',
          },
          body: jsonEncode(<String, dynamic>{'payment_method_id': 2}),
        ),
      );
      expect(response.statusCode, 200);
      final payload =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      return (payload['data'] as Map<String, dynamic>)['action']
          as Map<String, dynamic>;
    }

    expect(
      await checkout(<String, dynamic>{
        'type': 1,
        'data': 'https://pay.example.test/checkout',
      }),
      containsPair('kind', 'redirect'),
    );
    expect(
      await checkout(<String, dynamic>{'type': 0, 'data': 'qr-payload'}),
      containsPair('kind', 'qr_code'),
    );
    expect(
      await checkout(<String, dynamic>{'type': -1, 'data': true}),
      containsPair('kind', 'completed'),
    );
  });
}

class _FakeUpstreamApi implements UpstreamApi {
  bool inviteCodeGenerated = false;
  int transferredCommissionCents = 0;
  int balanceCents = 123;
  int withdrawableCommissionCents = 900;
  int? validatedCouponPlanId;
  String? validatedCouponPeriod;
  String? validatedCouponCode;
  String? fetchedOrderDetailRef;
  String? registeredInviteCode;
  String? registeredEmailCode;
  String? registeredRecaptchaData;
  bool? updatedRemindExpire;
  bool? updatedRemindTraffic;
  String? changedOldPassword;
  String? changedNewPassword;
  bool subscriptionSecurityReset = false;
  String? fetchedSubscriptionFlag;
  String? withdrawalMethod;
  String? withdrawalAccount;
  Map<String, dynamic> checkoutResult = <String, dynamic>{
    'type': 0,
    'data': true,
  };

  Map<String, dynamic> helpArticleCategories = <String, dynamic>{
    'data': <String, dynamic>{
      '客户端下载': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 11,
          'category': '客户端下载',
          'title': 'Windows 客户端',
          'updated_at': 1700000001,
        },
      ],
      '订阅教程': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 12,
          'category': '订阅教程',
          'title': '如何导入订阅',
          'updated_at': 1700000002,
        },
      ],
    },
  };

  Map<String, dynamic> helpArticleDetail = <String, dynamic>{
    'data': <String, dynamic>{
      'id': 11,
      'category': '客户端下载',
      'title': 'Windows 客户端',
      'body': '<p>正文</p>',
      'updated_at': 1700000001,
    },
  };

  @override
  Future<void> cancelOrder(UpstreamAuth auth,
      {required String tradeNo}) async {}

  @override
  Future<int> checkOrder(UpstreamAuth auth, {required String tradeNo}) async =>
      1;

  @override
  Future<Map<String, dynamic>> checkoutOrder(
    UpstreamAuth auth, {
    required String tradeNo,
    required int methodId,
  }) async {
    return checkoutResult;
  }

  @override
  Future<String> createOrder(
    UpstreamAuth auth, {
    required int planId,
    required String period,
    String? couponCode,
  }) async =>
      '202600000001';

  @override
  Future<Map<String, dynamic>> validateCoupon(
    UpstreamAuth auth, {
    required int planId,
    required String period,
    required String couponCode,
  }) async {
    validatedCouponPlanId = planId;
    validatedCouponPeriod = period;
    validatedCouponCode = couponCode;
    return <String, dynamic>{
      'data': <String, dynamic>{
        'id': 99,
        'code': couponCode,
        'name': 'Test Coupon',
        'type': 1,
        'value': 100,
        'limit_period': <String>[period],
        'limit_plan_ids': <String>['$planId'],
      },
    };
  }

  @override
  Future<Map<String, dynamic>> fetchOrderDetail(
    UpstreamAuth auth, {
    required String tradeNo,
  }) async {
    fetchedOrderDetailRef = tradeNo;
    return <String, dynamic>{
      'data': <String, dynamic>{
        'trade_no': tradeNo,
        'status': 0,
        'period': 'month_price',
        'total_amount': 380,
        'discount_amount': 0,
        'balance_amount': 0,
        'refund_amount': 0,
        'surplus_amount': 0,
        'handling_amount': 10,
        'created_at': 1776150000,
        'updated_at': 1776150001,
        'plan': <String, dynamic>{
          'id': 1,
          'name': 'Starter',
          'transfer_enable': 10 * 1024 * 1024 * 1024,
          'month_price': 380,
        },
        'payment': <String, dynamic>{
          'id': 2,
          'name': 'Pay',
          'payment': 'EPay',
          'icon': null,
          'handling_fee_fixed': 10,
          'handling_fee_percent': 0,
        },
      },
    };
  }

  @override
  Future<Map<String, dynamic>> fetchClientConfig(UpstreamAuth auth) async =>
      <String, dynamic>{
        'data': <String, dynamic>{'theme': 'neutral'}
      };

  @override
  Future<Map<String, dynamic>> fetchClientVersion(UpstreamAuth auth) async =>
      <String, dynamic>{
        'data': <String, dynamic>{
          'windows_version': '1.0.0',
          'windows_download_url': 'https://download.example.test/windows.exe',
          'macos_version': '1.0.0',
          'macos_download_url': 'https://download.example.test/macos.dmg',
          'android_version': '1.0.0',
          'android_download_url': 'https://download.example.test/android.apk',
        }
      };

  @override
  Future<Map<String, dynamic>> fetchHelpArticleDetail(
    UpstreamAuth auth, {
    required int articleId,
    required String language,
  }) async =>
      helpArticleDetail;

  @override
  Future<Map<String, dynamic>> fetchHelpArticles(
    UpstreamAuth auth, {
    required String language,
  }) async =>
      helpArticleCategories;

  @override
  Future<Map<String, dynamic>> fetchGuestConfig() async => <String, dynamic>{
        'data': <String, dynamic>{'is_email_verify': 1}
      };

  @override
  Future<List<Map<String, dynamic>>> fetchGuestPlans() async =>
      <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 1,
          'name': 'Starter',
          'transfer_enable': 10 * 1024 * 1024 * 1024,
          'month_price': 1000,
        },
      ];

  @override
  Future<Map<String, dynamic>> fetchInviteOverview(UpstreamAuth auth) async =>
      <String, dynamic>{
        'data': <String, dynamic>{
          'codes': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 7,
              'user_id': 9,
              'code': 'ABCDEFGH',
              'status': 0,
              'pv': 3,
              'created_at': 1700000000,
              'updated_at': 1700000001,
            },
          ],
          'stat': <int>[2, 1200, 300, 10, withdrawableCommissionCents],
        },
      };

  @override
  Future<List<Map<String, dynamic>>> fetchInviteRecords(
          UpstreamAuth auth) async =>
      <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 31,
          'get_amount': 450,
          'order_amount': 4500,
          'trade_no': 'T20260414001',
          'created_at': 1700000020,
          'status_text': '已发放',
        },
      ];

  @override
  Future<List<Map<String, dynamic>>> fetchNotices(UpstreamAuth auth) async =>
      <Map<String, dynamic>>[];

  @override
  Future<List<Map<String, dynamic>>> fetchOrders(UpstreamAuth auth) async =>
      <Map<String, dynamic>>[];

  @override
  Future<List<Map<String, dynamic>>> fetchPaymentMethods(
          UpstreamAuth auth) async =>
      <Map<String, dynamic>>[];

  @override
  Future<List<Map<String, dynamic>>> fetchPlans(UpstreamAuth auth) async =>
      <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 1,
          'name': 'Starter',
          'transfer_enable': 10 * 1024 * 1024 * 1024,
          'month_price': 1000,
        },
      ];

  @override
  Future<Map<String, dynamic>> fetchSubscriptionSummary(
          UpstreamAuth auth) async =>
      <String, dynamic>{
        'data': <String, dynamic>{
          'u': 10,
          'd': 20,
          'transfer_enable': 30,
          'expired_at': 1700000000,
          'reset_day': 7,
          'subscribe_url': 'https://panel.example.test/s/token',
        },
      };

  @override
  Future<String> fetchSubscriptionContent(UpstreamAuth auth,
      {String? flag}) async {
    fetchedSubscriptionFlag = flag;
    return 'vmess://test';
  }

  @override
  Future<Map<String, dynamic>> fetchUserConfig(UpstreamAuth auth) async =>
      <String, dynamic>{
        'data': <String, dynamic>{
          'currency_symbol': '¥',
          'withdraw_methods': <String>['alipay', 'wechat'],
          'withdraw_close': 0,
        }
      };

  @override
  Future<Map<String, dynamic>> fetchUserProfile(UpstreamAuth auth) async =>
      <String, dynamic>{
        'data': <String, dynamic>{
          'email': 'u@example.com',
          'balance': balanceCents,
          'plan_id': 1,
          'transfer_enable': 1024,
          'expired_at': 1700000000,
          'avatar_url': 'https://example.com/avatar.png',
          'uuid': 'uuid-1',
          'remind_expire':
              updatedRemindExpire == null ? 1 : (updatedRemindExpire! ? 1 : 0),
          'remind_traffic': updatedRemindTraffic == null
              ? 0
              : (updatedRemindTraffic! ? 1 : 0),
        },
      };

  @override
  Future<void> generateInviteCode(UpstreamAuth auth) async {
    inviteCodeGenerated = true;
  }

  @override
  Future<UpstreamAuth> login({
    required String email,
    required String password,
  }) async =>
      UpstreamAuth(token: 'panel-token', authorization: 'Bearer panel-auth');

  @override
  Future<UpstreamAuth> register({
    required String email,
    required String password,
    String? inviteCode,
    String? emailCode,
    String? recaptchaData,
  }) async {
    registeredInviteCode = inviteCode;
    registeredEmailCode = emailCode;
    registeredRecaptchaData = recaptchaData;
    return UpstreamAuth(
        token: 'panel-token', authorization: 'Bearer panel-auth');
  }

  @override
  Future<Map<String, dynamic>> redeemGiftCard(
    UpstreamAuth auth, {
    required String code,
  }) async =>
      <String, dynamic>{
        'data': <String, dynamic>{
          'message': 'ok',
          'rewards': <String, dynamic>{'amount': 1},
        },
      };

  @override
  Future<void> updateUserNotifications(
    UpstreamAuth auth, {
    required bool remindExpire,
    required bool remindTraffic,
  }) async {
    updatedRemindExpire = remindExpire;
    updatedRemindTraffic = remindTraffic;
  }

  @override
  Future<void> changePassword(
    UpstreamAuth auth, {
    required String oldPassword,
    required String newPassword,
  }) async {
    changedOldPassword = oldPassword;
    changedNewPassword = newPassword;
  }

  @override
  Future<void> resetSubscriptionSecurity(UpstreamAuth auth) async {
    subscriptionSecurityReset = true;
  }

  @override
  Future<void> requestCommissionWithdrawal(
    UpstreamAuth auth, {
    required String method,
    required String account,
  }) async {
    withdrawalMethod = method;
    withdrawalAccount = account;
  }

  @override
  Future<void> transferCommissionToBalance(
    UpstreamAuth auth, {
    required int amountCents,
  }) async {
    transferredCommissionCents = amountCents;
    balanceCents += amountCents;
    withdrawableCommissionCents -= amountCents;
  }

  @override
  Future<void> resetPassword({
    required String email,
    required String emailCode,
    required String password,
  }) async {}

  @override
  Future<void> sendEmailCode({
    required String email,
    String? recaptchaData,
  }) async {}
}
