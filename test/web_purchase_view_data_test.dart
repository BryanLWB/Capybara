import 'package:flutter_test/flutter_test.dart';

import 'package:capybara/models/web_purchase_view_data.dart';

void main() {
  test('plan view data keeps only purchasable priced periods', () {
    final plan = WebPlanViewData.fromJson(<String, dynamic>{
      'plan_id': 1,
      'title': 'Starter',
      'transfer_bytes': 10 * 1024 * 1024 * 1024,
      'monthly_amount': 380,
      'quarterly_amount': null,
      'half_year_amount': 0,
      'yearly_amount': '1200',
    });

    expect(plan.canBuy, isTrue);
    expect(plan.trafficLabel, '10.00 GB');
    expect(plan.periods.map((period) => period.key), <String>[
      'month_price',
      'year_price',
    ]);
  });

  test('plan view data preserves rich content for detail rendering', () {
    final plan = WebPlanViewData.fromJson(<String, dynamic>{
      'plan_id': 2,
      'title': 'Pro',
      'summary':
          '## 套餐亮点\n\n- 支持更多地区\n- **适合主力使用**\n\n[查看说明](https://example.com)',
      'transfer_bytes': 50 * 1024 * 1024 * 1024,
      'monthly_amount': 680,
    });

    expect(plan.summary, contains('套餐亮点'));
    expect(plan.richContentHtml, contains('套餐亮点</h2>'));
    expect(plan.richContentHtml, contains('<strong>适合主力使用</strong>'));
    expect(plan.features, isNotEmpty);
  });
}
