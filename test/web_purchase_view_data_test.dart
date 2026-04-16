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
}
