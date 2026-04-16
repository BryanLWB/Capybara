import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:capybara/models/help_article.dart';
import 'package:capybara/models/web_shell_section.dart';
import 'package:capybara/models/web_invite_view_data.dart';
import 'package:capybara/models/web_purchase_view_data.dart';
import 'package:capybara/models/web_withdraw_config.dart';
import 'package:capybara/screens/web_account_page.dart';
import 'package:capybara/screens/web_auth_page.dart';
import 'package:capybara/screens/web_help_page.dart';
import 'package:capybara/screens/web_invite_page.dart';
import 'package:capybara/screens/web_purchase_page.dart';
import 'package:capybara/services/api_config.dart';
import 'package:capybara/services/panel_api.dart';
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

Future<List<WebPlanViewData>> _loadTestPlans() async => <WebPlanViewData>[
      WebPlanViewData(
        id: 1,
        title: '微量基础节点',
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
          WebPlanPeriod(
            key: 'quarter_price',
            amountField: 'quarterly_amount',
            zhLabel: '季付',
            enLabel: 'Quarterly',
            amountCents: 1100,
          ),
        ],
        features: const <String>[
          '基础系列节点',
          '适合轻量浏览',
          '入门价格低',
        ],
        deviceLimit: 3,
      ),
    ];

void main() {
  testWidgets('web purchase shell renders without overflow',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1800);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      _desktopHost(WebPurchasePage(plansLoader: _loadTestPlans)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

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

    await tester.pumpWidget(
      _desktopHost(WebPurchasePage(plansLoader: _loadTestPlans)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final heroBox =
        tester.renderObject<RenderBox>(find.byKey(const Key('web-page-hero')));
    expect(heroBox.size.width, greaterThan(1300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('web purchase flow creates order and renders payment methods',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1800);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    var createdOrder = false;
    await tester.pumpWidget(
      _desktopHost(
        WebPurchasePage(
          plansLoader: _loadTestPlans,
          couponValidator: (_, __, ___) async {},
          orderCreator: (_, __, ___) async {
            createdOrder = true;
            return 'T20260414001';
          },
          orderDetailLoader: (orderRef, fallbackPlan) async =>
              WebOrderDetailData(
            orderRef: orderRef,
            stateCode: 0,
            periodKey: 'month_price',
            amountTotal: 380,
            amountPayable: 380,
            amountDiscount: 0,
            amountBalance: 0,
            amountRefund: 0,
            amountSurplus: 0,
            amountHandling: 0,
            createdAt: 1776150000,
            plan: fallbackPlan,
          ),
          paymentMethodsLoader: () async => <WebPaymentMethodData>[
            WebPaymentMethodData(
              id: 1,
              label: '支付宝',
              provider: 'AlipayF2F',
              feeFixedCents: 0,
              feeRate: 0,
            ),
          ],
          orderCheckout: (_, __) async => WebCheckoutActionData(
            kind: WebCheckoutActionKind.completed,
            code: -1,
            payload: true,
          ),
          orderStatusLoader: (_) async => 1,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('立即购买').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('确认套餐'), findsOneWidget);
    expect(find.text('月付'), findsWidgets);

    await tester.tap(find.textContaining('前去支付'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(createdOrder, isTrue);
    expect(find.text('订单支付'), findsOneWidget);
    expect(find.text('支付宝'), findsOneWidget);

    await tester.tap(find.text('结算'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('订单已完成'), findsOneWidget);
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
    await tester.pump(const Duration(milliseconds: 400));
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

    await tester.pumpWidget(_desktopHost(WebInvitePage(
      dataLoader: () async => WebInviteViewData(
        codes: <WebInviteCodeData>[
          WebInviteCodeData(
            id: 1,
            code: 'CAPYBARA',
            stateCode: 0,
            visitCount: 4,
            createdAt: 1700000000,
          ),
        ],
        metrics: WebInviteMetricsData(
          registeredUsers: 2,
          settledAmount: 1200,
          pendingAmount: 300,
          ratePercent: 10,
          withdrawableAmount: 900,
        ),
        records: <WebInviteRecordData>[
          WebInviteRecordData(
            id: 1,
            amount: 450,
            orderAmount: 4500,
            tradeRef: 'T20260414001',
            createdAt: 1700000000,
            statusText: '已发放',
          ),
        ],
      ),
    )));
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('当前剩余佣金'), findsOneWidget);
    expect(find.text('¥9'), findsOneWidget);
    expect(find.text('¥12'), findsOneWidget);
    expect(find.textContaining('CAPYBARA'), findsOneWidget);
    expect(find.text('复制邀请码'), findsOneWidget);
    expect(find.text('佣金发放记录'), findsOneWidget);
    expect(find.text('2023-11-15'), findsOneWidget);
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

  testWidgets('web invite shell can generate missing invite code',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1800);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    var generated = false;
    await tester.pumpWidget(_desktopHost(WebInvitePage(
      dataLoader: () async => WebInviteViewData(
        codes: const <WebInviteCodeData>[],
        metrics: WebInviteMetricsData(
          registeredUsers: 0,
          settledAmount: 0,
          pendingAmount: 0,
          ratePercent: 10,
          withdrawableAmount: 0,
        ),
        records: const <WebInviteRecordData>[],
      ),
      codeCreator: () async {
        generated = true;
      },
    )));
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('生成邀请码'), findsOneWidget);
    await tester.tap(find.byKey(const Key('web-invite-generate-button')));
    await tester.pump(const Duration(milliseconds: 400));

    expect(generated, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('web invite shell transfers available commission after confirm',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1800);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    var transferred = 0;
    await tester.pumpWidget(_desktopHost(WebInvitePage(
      dataLoader: () async => WebInviteViewData(
        codes: <WebInviteCodeData>[
          WebInviteCodeData(
            id: 1,
            code: 'CAPYBARA',
            stateCode: 0,
            visitCount: 4,
            createdAt: 1700000000,
          ),
        ],
        metrics: WebInviteMetricsData(
          registeredUsers: 2,
          settledAmount: 1200,
          pendingAmount: 300,
          ratePercent: 10,
          withdrawableAmount: 900,
        ),
        records: const <WebInviteRecordData>[],
      ),
      balanceTransfer: (amountCents) async {
        transferred = amountCents;
      },
    )));
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byKey(const Key('web-invite-transfer-button')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      find.byKey(const Key('web-invite-transfer-confirm-dialog')),
      findsOneWidget,
    );
    expect(find.text('确认转入'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('web-invite-transfer-confirm-button')),
        matching: find.byType(AnimatedCard),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('web-invite-transfer-cancel-button')),
        matching: find.byType(AnimatedCard),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('确认转入'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(transferred, 900);
    expect(tester.takeException(), isNull);
  });

  testWidgets('web invite shell submits withdrawal request',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1800);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    String? requestedMethod;
    String? requestedAccount;
    await tester.pumpWidget(_desktopHost(WebInvitePage(
      dataLoader: () async => WebInviteViewData(
        codes: <WebInviteCodeData>[
          WebInviteCodeData(
            id: 1,
            code: 'CAPYBARA',
            stateCode: 0,
            visitCount: 4,
            createdAt: 1700000000,
          ),
        ],
        metrics: WebInviteMetricsData(
          registeredUsers: 2,
          settledAmount: 1200,
          pendingAmount: 300,
          ratePercent: 10,
          withdrawableAmount: 900,
        ),
        records: const <WebInviteRecordData>[],
      ),
      withdrawConfigLoader: () async => const WebWithdrawConfig(
        methods: <String>['alipay', 'bank'],
        closed: false,
      ),
      withdrawalRequester: ({required method, required account}) async {
        requestedMethod = method;
        requestedAccount = account;
      },
    )));
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byKey(const Key('web-invite-withdraw-button')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('web-invite-withdraw-dialog')), findsOneWidget);
    await tester.tap(find.text('bank'));
    await tester.enterText(
      find.byKey(const Key('web-invite-withdraw-account-field')),
      'bank-account-001',
    );
    await tester
        .tap(find.byKey(const Key('web-invite-withdraw-submit-button')));
    await tester.pump(const Duration(milliseconds: 400));

    expect(requestedMethod, 'bank');
    expect(requestedAccount, 'bank-account-001');
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

    await tester.pumpWidget(
      _desktopHost(
        WebAccountPage(
          profileLoader: () async => <String, dynamic>{
            'data': <String, dynamic>{
              'account': <String, dynamic>{'balance_amount': 456},
            },
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('账户余额（仅消费）'), findsOneWidget);
    expect(find.text('¥4.56'), findsOneWidget);
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

  testWidgets('web account shell updates notifications and risk actions',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1800);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    bool? updatedExpiry;
    bool? updatedTraffic;
    String? capturedOldPassword;
    String? capturedNewPassword;
    var resetCalled = false;
    await tester.pumpWidget(
      _desktopHost(
        WebAccountPage(
          profileLoader: () async => <String, dynamic>{
            'data': <String, dynamic>{
              'account': <String, dynamic>{
                'balance_amount': 456,
                'remind_expire': false,
                'remind_traffic': true,
              },
            },
          },
          notificationUpdater: ({required expiry, required traffic}) async {
            updatedExpiry = expiry;
            updatedTraffic = traffic;
          },
          passwordChanger: ({
            required String oldPassword,
            required String newPassword,
          }) async {
            capturedOldPassword = oldPassword;
            capturedNewPassword = newPassword;
          },
          subscriptionResetter: () async {
            resetCalled = true;
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byType(Switch).first);
    await tester.pump(const Duration(milliseconds: 400));
    expect(updatedExpiry, isTrue);
    expect(updatedTraffic, isTrue);

    await tester.tap(find.text('立即修改'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.byKey(const Key('web-account-change-password-dialog')),
      findsOneWidget,
    );
    await tester.enterText(find.widgetWithText(TextField, '旧密码'), 'old-pass');
    await tester.enterText(
      find.widgetWithText(TextField, '新密码'),
      'new-pass-123',
    );
    await tester.enterText(
      find.widgetWithText(TextField, '确认新密码'),
      'new-pass-123',
    );
    await tester.tap(find.text('确认修改'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(capturedOldPassword, 'old-pass');
    expect(capturedNewPassword, 'new-pass-123');

    await tester.tap(find.text('立即重置'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('web-account-confirm-dialog')), findsOneWidget);
    await tester.tap(find.text('确认重置'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(resetCalled, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('web auth pre-fills and submits invite code from query',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1200);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final api = _FakePanelApi();
    var authed = false;
    await tester.pumpWidget(
      _desktopHost(
        WebAuthPage(
          api: api,
          initialUri: Uri.parse('http://localhost/?invite_code=%20CAPYBARA%20'),
          onAuthed: () => authed = true,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('创建一个新的账号'), findsOneWidget);
    expect(find.text('CAPYBARA'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), 'new@example.com');
    await tester.enterText(find.byType(TextField).at(2), '123456');
    await tester.enterText(find.byType(TextField).at(3), 'password123');
    await tester.tap(find.text('创建账号'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(api.inviteCode, 'CAPYBARA');
    expect(authed, isTrue);
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
            purchasePageBuilder: (_) =>
                WebPurchasePage(plansLoader: _loadTestPlans),
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

  testWidgets('web shell logout clears server and local session state',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1200);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    SharedPreferences.setMockInitialValues(const <String, Object>{
      'app_session_token': 'as_test',
      'api_token': 'legacy-token',
      'api_auth_data': 'legacy-auth',
    });
    await ApiConfig().refreshSessionCache();

    var serverLogoutCalled = false;
    var onLogoutCalled = false;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: const [Locale('en'), Locale('zh')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: WebShell(
          onLogout: () => onLogoutCalled = true,
          logoutAction: () async => serverLogoutCalled = true,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('退出登录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final prefs = await SharedPreferences.getInstance();
    expect(serverLogoutCalled, isTrue);
    expect(onLogoutCalled, isTrue);
    expect(await ApiConfig().getSessionToken(), isNull);
    expect(prefs.containsKey('app_session_token'), isFalse);
    expect(prefs.containsKey('api_token'), isFalse);
    expect(prefs.containsKey('api_auth_data'), isFalse);
    expect(tester.takeException(), isNull);
  });
}

class _FakePanelApi extends PanelApi {
  String? inviteCode;

  @override
  Future<Map<String, dynamic>> register(
    String email,
    String password, {
    String? inviteCode,
    String? emailCode,
    String? recaptchaData,
  }) async {
    this.inviteCode = inviteCode;
    return <String, dynamic>{'data': const <String, dynamic>{}};
  }
}
