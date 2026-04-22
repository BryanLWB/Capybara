import 'package:flutter_test/flutter_test.dart';

import 'package:capybara/models/user_info.dart';
import 'package:capybara/models/web_home_view_data.dart';

void main() {
  test('web home view data resolves plan and sorts latest notice', () {
    final user = UserInfo(
      email: 'demo@example.com',
      transferEnable: 0,
      expiredAt: 0,
      balance: 1280,
      planId: 2,
    );

    final viewData = WebHomeViewData.fromSources(
      user: user,
      subscription: <String, dynamic>{
        'u': 1024,
        'd': 2048,
        'transfer_enable': 4096,
        'expired_at': 1710000000,
        'reset_day': 15,
      },
      plans: <Map<String, dynamic>>[
        <String, dynamic>{'id': 1, 'name': 'Starter'},
        <String, dynamic>{'id': 2, 'name': 'Pro'},
      ],
      notices: <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 7,
          'title': 'Older',
          'content': 'Plain body',
          'created_at': 1700000000,
        },
        <String, dynamic>{
          'id': 9,
          'title': '<b>Latest</b>',
          'content': '<p>Body<br>Line 2</p>',
          'created_at': 1710000000,
        },
      ],
    );

    expect(viewData.planName, 'Pro');
    expect(viewData.hasSubscription, isTrue);
    expect(viewData.usedBytes, 3072);
    expect(viewData.latestNotice?.title, 'Latest');
    expect(viewData.latestNotice?.body, 'Body\nLine 2');
  });
}
