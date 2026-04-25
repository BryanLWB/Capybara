import 'package:flutter_test/flutter_test.dart';

import 'package:capybara/models/web_purchase_view_data.dart';
import 'package:capybara/services/api_config.dart';
import 'package:capybara/services/app_api.dart';
import 'package:capybara/services/panel_api.dart';
import 'package:capybara/services/user_data_service.dart';
import 'package:capybara/services/web_app_facade.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final plan = WebPlanViewData(
    id: 1,
    title: 'Starter',
    summary: '包含流量 10 GB',
    transferBytes: 10 * 1024 * 1024 * 1024,
    periods: const <WebPlanPeriod>[
      WebPlanPeriod(
        key: 'month_price',
        amountField: 'monthly_amount',
        zhLabel: '月付',
        enLabel: 'Monthly',
        amountCents: 380,
      ),
    ],
    features: const <String>['基础系列节点'],
  );

  test('recovers the latest matching pending order within 30 minutes',
      () async {
    final api = _FakeAppApi(
      orders: <Map<String, dynamic>>[
        <String, dynamic>{
          'order_ref': 'T20260416002',
          'state_code': 0,
          'created_at': 1713256200,
        },
        <String, dynamic>{
          'order_ref': 'T20260416001',
          'state_code': 0,
          'created_at': 1713255000,
        },
      ],
      orderDetails: <String, Map<String, dynamic>>{
        'T20260416002': _orderDetailPayload(
          orderRef: 'T20260416002',
          periodKey: 'month_price',
          createdAt: 1713256200,
          planId: 1,
        ),
      },
    );
    final facade = WebAppFacade(api: api, config: ApiConfig());

    final result = await facade.recoverMatchingPendingOrderRef(
      plan: plan,
      period: plan.periods.first,
      now: () => DateTime.fromMillisecondsSinceEpoch(
        1713256800 * 1000,
        isUtc: true,
      ),
    );

    expect(result, 'T20260416002');
    expect(api.requestedOrderDetails, <String>['T20260416002']);
  });

  test('does not recover any pending order when coupon is present', () async {
    final api = _FakeAppApi(
      orders: <Map<String, dynamic>>[
        <String, dynamic>{
          'order_ref': 'T20260416003',
          'state_code': 0,
          'created_at': 1713256200,
        },
      ],
    );
    final facade = WebAppFacade(api: api, config: ApiConfig());

    final result = await facade.recoverMatchingPendingOrderRef(
      plan: plan,
      period: plan.periods.first,
      couponCode: 'SAVE10',
      now: () => DateTime.fromMillisecondsSinceEpoch(
        1713256800 * 1000,
        isUtc: true,
      ),
    );

    expect(result, isNull);
    expect(api.requestedOrderDetails, isEmpty);
  });

  test('does not recover an order older than 30 minutes', () async {
    final api = _FakeAppApi(
      orders: <Map<String, dynamic>>[
        <String, dynamic>{
          'order_ref': 'T20260416004',
          'state_code': 0,
          'created_at': 1713253000,
        },
      ],
    );
    final facade = WebAppFacade(api: api, config: ApiConfig());

    final result = await facade.recoverMatchingPendingOrderRef(
      plan: plan,
      period: plan.periods.first,
      now: () => DateTime.fromMillisecondsSinceEpoch(
        1713256800 * 1000,
        isUtc: true,
      ),
    );

    expect(result, isNull);
    expect(api.requestedOrderDetails, isEmpty);
  });

  test('does not recover when latest pending order mismatches plan or period',
      () async {
    final api = _FakeAppApi(
      orders: <Map<String, dynamic>>[
        <String, dynamic>{
          'order_ref': 'T20260416005',
          'state_code': 0,
          'created_at': 1713256200,
        },
      ],
      orderDetails: <String, Map<String, dynamic>>{
        'T20260416005': _orderDetailPayload(
          orderRef: 'T20260416005',
          periodKey: 'quarter_price',
          createdAt: 1713256200,
          planId: 2,
        ),
      },
    );
    final facade = WebAppFacade(api: api, config: ApiConfig());

    final result = await facade.recoverMatchingPendingOrderRef(
      plan: plan,
      period: plan.periods.first,
      now: () => DateTime.fromMillisecondsSinceEpoch(
        1713256800 * 1000,
        isUtc: true,
      ),
    );

    expect(result, isNull);
    expect(api.requestedOrderDetails, <String>['T20260416005']);
  });

  test('loadHomeData uses bootstrap route for home payload', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final api = _FakeAppApi();
    final config = ApiConfig();
    final facade = WebAppFacade(
      api: api,
      config: config,
      userDataService: UserDataService.withApi(
        PanelApi(config: config, appApi: api),
      ),
    );

    final data = await facade.loadHomeData();

    expect(api.webBootstrapCalls, 1);
    expect(data.hasSubscription, isTrue);
    expect(data.totalBytes, 1024);
    expect(data.expiryAt, 1713256800);
  });
}

Map<String, dynamic> _orderDetailPayload({
  required String orderRef,
  required String periodKey,
  required int createdAt,
  required int planId,
}) {
  return <String, dynamic>{
    'data': <String, dynamic>{
      'order': <String, dynamic>{
        'order_ref': orderRef,
        'state_code': 0,
        'period_key': periodKey,
        'amount_total': 380,
        'amount_payable': 380,
        'amount_discount': 0,
        'amount_balance': 0,
        'amount_refund': 0,
        'amount_surplus': 0,
        'amount_handling': 0,
        'created_at': createdAt,
        'plan': <String, dynamic>{
          'plan_id': planId,
          'title': 'Starter',
          'transfer_bytes': 10 * 1024 * 1024 * 1024,
          'monthly_amount': 380,
        },
      },
    },
  };
}

class _FakeAppApi extends AppApi {
  _FakeAppApi({
    List<Map<String, dynamic>>? orders,
    Map<String, Map<String, dynamic>>? orderDetails,
    int subscriptionFailuresRemaining = 0,
  })  : _orders = orders ?? const <Map<String, dynamic>>[],
        _orderDetails = orderDetails ?? const <String, Map<String, dynamic>>{},
        _subscriptionFailuresRemaining = subscriptionFailuresRemaining,
        super(config: ApiConfig());

  final List<Map<String, dynamic>> _orders;
  final Map<String, Map<String, dynamic>> _orderDetails;
  final List<String> requestedOrderDetails = <String>[];
  int _subscriptionFailuresRemaining;
  int subscriptionSummaryCalls = 0;
  int webBootstrapCalls = 0;

  @override
  Future<Map<String, dynamic>> getOrders() async {
    return <String, dynamic>{
      'data': <String, dynamic>{'items': _orders},
    };
  }

  @override
  Future<Map<String, dynamic>> getOrderDetail(String tradeNo) async {
    requestedOrderDetails.add(tradeNo);
    return _orderDetails[tradeNo] ??
        <String, dynamic>{
          'data': <String, dynamic>{'order': <String, dynamic>{}},
        };
  }

  @override
  Future<Map<String, dynamic>> getProfile() async {
    return <String, dynamic>{
      'data': <String, dynamic>{
        'account': <String, dynamic>{
          'email': 'admin@local.test',
          'transfer_bytes': 1024,
          'expiry_at': 1713256800,
          'balance_amount': 0,
          'plan_id': 1,
        },
      },
    };
  }

  @override
  Future<Map<String, dynamic>> getUserConfig() async {
    return <String, dynamic>{
      'data': <String, dynamic>{'config': <String, dynamic>{}},
    };
  }

  @override
  Future<Map<String, dynamic>> getSubscriptionSummary() async {
    subscriptionSummaryCalls += 1;
    if (_subscriptionFailuresRemaining > 0) {
      _subscriptionFailuresRemaining -= 1;
      throw AppApiException(
        statusCode: 500,
        message: 'temporary subscription failure',
      );
    }
    return <String, dynamic>{
      'data': <String, dynamic>{
        'subscription': <String, dynamic>{
          'upload_bytes': 10,
          'download_bytes': 20,
          'total_bytes': 1024,
          'expiry_at': 1713256800,
          'reset_days': 0,
          'download_endpoint': '/api/app/v1/account/subscription/content',
        },
      },
    };
  }

  @override
  Future<Map<String, dynamic>> getPlans() async {
    return <String, dynamic>{
      'data': <String, dynamic>{
        'items': <Map<String, dynamic>>[
          <String, dynamic>{
            'plan_id': 1,
            'title': 'Starter',
            'transfer_bytes': 1024,
          },
        ],
      },
    };
  }

  @override
  Future<Map<String, dynamic>> getNotices() async {
    return <String, dynamic>{
      'data': <String, dynamic>{'items': <Map<String, dynamic>>[]},
    };
  }

  @override
  Future<Map<String, dynamic>> getWebBootstrap() async {
    webBootstrapCalls += 1;
    return <String, dynamic>{
      'data': <String, dynamic>{
        'account': <String, dynamic>{
          'email': 'admin@local.test',
          'transfer_bytes': 1024,
          'expiry_at': 1713256800,
          'balance_amount': 0,
          'plan_id': 1,
        },
        'config': <String, dynamic>{},
        'subscription': <String, dynamic>{
          'upload_bytes': 10,
          'download_bytes': 20,
          'total_bytes': 1024,
          'expiry_at': 1713256800,
          'reset_days': 0,
          'download_endpoint': '/api/app/v1/account/subscription/content',
        },
        'plans': <Map<String, dynamic>>[
          <String, dynamic>{
            'plan_id': 1,
            'title': 'Starter',
            'transfer_bytes': 1024,
          },
        ],
        'notices': <Map<String, dynamic>>[],
      },
    };
  }

  @override
  Future<Map<String, dynamic>> getAccountBootstrap() async {
    return <String, dynamic>{
      'data': <String, dynamic>{
        'account': <String, dynamic>{
          'email': 'admin@local.test',
          'transfer_bytes': 1024,
          'expiry_at': 1713256800,
          'balance_amount': 0,
          'plan_id': 1,
          'remind_expire': true,
          'remind_traffic': false,
          'telegram_bound': false,
        },
        'config': <String, dynamic>{},
        'subscription': <String, dynamic>{
          'total_bytes': 1024,
          'expiry_at': 1713256800,
          'plan_id': 1,
        },
      },
    };
  }
}
