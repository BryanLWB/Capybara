import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:capybara/widgets/animated_card.dart';
import 'package:capybara/models/user_info.dart';
import 'package:capybara/models/web_home_view_data.dart';
import 'package:capybara/models/web_shell_section.dart';
import 'package:capybara/screens/web_home_page.dart';

void main() {
  testWidgets(
      'desktop zh web home renders without overflow and purchase card navigates',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1600);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    WebShellSection? navigatedSection;
    final data = WebHomeViewData.fromSources(
      user: UserInfo(
        email: 'admin@local.test',
        transferEnable: 0,
        expiredAt: 0,
        balance: 0,
        planId: 0,
      ),
      subscription: const <String, dynamic>{
        'u': 0,
        'd': 0,
        'transfer_enable': 0,
        'expired_at': 0,
        'reset_day': 0,
      },
      plans: const <Map<String, dynamic>>[],
      notices: const <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 1,
          'title': '最新可用地址',
          'content': '这里是公告内容，这里是公告内容。',
          'created_at': 1710000000,
        },
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: const [Locale('en'), Locale('zh')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(
          body: WebHomePage(
            onNavigate: (section) => navigatedSection = section,
            onUnauthorized: () {},
            dataLoader: (_) => SynchronousFuture(data),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));

    expect(find.text('公告'), findsOneWidget);
    expect(find.text('订阅概览'), findsOneWidget);
    expect(find.text('购买套餐'), findsOneWidget);
    expect(find.byKey(const Key('web-subscription-empty-card')), findsOneWidget);
    expect(
      tester.widget(find.byKey(const Key('web-subscription-empty-card'))),
      isA<AnimatedCard>(),
    );
    expect(tester.takeException(), isNull);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('购买套餐')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('购买套餐'));
    await tester.pumpAndSettle();

    expect(navigatedSection, WebShellSection.purchase);
    expect(tester.takeException(), isNull);
  });
}
