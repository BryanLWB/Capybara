import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:capybara/widgets/animated_card.dart';
import 'package:capybara/models/user_info.dart';
import 'package:capybara/models/web_client_download.dart';
import 'package:capybara/models/web_home_view_data.dart';
import 'package:capybara/models/web_shell_section.dart';
import 'package:capybara/screens/web_home_page.dart';

WebHomeViewData _homeData() {
  return WebHomeViewData.fromSources(
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
}

Widget _desktopHost(Widget child) {
  return MaterialApp(
    locale: const Locale('zh'),
    supportedLocales: const [Locale('en'), Locale('zh')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: Scaffold(body: child),
  );
}

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
    final data = _homeData();

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

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 3));

    expect(find.text('公告'), findsOneWidget);
    expect(find.text('订阅概览'), findsOneWidget);
    expect(find.text('购买套餐'), findsOneWidget);
    expect(
        find.byKey(const Key('web-subscription-empty-card')), findsOneWidget);
    expect(
      tester.widget(find.byKey(const Key('web-subscription-empty-card'))),
      isA<AnimatedCard>(),
    );
    expect(tester.takeException(), isNull);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('购买套餐')));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('购买套餐'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(navigatedSection, WebShellSection.purchase);
    expect(tester.takeException(), isNull);
  });

  testWidgets('web home quick start actions use neutral subscription links',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1600);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    WebShellSection? navigatedSection;
    String? requestedFlag;
    String? clipboardText;
    const link = 'http://127.0.0.1:8787/api/app/v1/client/subscription/cl_test';

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboardText = (call.arguments as Map?)?['text']?.toString();
        return null;
      }
      if (call.method == 'Clipboard.getData') {
        return <String, dynamic>{'text': clipboardText};
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(
      _desktopHost(
        WebHomePage(
          onNavigate: (section) => navigatedSection = section,
          onUnauthorized: () {},
          dataLoader: (_) => SynchronousFuture(_homeData()),
          subscriptionLinkCreator: (flag) async {
            requestedFlag = flag;
            return link;
          },
          downloadsLoader: () async => const <WebClientDownloadItem>[
            WebClientDownloadItem(
              platform: 'ios',
              label: 'iOS',
              available: false,
            ),
          ],
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('复制订阅链接'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(requestedFlag, 'shadowrocket');
    final clipboardData = await Clipboard.getData('text/plain');
    expect(clipboardData?.text, link);

    await tester.tap(find.text('二维码订阅'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byKey(const Key('web-home-subscription-qr-dialog')),
      findsOneWidget,
    );
    expect(find.text(link), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('下载客户端'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(navigatedSection, WebShellSection.help);
    expect(tester.takeException(), isNull);
  });
}
