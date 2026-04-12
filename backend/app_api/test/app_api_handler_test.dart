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

  test('login returns opaque session token without upstream auth fields', () async {
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
    final payload = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    final data = payload['data'] as Map<String, dynamic>;
    final session = data['session'] as Map<String, dynamic>;

    expect(session['token'], isNotEmpty);
    expect(jsonEncode(payload).toLowerCase(), isNot(contains('auth_data')));
    expect(jsonEncode(payload).toLowerCase(), isNot(contains('xboard')));
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
    final payload = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
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
    final payload = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    final data = payload['data'] as Map<String, dynamic>;
    final items = data['items'] as List<dynamic>;
    expect(items, isNotEmpty);
  });
}

class _FakeUpstreamApi implements UpstreamApi {
  @override
  Future<void> cancelOrder(UpstreamAuth auth, {required String tradeNo}) async {}

  @override
  Future<int> checkOrder(UpstreamAuth auth, {required String tradeNo}) async => 1;

  @override
  Future<Map<String, dynamic>> checkoutOrder(
    UpstreamAuth auth, {
    required String tradeNo,
    required int methodId,
  }) async {
    return <String, dynamic>{'type': 0, 'data': true};
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
  Future<Map<String, dynamic>> fetchClientConfig(UpstreamAuth auth) async =>
      <String, dynamic>{'data': <String, dynamic>{'theme': 'neutral'}};

  @override
  Future<Map<String, dynamic>> fetchClientVersion(UpstreamAuth auth) async =>
      <String, dynamic>{'data': <String, dynamic>{'windows_version': '1.0.0'}};

  @override
  Future<Map<String, dynamic>> fetchGuestConfig() async =>
      <String, dynamic>{'data': <String, dynamic>{'is_email_verify': 1}};

  @override
  Future<List<Map<String, dynamic>>> fetchGuestPlans() async =>
      <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 1,
          'name': 'Starter',
          'transfer_enable': 10,
          'month_price': 1000,
        },
      ];

  @override
  Future<Map<String, dynamic>> fetchInviteOverview(UpstreamAuth auth) async =>
      <String, dynamic>{
        'data': <String, dynamic>{
          'codes': <Map<String, dynamic>>[],
          'stat': <int>[1, 2, 3, 4, 5],
        },
      };

  @override
  Future<List<Map<String, dynamic>>> fetchInviteRecords(UpstreamAuth auth) async =>
      <Map<String, dynamic>>[];

  @override
  Future<List<Map<String, dynamic>>> fetchNotices(UpstreamAuth auth) async =>
      <Map<String, dynamic>>[];

  @override
  Future<List<Map<String, dynamic>>> fetchOrders(UpstreamAuth auth) async =>
      <Map<String, dynamic>>[];

  @override
  Future<List<Map<String, dynamic>>> fetchPaymentMethods(UpstreamAuth auth) async =>
      <Map<String, dynamic>>[];

  @override
  Future<List<Map<String, dynamic>>> fetchPlans(UpstreamAuth auth) async =>
      <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 1,
          'name': 'Starter',
          'transfer_enable': 10,
          'month_price': 1000,
        },
      ];

  @override
  Future<Map<String, dynamic>> fetchSubscriptionSummary(UpstreamAuth auth) async =>
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
  Future<String> fetchSubscriptionContent(UpstreamAuth auth, {String? flag}) async =>
      'vmess://test';

  @override
  Future<Map<String, dynamic>> fetchUserConfig(UpstreamAuth auth) async =>
      <String, dynamic>{'data': <String, dynamic>{'currency_symbol': '¥'}};

  @override
  Future<Map<String, dynamic>> fetchUserProfile(UpstreamAuth auth) async =>
      <String, dynamic>{
        'data': <String, dynamic>{
          'email': 'u@example.com',
          'balance': 123,
          'plan_id': 1,
          'transfer_enable': 1024,
          'expired_at': 1700000000,
          'avatar_url': 'https://example.com/avatar.png',
          'uuid': 'uuid-1',
        },
      };

  @override
  Future<void> generateInviteCode(UpstreamAuth auth) async {}

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
  }) async =>
      UpstreamAuth(token: 'panel-token', authorization: 'Bearer panel-auth');

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
