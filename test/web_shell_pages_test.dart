import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:capybara/models/help_article.dart';
import 'package:capybara/models/web_shell_section.dart';
import 'package:capybara/screens/web_account_page.dart';
import 'package:capybara/screens/web_help_page.dart';
import 'package:capybara/screens/web_invite_page.dart';
import 'package:capybara/screens/web_purchase_page.dart';
import 'package:capybara/screens/web_shell.dart';
import 'package:capybara/widgets/action_button.dart';
import 'package:capybara/widgets/animated_card.dart';

Widget _desktopHost(Widget child) {
  return MaterialApp(
    locale: const Locale('zh'),
    supportedLocales: const [Locale('en'), Locale('zh')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('web purchase shell renders without overflow',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1800);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(_desktopHost(const WebPurchasePage()));
    await tester.pumpAndSettle();

    expect(find.text('选择更适合你的套餐'), findsOneWidget);
    expect(find.text('全部套餐'), findsOneWidget);
    expect(find.text('立即购买'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('web purchase hero stretches across content width',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1800);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(_desktopHost(const WebPurchasePage()));
    await tester.pumpAndSettle();

    final heroBox =
        tester.renderObject<RenderBox>(find.byKey(const Key('web-page-hero')));
    expect(heroBox.size.width, greaterThan(1300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('web help shell renders without overflow',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 2200);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      _desktopHost(
        WebHelpPage(
          categoriesLoader: (_) async => <HelpCategory>[
            HelpCategory(
              name: '客户端下载',
              articles: <HelpArticleSummary>[
                HelpArticleSummary(
                  id: 1,
                  category: '客户端下载',
                  title: 'Windows 客户端',
                  updatedAt: 1700000000,
                ),
              ],
            ),
          ],
          articleLoader: (_, __) async => HelpArticleDetail(
            id: 1,
            category: '客户端下载',
            title: 'Windows 客户端',
            updatedAt: 1700000000,
            bodyHtml: '<p>正文</p>',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));

    expect(find.text('帮助中心与知识库'), findsOneWidget);
    expect(find.text('在线聊天'), findsOneWidget);
    expect(find.text('客户端下载'), findsOneWidget);
    final heroBox =
        tester.renderObject<RenderBox>(find.byKey(const Key('web-page-hero')));
    expect(heroBox.size.width, greaterThan(1300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('web invite shell renders without overflow',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1800);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(_desktopHost(const WebInvitePage()));
    await tester.pumpAndSettle();

    expect(find.text('当前剩余佣金'), findsOneWidget);
    expect(find.text('复制邀请码'), findsOneWidget);
    expect(find.text('佣金发放记录'), findsOneWidget);
    expect(find.byType(ActionChip), findsNothing);
    expect(find.byType(WebPurchasePage), findsNothing);
    expect(find.byType(WebHelpPage), findsNothing);
    expect(find.byType(WebAccountPage), findsNothing);
    expect(find.byType(WebInvitePage), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byKey(const Key('web-invite-withdraw-button')), findsOneWidget);
    expect(find.byKey(const Key('web-invite-transfer-button')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('web-invite-withdraw-button')),
        matching: find.byType(ActionButton),
      ),
      findsOneWidget,
    );
    expect(
      tester.widget(find.byKey(const Key('web-invite-transfer-button'))),
      isA<AnimatedCard>(),
    );
    final withdrawBox = tester.renderObject<RenderBox>(
      find.byKey(const Key('web-invite-withdraw-button')),
    );
    final transferBox = tester.renderObject<RenderBox>(
      find.byKey(const Key('web-invite-transfer-button')),
    );
    expect(withdrawBox.size.height, equals(transferBox.size.height));
    expect(tester.takeException(), isNull);
  });

  testWidgets('web account shell renders without overflow',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1800);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(_desktopHost(const WebAccountPage()));
    await tester.pumpAndSettle();

    expect(find.text('账户余额（仅消费）'), findsOneWidget);
    expect(find.text('邮件通知'), findsOneWidget);
    expect(find.text('修改你的密码'), findsOneWidget);
    final balanceBox = tester.renderObject<RenderBox>(
      find.byKey(const Key('web-account-balance-card')),
    );
    final preferenceBox = tester.renderObject<RenderBox>(
      find.byKey(const Key('web-account-preference-card')),
    );
    expect(balanceBox.size.height, equals(preferenceBox.size.height));
    expect(tester.takeException(), isNull);
  });

  testWidgets('web shell keeps purchase and account pages top aligned',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1800);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    Future<void> pumpShell(WebShellSection section) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: const [Locale('en'), Locale('zh')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: WebShell(
            key: ValueKey(section),
            onLogout: () {},
            initialSection: section,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    await pumpShell(WebShellSection.purchase);
    final purchaseHeroTop = tester.getTopLeft(
      find.byKey(const Key('web-page-hero')),
    );
    expect(purchaseHeroTop.dy, lessThan(180));

    await pumpShell(WebShellSection.account);
    final balanceTop = tester.getTopLeft(
      find.byKey(const Key('web-account-balance-card')),
    );
    expect(balanceTop.dy, lessThan(180));
    expect(tester.takeException(), isNull);
  });
}
