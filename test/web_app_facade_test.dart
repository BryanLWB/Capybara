import 'package:flutter_test/flutter_test.dart';

import 'package:capybara/models/web_purchase_view_data.dart';
import 'package:capybara/services/api_config.dart';
import 'package:capybara/services/app_api.dart';
import 'package:capybara/services/web_app_facade.dart';

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
  })  : _orders = orders ?? const <Map<String, dynamic>>[],
        _orderDetails = orderDetails ?? const <String, Map<String, dynamic>>{},
        super(config: ApiConfig());

  final List<Map<String, dynamic>> _orders;
  final Map<String, Map<String, dynamic>> _orderDetails;
  final List<String> requestedOrderDetails = <String>[];

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
}
