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
        checkoutAllowedOrigins: ServiceConfig.parseCheckoutAllowedOrigins(null),
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

  test(
      'subscription summary falls back to profile when upstream is transiently unavailable',
      () async {
    upstreamApi.subscriptionSummaryFailure = UpstreamException(
      statusCode: 500,
      message: 'upstream subscribe not ready',
    );
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
    final data = payload['data'] as Map<String, dynamic>;
    final subscription = data['subscription'] as Map<String, dynamic>;

    expect(subscription['total_bytes'], 1024);
    expect(subscription['expiry_at'], 1700000000);
    expect(subscription['plan_id'], 1);
    expect(jsonEncode(payload).toLowerCase(), isNot(contains('subscribe_url')));
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

  test('guest config includes cache headers for Cloudflare edge caching',
      () async {
    final response = await handler(
      Request(
        'GET',
        Uri.parse('http://localhost/api/app/v1/public/config'),
      ),
    );

    expect(response.statusCode, 200);
    expect(
      response.headers['cache-control'],
      'public, s-maxage=60, stale-while-revalidate=300',
    );
    final payload =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    final data = payload['data'] as Map<String, dynamic>;
    expect(
      data['config'],
      containsPair('email_verification_required', 1),
    );
  });

  test('catalog plans normalize small GB transfer values into bytes', () async {
    upstreamApi.guestPlansResponse = <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 2,
        'name': 'Compact',
        'transfer_enable': 2,
        'month_price': 800,
      },
    ];

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
    expect(items, hasLength(1));
    expect(
      (items.first as Map<String, dynamic>)['transfer_bytes'],
      2 * 1024 * 1024 * 1024,
    );
  });

  test('web bootstrap aggregates home payload in a single app_api request',
      () async {
    final session = await sessionStore.create(
      upstreamToken: 'upstream-token',
      upstreamAuth: 'Bearer upstream-auth',
      ownerKey: 'email:u@example.com',
      ttl: const Duration(hours: 1),
    );
    upstreamApi.noticesResponse = <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 99,
        'title': '维护通知',
        'content': '今晚维护',
        'created_at': 1700000100,
      },
    ];

    final response = await handler(
      Request(
        'GET',
        Uri.parse('http://localhost/api/app/v1/web/bootstrap'),
        headers: <String, String>{'authorization': 'Bearer ${session.id}'},
      ),
    );

    expect(response.statusCode, 200);
    final payload =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    final data = payload['data'] as Map<String, dynamic>;
    expect(data['account'], isA<Map<String, dynamic>>());
    expect(data['subscription'], isA<Map<String, dynamic>>());
    expect(data['config'], isA<Map<String, dynamic>>());
    expect(data['plans'], isA<List<dynamic>>());
    expect(data['notices'], isA<List<dynamic>>());
    expect(upstreamApi.fetchUserProfileCalls, 1);
    expect(upstreamApi.fetchUserConfigCalls, 1);
    expect(upstreamApi.fetchSubscriptionSummaryCalls, 1);
    expect(upstreamApi.fetchPlansCalls, 1);
    expect(upstreamApi.fetchNoticesCalls, 1);
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

  test('help knowledge responses reuse cached upstream payloads', () async {
    final session = await sessionStore.create(
      upstreamToken: 'upstream-token',
      upstreamAuth: 'Bearer upstream-auth',
      ttl: const Duration(hours: 1),
    );

    final listUri = Uri.parse(
        'http://localhost/api/app/v1/content/help/articles?language=zh-CN');
    final detailUri = Uri.parse(
      'http://localhost/api/app/v1/content/help/articles/11?language=zh-CN',
    );

    final firstList = await handler(
      Request(
        'GET',
        listUri,
        headers: <String, String>{'authorization': 'Bearer ${session.id}'},
      ),
    );
    final secondList = await handler(
      Request(
        'GET',
        listUri,
        headers: <String, String>{'authorization': 'Bearer ${session.id}'},
      ),
    );
    final firstDetail = await handler(
      Request(
        'GET',
        detailUri,
        headers: <String, String>{'authorization': 'Bearer ${session.id}'},
      ),
    );
    final secondDetail = await handler(
      Request(
        'GET',
        detailUri,
        headers: <String, String>{'authorization': 'Bearer ${session.id}'},
      ),
    );

    expect(firstList.statusCode, 200);
    expect(secondList.statusCode, 200);
    expect(firstDetail.statusCode, 200);
    expect(secondDetail.statusCode, 200);
    expect(upstreamApi.fetchHelpArticlesCalls, 1);
    expect(upstreamApi.fetchHelpArticleDetailCalls, 1);
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

  test('referral records map commission log entries with pagination', () async {
    final session = await sessionStore.create(
      upstreamToken: 'upstream-token',
      upstreamAuth: 'Bearer upstream-auth',
      ttl: const Duration(hours: 1),
    );

    final response = await handler(
      Request(
        'GET',
        Uri.parse(
            'http://localhost/api/app/v1/referrals/records?page=2&page_size=10'),
        headers: <String, String>{'authorization': 'Bearer ${session.id}'},
      ),
    );

    expect(response.statusCode, 200);
    expect(upstreamApi.inviteRecordsPage, 2);
    expect(upstreamApi.inviteRecordsPageSize, 10);
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
    expect(data['page'], 2);
    expect(data['page_size'], 10);
    expect(data['total'], 12);
    expect(data['has_more'], isFalse);
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

  test('referral transfer rejects amount above available commission', () async {
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
        body: jsonEncode(<String, dynamic>{'amount_cents': 901}),
      ),
    );

    expect(response.statusCode, 400);
    final payload =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    expect(
      ((payload['error'] as Map<String, dynamic>)['code']),
      'referrals.transfer_amount_invalid',
    );
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

  test('account preferences stay lightweight without telegram binding fetches',
      () async {
    final session = await sessionStore.create(
      upstreamToken: 'upstream-token',
      upstreamAuth: 'Bearer upstream-auth',
      ttl: const Duration(hours: 1),
    );

    final response = await handler(
      Request(
        'GET',
        Uri.parse('http://localhost/api/app/v1/account/preferences'),
        headers: <String, String>{'authorization': 'Bearer ${session.id}'},
      ),
    );

    expect(response.statusCode, 200);
    final payload =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    final config = ((payload['data'] as Map<String, dynamic>)['config']
        as Map<String, dynamic>);
    expect(config['telegram_enabled'], 1);
    expect(config['telegram_discuss_link'], 'https://t.me/capybara_group');
    expect(config['telegram_bind_url'], isNull);
    expect(config['telegram_bind_command'], isNull);
    expect(upstreamApi.fetchUserProfileCalls, 0);
    expect(upstreamApi.fetchTelegramBotInfoCalls, 0);
    expect(upstreamApi.fetchSubscriptionSummaryCalls, 0);
  });

  test('account bootstrap exposes telegram binding helpers', () async {
    final session = await sessionStore.create(
      upstreamToken: 'upstream-token',
      upstreamAuth: 'Bearer upstream-auth',
      ownerKey: 'email:u@example.com',
      ttl: const Duration(hours: 1),
    );

    final response = await handler(
      Request(
        'GET',
        Uri.parse('http://localhost/api/app/v1/account/bootstrap'),
        headers: <String, String>{'authorization': 'Bearer ${session.id}'},
      ),
    );

    expect(response.statusCode, 200);
    final payload =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    final config = ((payload['data'] as Map<String, dynamic>)['config']
        as Map<String, dynamic>);
    expect(config['telegram_bind_url'], 'https://t.me/capybara_bot');
    expect(
      config['telegram_bind_command'],
      '/bind https://panel.example.test/s/token',
    );
  });

  test('client import options return platform-specific actions', () async {
    final session = await sessionStore.create(
      upstreamToken: 'upstream-token',
      upstreamAuth: 'Bearer upstream-auth',
      ownerKey: 'email:u@example.com',
      ttl: const Duration(hours: 1),
    );

    final response = await handler(
      Request(
        'GET',
        Uri.parse(
            'http://localhost/api/app/v1/client/import-options?platform=ios'),
        headers: <String, String>{'authorization': 'Bearer ${session.id}'},
      ),
    );

    expect(response.statusCode, 200);
    final payload =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    final items =
        ((payload['data'] as Map<String, dynamic>)['items'] as List<dynamic>);
    expect(items, hasLength(2));
    expect((items.first as Map<String, dynamic>)['client_key'], 'shadowrocket');
    expect(items.first['action_type'], 'deep_link');
    expect(upstreamApi.fetchUserProfileCalls, 0);
    expect(upstreamApi.fetchSubscriptionSummaryCalls, 1);
  });

  test('client version and downloads share cached upstream version payload',
      () async {
    final session = await sessionStore.create(
      upstreamToken: 'upstream-token',
      upstreamAuth: 'Bearer upstream-auth',
      ttl: const Duration(hours: 1),
    );

    final versionResponse = await handler(
      Request(
        'GET',
        Uri.parse('http://localhost/api/app/v1/client/version'),
        headers: <String, String>{'authorization': 'Bearer ${session.id}'},
      ),
    );
    final downloadsResponse = await handler(
      Request(
        'GET',
        Uri.parse('http://localhost/api/app/v1/client/downloads'),
        headers: <String, String>{'authorization': 'Bearer ${session.id}'},
      ),
    );

    expect(versionResponse.statusCode, 200);
    expect(downloadsResponse.statusCode, 200);
    expect(upstreamApi.fetchClientVersionCalls, 1);
  });

  test('client import options require active subscription', () async {
    upstreamApi.subscriptionSummary = <String, dynamic>{
      'data': <String, dynamic>{
        'u': 0,
        'd': 0,
        'transfer_enable': 0,
        'expired_at': 0,
        'reset_day': 0,
        'subscribe_url': '',
      },
    };
    final session = await sessionStore.create(
      upstreamToken: 'upstream-token',
      upstreamAuth: 'Bearer upstream-auth',
      ttl: const Duration(hours: 1),
    );

    final response = await handler(
      Request(
        'GET',
        Uri.parse(
            'http://localhost/api/app/v1/client/import-options?platform=ios'),
        headers: <String, String>{'authorization': 'Bearer ${session.id}'},
      ),
    );

    expect(response.statusCode, 400);
    final payload =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    expect(
      ((payload['error'] as Map<String, dynamic>)['code']),
      'subscription.required',
    );
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

  test('subscription reset invalidates previously issued relay links',
      () async {
    final session = await sessionStore.create(
      upstreamToken: 'upstream-token',
      upstreamAuth: 'Bearer upstream-auth',
      ttl: const Duration(hours: 1),
    );

    final initialResponse = await handler(
      Request(
        'POST',
        Uri.parse(
            'http://localhost/api/app/v1/account/subscription/access-link'),
        headers: <String, String>{
          'authorization': 'Bearer ${session.id}',
          'content-type': 'application/json',
        },
      ),
    );

    expect(initialResponse.statusCode, 200);
    final initialPayload = jsonDecode(await initialResponse.readAsString())
        as Map<String, dynamic>;
    final initialData = initialPayload['data'] as Map<String, dynamic>;
    final initialSubscription =
        initialData['subscription'] as Map<String, dynamic>;
    final initialAccessUrl = initialSubscription['access_url'] as String;

    final resetResponse = await handler(
      Request(
        'POST',
        Uri.parse('http://localhost/api/app/v1/account/subscription/reset'),
        headers: <String, String>{
          'authorization': 'Bearer ${session.id}',
          'content-type': 'application/json',
        },
      ),
    );

    expect(resetResponse.statusCode, 200);
    final resetPayload =
        jsonDecode(await resetResponse.readAsString()) as Map<String, dynamic>;
    final resetData = resetPayload['data'] as Map<String, dynamic>;
    final resetSubscription = resetData['subscription'] as Map<String, dynamic>;
    final freshAccessUrl = resetSubscription['access_url'] as String;

    final staleResponse = await handler(
      Request('GET', Uri.parse(initialAccessUrl)),
    );
    expect(staleResponse.statusCode, 404);
    expect(
      jsonDecode(await staleResponse.readAsString()),
      <String, dynamic>{
        'error': <String, dynamic>{
          'code': 'subscription.unavailable',
          'message': 'Request failed',
        },
      },
    );

    final freshResponse = await handler(
      Request('GET', Uri.parse(freshAccessUrl)),
    );
    expect(freshResponse.statusCode, 200);
    expect(await freshResponse.readAsString(), 'vmess://test');
  });

  test('subscription access link requires an active subscription', () async {
    final session = await sessionStore.create(
      upstreamToken: 'upstream-token',
      upstreamAuth: 'Bearer upstream-auth',
      ttl: const Duration(hours: 1),
    );
    upstreamApi.subscriptionSummary = <String, dynamic>{
      'data': <String, dynamic>{
        'u': 0,
        'd': 0,
        'transfer_enable': 0,
        'subscribe_url': '',
      },
    };

    final response = await handler(
      Request(
        'POST',
        Uri.parse(
            'http://localhost/api/app/v1/account/subscription/access-link'),
        headers: <String, String>{
          'authorization': 'Bearer ${session.id}',
          'content-type': 'application/json',
        },
      ),
    );

    expect(response.statusCode, 400);
    final payload =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    expect(
      payload['error'],
      <String, dynamic>{
        'code': 'subscription.required',
        'message': 'Request failed',
      },
    );
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

  test('node status maps public fields', () async {
    final session = await sessionStore.create(
      upstreamToken: 'upstream-token',
      upstreamAuth: 'Bearer upstream-auth',
      ttl: const Duration(hours: 1),
    );

    final response = await handler(
      Request(
        'GET',
        Uri.parse('http://localhost/api/app/v1/client/nodes/status'),
        headers: <String, String>{'authorization': 'Bearer ${session.id}'},
      ),
    );

    expect(response.statusCode, 200);
    final payload =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    final items =
        (payload['data'] as Map<String, dynamic>)['items'] as List<dynamic>;
    expect(items, hasLength(1));
    expect(
      items.first,
      <String, dynamic>{
        'node_id': 101,
        'display_name': 'Sydney 01',
        'protocol_type': 'shadowsocks',
        'version': '1.0',
        'rate': 1.5,
        'tags': <String>['AU', 'Premium'],
        'is_online': true,
        'last_check_at': 1700000030,
      },
    );
  });

  test('traffic logs map upload download and charged amount', () async {
    final session = await sessionStore.create(
      upstreamToken: 'upstream-token',
      upstreamAuth: 'Bearer upstream-auth',
      ttl: const Duration(hours: 1),
    );

    final response = await handler(
      Request(
        'GET',
        Uri.parse('http://localhost/api/app/v1/account/traffic-logs'),
        headers: <String, String>{'authorization': 'Bearer ${session.id}'},
      ),
    );

    expect(response.statusCode, 200);
    final payload =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    final items =
        (payload['data'] as Map<String, dynamic>)['items'] as List<dynamic>;
    expect(items, hasLength(1));
    expect(
      items.first,
      <String, dynamic>{
        'uploaded_amount': 100,
        'downloaded_amount': 200,
        'charged_amount': 600,
        'rate_multiplier': 2.0,
        'recorded_at': 1700000040,
      },
    );
  });

  test('ticket list maps summary fields', () async {
    final session = await sessionStore.create(
      upstreamToken: 'upstream-token',
      upstreamAuth: 'Bearer upstream-auth',
      ttl: const Duration(hours: 1),
    );

    final response = await handler(
      Request(
        'GET',
        Uri.parse('http://localhost/api/app/v1/support/tickets'),
        headers: <String, String>{'authorization': 'Bearer ${session.id}'},
      ),
    );

    expect(response.statusCode, 200);
    final payload =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    final items =
        (payload['data'] as Map<String, dynamic>)['items'] as List<dynamic>;
    expect(items, hasLength(1));
    expect(
      items.first,
      <String, dynamic>{
        'ticket_id': 61,
        'subject': '登录问题',
        'priority_level': 1,
        'reply_state': 1,
        'state_code': 0,
        'created_at': 1700000050,
        'updated_at': 1700000060,
      },
    );
  });

  test('ticket detail maps messages timeline', () async {
    final session = await sessionStore.create(
      upstreamToken: 'upstream-token',
      upstreamAuth: 'Bearer upstream-auth',
      ttl: const Duration(hours: 1),
    );

    final response = await handler(
      Request(
        'GET',
        Uri.parse('http://localhost/api/app/v1/support/tickets/61'),
        headers: <String, String>{'authorization': 'Bearer ${session.id}'},
      ),
    );

    expect(response.statusCode, 200);
    final payload =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    final ticket = (payload['data'] as Map<String, dynamic>)['ticket']
        as Map<String, dynamic>;
    expect(ticket['ticket_id'], 61);
    expect(ticket['body'], '初始工单内容');
    expect(ticket['messages'], [
      <String, dynamic>{
        'message_id': 502,
        'ticket_id': 61,
        'is_mine': true,
        'body': '我这边无法登录',
        'created_at': 1700000062,
        'updated_at': 1700000062,
      },
      <String, dynamic>{
        'message_id': 503,
        'ticket_id': 61,
        'is_mine': false,
        'body': '您好，请尝试重置密码',
        'created_at': 1700000063,
        'updated_at': 1700000063,
      },
    ]);
  });

  test('create ticket forwards subject level and message', () async {
    final session = await sessionStore.create(
      upstreamToken: 'upstream-token',
      upstreamAuth: 'Bearer upstream-auth',
      ttl: const Duration(hours: 1),
    );

    final response = await handler(
      Request(
        'POST',
        Uri.parse('http://localhost/api/app/v1/support/tickets'),
        headers: <String, String>{
          'authorization': 'Bearer ${session.id}',
          'content-type': 'application/json',
        },
        body: jsonEncode(<String, dynamic>{
          'subject': ' 无法连接 ',
          'priority_level': 2,
          'message': ' 请帮我排查 ',
        }),
      ),
    );

    expect(response.statusCode, 200);
    expect(upstreamApi.createdTicketSubject, '无法连接');
    expect(upstreamApi.createdTicketLevel, 2);
    expect(upstreamApi.createdTicketMessage, '请帮我排查');
  });

  test('reply ticket forwards ticket id and message', () async {
    final session = await sessionStore.create(
      upstreamToken: 'upstream-token',
      upstreamAuth: 'Bearer upstream-auth',
      ttl: const Duration(hours: 1),
    );

    final response = await handler(
      Request(
        'POST',
        Uri.parse('http://localhost/api/app/v1/support/tickets/61/reply'),
        headers: <String, String>{
          'authorization': 'Bearer ${session.id}',
          'content-type': 'application/json',
        },
        body: jsonEncode(<String, dynamic>{
          'message': ' 我补充一下问题现象 ',
        }),
      ),
    );

    expect(response.statusCode, 200);
    expect(upstreamApi.repliedTicketId, 61);
    expect(upstreamApi.repliedTicketMessage, '我补充一下问题现象');
  });

  test('close ticket forwards ticket id', () async {
    final session = await sessionStore.create(
      upstreamToken: 'upstream-token',
      upstreamAuth: 'Bearer upstream-auth',
      ttl: const Duration(hours: 1),
    );

    final response = await handler(
      Request(
        'POST',
        Uri.parse('http://localhost/api/app/v1/support/tickets/61/close'),
        headers: <String, String>{
          'authorization': 'Bearer ${session.id}',
          'content-type': 'application/json',
        },
      ),
    );

    expect(response.statusCode, 200);
    expect(upstreamApi.closedTicketId, 61);
  });

  test('new support and node routes require authentication', () async {
    final endpoints = <String>[
      'http://localhost/api/app/v1/client/nodes/status',
      'http://localhost/api/app/v1/account/traffic-logs',
      'http://localhost/api/app/v1/support/tickets',
      'http://localhost/api/app/v1/support/tickets/61',
    ];

    for (final endpoint in endpoints) {
      final response = await handler(Request('GET', Uri.parse(endpoint)));
      expect(response.statusCode, 401, reason: endpoint);
    }
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

  test('create order maps pending order conflict to stable app error',
      () async {
    upstreamApi.createOrderFailure = UpstreamException(
      statusCode: 400,
      message:
          'У вас есть неоплаченный или ожидающий заказ, попробуйте позже или отмените его',
    );
    upstreamApi.fetchOrdersResponse = <Map<String, dynamic>>[
      <String, dynamic>{'status': 0, 'trade_no': '202600000001'},
    ];
    final session = await sessionStore.create(
      upstreamToken: 'upstream-token',
      upstreamAuth: 'Bearer upstream-auth',
      ttl: const Duration(hours: 1),
    );

    final response = await handler(
      Request(
        'POST',
        Uri.parse('http://localhost/api/app/v1/commerce/orders'),
        headers: <String, String>{
          'authorization': 'Bearer ${session.id}',
          'content-type': 'application/json',
        },
        body: jsonEncode(<String, dynamic>{
          'plan_id': 8,
          'period_key': 'month_price',
        }),
      ),
    );

    expect(response.statusCode, 409);
    final payload =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    expect(
      payload['error'],
      <String, dynamic>{
        'code': 'commerce.pending_order_exists',
        'message': 'Request failed',
      },
    );
  });

  test('create order keeps unrelated upstream failures generic', () async {
    upstreamApi.createOrderFailure = UpstreamException(
      statusCode: 400,
      message: 'Coupon failed',
    );
    upstreamApi.fetchOrdersResponse = <Map<String, dynamic>>[];
    final session = await sessionStore.create(
      upstreamToken: 'upstream-token',
      upstreamAuth: 'Bearer upstream-auth',
      ttl: const Duration(hours: 1),
    );

    final response = await handler(
      Request(
        'POST',
        Uri.parse('http://localhost/api/app/v1/commerce/orders'),
        headers: <String, String>{
          'authorization': 'Bearer ${session.id}',
          'content-type': 'application/json',
        },
        body: jsonEncode(<String, dynamic>{
          'plan_id': 8,
          'period_key': 'month_price',
        }),
      ),
    );

    expect(response.statusCode, 400);
    final payload =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    expect(
      payload['error'],
      <String, dynamic>{
        'code': 'request.failed',
        'message': 'Request failed',
      },
    );
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
    expect(order['amount_original'], 380);
    expect(order['amount_due_before_fee'], 380);
    expect(order['amount_due_after_fee'], 390);
    expect(order['amount_discount_applied'], 0);
    expect(order['amount_balance_used'], 0);
    expect(order['amount_surplus_credit'], 0);
    expect(order['amount_refund_value'], 0);
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
            'origin': 'https://www.kapi-net.com',
            'referer': 'https://www.kapi-net.com/purchase',
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
    expect(upstreamApi.checkoutOrigin, 'https://www.kapi-net.com');
    expect(upstreamApi.checkoutReferer, 'https://www.kapi-net.com/purchase');
    expect(
      await checkout(<String, dynamic>{'type': 0, 'data': 'qr-payload'}),
      containsPair('kind', 'qr_code'),
    );
    expect(
      await checkout(<String, dynamic>{'type': -1, 'data': true}),
      containsPair('kind', 'completed'),
    );
  });

  test('checkout source ignores untrusted origins and defaults to web origin',
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
            'https://api.kapi-net.com/api/app/v1/commerce/orders/T20260414001/checkout'),
        headers: <String, String>{
          'authorization': 'Bearer ${session.id}',
          'content-type': 'application/json',
          'origin': 'https://evil.example.test',
          'referer': 'https://evil.example.test/purchase',
        },
        body: jsonEncode(<String, dynamic>{'payment_method_id': 2}),
      ),
    );

    expect(response.statusCode, 200);
    expect(upstreamApi.checkoutOrigin, 'https://www.kapi-net.com');
    expect(upstreamApi.checkoutReferer, 'https://www.kapi-net.com/');
  });

  test('gift redeem returns ok only for upstream success payload', () async {
    final session = await sessionStore.create(
      upstreamToken: 'upstream-token',
      upstreamAuth: 'Bearer upstream-auth',
      ttl: const Duration(hours: 1),
    );

    final response = await handler(
      Request(
        'POST',
        Uri.parse('http://localhost/api/app/v1/rewards/redeem'),
        headers: <String, String>{
          'authorization': 'Bearer ${session.id}',
          'content-type': 'application/json',
        },
        body: jsonEncode(<String, dynamic>{'code': 'GIFT-001'}),
      ),
    );

    expect(response.statusCode, 200);
    final payload =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    expect(
      (payload['data'] as Map<String, dynamic>)['result'],
      <String, dynamic>{
        'ok': true,
        'message': 'ok',
        'rewards': <String, dynamic>{'amount': 1},
        'referral_rewards': null,
        'label': null,
      },
    );
  });

  test('gift redeem rejects malformed 2xx upstream payload', () async {
    upstreamApi.redeemGiftCardResponse = <String, dynamic>{
      'status': 'fail',
      'data': <String, dynamic>{'message': 'bad'},
    };
    final session = await sessionStore.create(
      upstreamToken: 'upstream-token',
      upstreamAuth: 'Bearer upstream-auth',
      ttl: const Duration(hours: 1),
    );

    final response = await handler(
      Request(
        'POST',
        Uri.parse('http://localhost/api/app/v1/rewards/redeem'),
        headers: <String, String>{
          'authorization': 'Bearer ${session.id}',
          'content-type': 'application/json',
        },
        body: jsonEncode(<String, dynamic>{'code': 'GIFT-001'}),
      ),
    );

    expect(response.statusCode, 400);
    final payload =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    expect(
      payload['error'],
      <String, dynamic>{
        'code': 'rewards.redeem_failed',
        'message': 'Request failed',
      },
    );
  });
}

class _FakeUpstreamApi implements UpstreamApi {
  bool inviteCodeGenerated = false;
  int transferredCommissionCents = 0;
  int balanceCents = 123;
  int withdrawableCommissionCents = 900;
  int fetchUserConfigCalls = 0;
  int fetchUserProfileCalls = 0;
  int fetchSubscriptionSummaryCalls = 0;
  int fetchPlansCalls = 0;
  int fetchNoticesCalls = 0;
  int fetchClientVersionCalls = 0;
  int fetchTelegramBotInfoCalls = 0;
  int fetchHelpArticlesCalls = 0;
  int fetchHelpArticleDetailCalls = 0;
  int inviteRecordsPage = 1;
  int inviteRecordsPageSize = 10;
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
  String? createdTicketSubject;
  int? createdTicketLevel;
  String? createdTicketMessage;
  int? repliedTicketId;
  String? repliedTicketMessage;
  int? closedTicketId;
  String? telegramId;
  Object? createOrderFailure;
  List<Map<String, dynamic>> guestPlansResponse = <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 1,
      'name': 'Starter',
      'transfer_enable': 10 * 1024 * 1024 * 1024,
      'month_price': 1000,
    },
  ];
  List<Map<String, dynamic>> plansResponse = <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 1,
      'name': 'Starter',
      'transfer_enable': 10 * 1024 * 1024 * 1024,
      'month_price': 1000,
    },
  ];
  Map<String, dynamic> orderDetailResponse = <String, dynamic>{
    'data': <String, dynamic>{
      'trade_no': 'T20260414001',
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
  List<Map<String, dynamic>> fetchOrdersResponse = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> noticesResponse = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> fetchServersResponse = <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 101,
      'type': 'shadowsocks',
      'version': '1.0',
      'name': 'Sydney 01',
      'rate': 1.5,
      'tags': <String>['AU', 'Premium'],
      'is_online': 1,
      'last_check_at': 1700000030,
    },
  ];
  List<Map<String, dynamic>> fetchTrafficLogsResponse = <Map<String, dynamic>>[
    <String, dynamic>{
      'u': 100,
      'd': 200,
      'record_at': 1700000040,
      'server_rate': 2.0,
    },
  ];
  List<Map<String, dynamic>> fetchTicketsResponse = <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 61,
      'level': 1,
      'reply_status': 1,
      'status': 0,
      'subject': '登录问题',
      'message': '初始工单内容',
      'created_at': 1700000050,
      'updated_at': 1700000060,
    },
  ];
  Map<String, dynamic> fetchTicketDetailResponse = <String, dynamic>{
    'id': 61,
    'level': 1,
    'reply_status': 1,
    'status': 0,
    'subject': '登录问题',
    'created_at': 1700000050,
    'updated_at': 1700000060,
    'message': <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 501,
        'ticket_id': 61,
        'is_me': 1,
        'message': '初始工单内容',
        'created_at': 1700000061,
        'updated_at': 1700000061,
      },
      <String, dynamic>{
        'id': 502,
        'ticket_id': 61,
        'is_me': 1,
        'message': '我这边无法登录',
        'created_at': 1700000062,
        'updated_at': 1700000062,
      },
      <String, dynamic>{
        'id': 503,
        'ticket_id': 61,
        'is_me': 0,
        'message': '您好，请尝试重置密码',
        'created_at': 1700000063,
        'updated_at': 1700000063,
      },
    ],
  };
  Map<String, dynamic> checkoutResult = <String, dynamic>{
    'type': 0,
    'data': true,
  };
  String? checkoutOrigin;
  String? checkoutReferer;
  Map<String, dynamic> subscriptionSummary = <String, dynamic>{
    'data': <String, dynamic>{
      'u': 10,
      'd': 20,
      'transfer_enable': 30,
      'expired_at': 1700000000,
      'reset_day': 7,
      'subscribe_url': 'https://panel.example.test/s/token',
    },
  };
  Object? subscriptionSummaryFailure;
  Map<String, dynamic> redeemGiftCardResponse = <String, dynamic>{
    'status': 'success',
    'data': <String, dynamic>{
      'message': 'ok',
      'rewards': <String, dynamic>{'amount': 1},
    },
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
    String? origin,
    String? referer,
  }) async {
    checkoutOrigin = origin;
    checkoutReferer = referer;
    return checkoutResult;
  }

  @override
  Future<String> createOrder(
    UpstreamAuth auth, {
    required int planId,
    required String period,
    String? couponCode,
  }) async {
    final failure = createOrderFailure;
    if (failure is Exception) {
      throw failure;
    }
    return '202600000001';
  }

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
    final response = Map<String, dynamic>.from(orderDetailResponse);
    final data =
        Map<String, dynamic>.from(response['data'] as Map? ?? const {});
    data['trade_no'] = tradeNo;
    response['data'] = data;
    return response;
  }

  @override
  Future<Map<String, dynamic>> fetchClientConfig(UpstreamAuth auth) async =>
      <String, dynamic>{
        'data': <String, dynamic>{'theme': 'neutral'}
      };

  @override
  Future<Map<String, dynamic>> fetchClientVersion(UpstreamAuth auth) async {
    fetchClientVersionCalls += 1;
    return <String, dynamic>{
      'data': <String, dynamic>{
        'windows_version': '1.0.0',
        'windows_download_url': 'https://download.example.test/windows.exe',
        'macos_version': '1.0.0',
        'macos_download_url': 'https://download.example.test/macos.dmg',
        'android_version': '1.0.0',
        'android_download_url': 'https://download.example.test/android.apk',
      }
    };
  }

  @override
  Future<Map<String, dynamic>> fetchTelegramBotInfo(UpstreamAuth auth) async {
    fetchTelegramBotInfoCalls += 1;
    return <String, dynamic>{
      'data': <String, dynamic>{'username': 'capybara_bot'},
    };
  }

  @override
  Future<Map<String, dynamic>> fetchHelpArticleDetail(
    UpstreamAuth auth, {
    required int articleId,
    required String language,
  }) async {
    fetchHelpArticleDetailCalls += 1;
    return helpArticleDetail;
  }

  @override
  Future<Map<String, dynamic>> fetchHelpArticles(
    UpstreamAuth auth, {
    required String language,
  }) async {
    fetchHelpArticlesCalls += 1;
    return helpArticleCategories;
  }

  @override
  Future<Map<String, dynamic>> fetchGuestConfig() async => <String, dynamic>{
        'data': <String, dynamic>{'is_email_verify': 1}
      };

  @override
  Future<List<Map<String, dynamic>>> fetchGuestPlans() async =>
      guestPlansResponse;

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
  Future<Map<String, dynamic>> fetchInviteRecords(
    UpstreamAuth auth, {
    required int page,
    required int pageSize,
  }) async {
    inviteRecordsPage = page;
    inviteRecordsPageSize = pageSize;
    return <String, dynamic>{
      'data': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 31,
          'get_amount': 450,
          'order_amount': 4500,
          'trade_no': 'T20260414001',
          'created_at': 1700000020,
          'status_text': '已发放',
        },
      ],
      'total': 12,
    };
  }

  @override
  Future<List<Map<String, dynamic>>> fetchNotices(UpstreamAuth auth) async {
    fetchNoticesCalls += 1;
    return noticesResponse;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchServers(UpstreamAuth auth) async =>
      fetchServersResponse;

  @override
  Future<List<Map<String, dynamic>>> fetchOrders(UpstreamAuth auth) async =>
      fetchOrdersResponse;

  @override
  Future<List<Map<String, dynamic>>> fetchPaymentMethods(
          UpstreamAuth auth) async =>
      <Map<String, dynamic>>[];

  @override
  Future<List<Map<String, dynamic>>> fetchPlans(UpstreamAuth auth) async {
    fetchPlansCalls += 1;
    return plansResponse;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchTickets(UpstreamAuth auth) async =>
      fetchTicketsResponse;

  @override
  Future<Map<String, dynamic>> fetchTicketDetail(
    UpstreamAuth auth, {
    required int ticketId,
  }) async =>
      fetchTicketDetailResponse;

  @override
  Future<List<Map<String, dynamic>>> fetchTrafficLogs(
          UpstreamAuth auth) async =>
      fetchTrafficLogsResponse;

  @override
  Future<Map<String, dynamic>> fetchSubscriptionSummary(
      UpstreamAuth auth) async {
    fetchSubscriptionSummaryCalls += 1;
    final failure = subscriptionSummaryFailure;
    if (failure is Exception) {
      throw failure;
    }
    return subscriptionSummary;
  }

  @override
  Future<String> fetchSubscriptionContent(UpstreamAuth auth,
      {String? flag}) async {
    fetchedSubscriptionFlag = flag;
    return 'vmess://test';
  }

  @override
  Future<Map<String, dynamic>> fetchUserConfig(UpstreamAuth auth) async {
    fetchUserConfigCalls += 1;
    return <String, dynamic>{
      'data': <String, dynamic>{
        'is_telegram': 1,
        'telegram_discuss_link': 'https://t.me/capybara_group',
        'currency_symbol': '¥',
        'withdraw_methods': <String>['alipay', 'wechat'],
        'withdraw_close': 0,
      }
    };
  }

  @override
  Future<Map<String, dynamic>> fetchUserProfile(UpstreamAuth auth) async {
    fetchUserProfileCalls += 1;
    return <String, dynamic>{
      'data': <String, dynamic>{
        'id': 42,
        'email': 'u@example.com',
        'balance': balanceCents,
        'plan_id': 1,
        'transfer_enable': 1024,
        'expired_at': 1700000000,
        'avatar_url': 'https://example.com/avatar.png',
        'uuid': 'uuid-1',
        'telegram_id': telegramId,
        'remind_expire':
            updatedRemindExpire == null ? 1 : (updatedRemindExpire! ? 1 : 0),
        'remind_traffic':
            updatedRemindTraffic == null ? 0 : (updatedRemindTraffic! ? 1 : 0),
      },
    };
  }

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
      redeemGiftCardResponse;

  @override
  Future<void> createTicket(
    UpstreamAuth auth, {
    required String subject,
    required int level,
    required String message,
  }) async {
    createdTicketSubject = subject;
    createdTicketLevel = level;
    createdTicketMessage = message;
  }

  @override
  Future<void> replyTicket(
    UpstreamAuth auth, {
    required int ticketId,
    required String message,
  }) async {
    repliedTicketId = ticketId;
    repliedTicketMessage = message;
  }

  @override
  Future<void> closeTicket(
    UpstreamAuth auth, {
    required int ticketId,
  }) async {
    closedTicketId = ticketId;
  }

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
