import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:capybara/models/help_article.dart';
import 'package:capybara/models/web_shell_section.dart';
import 'package:capybara/models/web_invite_view_data.dart';
import 'package:capybara/models/web_purchase_view_data.dart';
import 'package:capybara/models/web_user_center_view_data.dart';
import 'package:capybara/models/web_user_subpage.dart';
import 'package:capybara/models/web_withdraw_config.dart';
import 'package:capybara/screens/web_account_page.dart';
import 'package:capybara/screens/web_auth_page.dart';
import 'package:capybara/screens/web_help_page.dart';
import 'package:capybara/screens/web_invite_page.dart';
import 'package:capybara/screens/web_purchase_page.dart';
import 'package:capybara/services/api_config.dart';
import 'package:capybara/services/panel_api.dart';
import 'package:capybara/services/web_app_facade.dart';
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
    expect(find.text('我的订单'), findsNothing);
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

  testWidgets(
      'web purchase order setup adapts coupon and checkout bar on narrow width',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(760, 1600);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      _desktopHost(
        WebPurchasePage(
          plansLoader: _loadTestPlans,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('立即购买').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('验证'), findsOneWidget);
    expect(find.textContaining('前去支付'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('web purchase checkout returns to matching source page',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1800);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    var openedUserOrders = false;
    await tester.pumpWidget(
      _desktopHost(
        WebPurchasePage(
          key: const ValueKey('external-order-checkout'),
          initialOrderRef: 'T20260414002',
          initialFallbackPlan: (await _loadTestPlans()).first,
          onOpenUserOrders: () => openedUserOrders = true,
          plansLoader: _loadTestPlans,
          orderDetailLoader: (orderRef, fallbackPlan) async =>
              WebOrderDetailData(
            orderRef: orderRef,
            stateCode: 0,
            periodKey: 'month_price',
            amountTotal: 380,
            amountPayable: 390,
            amountDiscount: 0,
            amountBalance: 0,
            amountRefund: 0,
            amountSurplus: 0,
            amountHandling: 10,
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
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('订单支付'), findsOneWidget);
    await tester.tap(find.text('返回订单'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(openedUserOrders, isTrue);

    await tester.pumpWidget(
      _desktopHost(
        WebPurchasePage(
          key: const ValueKey('setup-checkout'),
          plansLoader: _loadTestPlans,
          orderCreator: (_, __, ___) async => 'T20260414003',
          orderDetailLoader: (orderRef, fallbackPlan) async =>
              WebOrderDetailData(
            orderRef: orderRef,
            stateCode: 0,
            periodKey: 'month_price',
            amountTotal: 380,
            amountPayable: 390,
            amountDiscount: 0,
            amountBalance: 0,
            amountRefund: 0,
            amountSurplus: 0,
            amountHandling: 10,
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
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('立即购买').first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.textContaining('前去支付'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('订单支付'), findsOneWidget);
    await tester.tap(find.text('返回周期选择'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('确认套餐'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('web purchase only recovers pending orders for pending conflict',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1800);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    var recoveryCalled = false;
    await tester.pumpWidget(
      _desktopHost(
        WebPurchasePage(
          plansLoader: _loadTestPlans,
          orderCreator: (_, __, ___) async {
            throw const PendingOrderExistsException();
          },
          pendingOrderRecoverer: (plan, period, couponCode) async {
            recoveryCalled = true;
            expect(plan.id, 1);
            expect(period.key, 'month_price');
            expect(couponCode, isNull);
            return 'T20260414002';
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
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('立即购买').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.textContaining('前去支付'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(recoveryCalled, isTrue);
    expect(find.text('订单支付'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('web purchase does not recover old orders for generic failures',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1800);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    var recoveryCalled = false;
    await tester.pumpWidget(
      _desktopHost(
        WebPurchasePage(
          plansLoader: _loadTestPlans,
          orderCreator: (_, __, ___) async {
            throw StateError('coupon failed');
          },
          pendingOrderRecoverer: (_, __, ___) async {
            recoveryCalled = true;
            return 'T20260414003';
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('立即购买').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.textContaining('前去支付'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(recoveryCalled, isFalse);
    expect(find.text('暂时无法完成操作，请稍后再试。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('web purchase pending order banner opens user orders callback',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1800);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    var openedUserOrders = false;
    await tester.pumpWidget(
      _desktopHost(
        WebPurchasePage(
          plansLoader: _loadTestPlans,
          onOpenUserOrders: () => openedUserOrders = true,
          orderCreator: (_, __, ___) async {
            throw const PendingOrderExistsException();
          },
          pendingOrderRecoverer: (_, __, ___) async => null,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('立即购买').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.textContaining('前去支付'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('查看我的订单'), findsOneWidget);
    await tester.tap(find.text('查看我的订单'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(openedUserOrders, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('web purchase confirms before replacing active subscription',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1800);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    var createCalls = 0;
    await tester.pumpWidget(
      _desktopHost(
        WebPurchasePage(
          plansLoader: _loadTestPlans,
          activeSubscriptionPlanLoader: () async => 99,
          orderCreator: (_, __, ___) async {
            createCalls += 1;
            return 'T20260414099';
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
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('立即购买').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.textContaining('前去支付'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('请确认订阅变更'), findsOneWidget);
    expect(createCalls, 0);

    await tester.tap(find.text('取消'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('确认套餐'), findsOneWidget);
    expect(createCalls, 0);

    await tester.tap(find.textContaining('前去支付'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('继续购买'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(createCalls, 1);
    expect(find.text('订单支付'), findsOneWidget);
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

    final reminderSwitchFinder = find.byType(Switch).evaluate().isNotEmpty
        ? find.byType(Switch).first
        : find.byType(CupertinoSwitch).first;
    await tester.tap(reminderSwitchFinder);
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

  testWidgets(
      'web account user center switches through orders nodes tickets and traffic',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 2000);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    var openedOrderRef = '';
    await tester.pumpWidget(
      _desktopHost(
        WebAccountPage(
          initialSubpage: WebUserSubpage.orders,
          profileLoader: () async => <String, dynamic>{
            'data': <String, dynamic>{
              'account': <String, dynamic>{
                'balance_amount': 456,
                'remind_expire': false,
                'remind_traffic': true,
              },
            },
          },
          ordersLoader: () async => <WebOrderListItemData>[
            WebOrderListItemData(
              orderRef: 'T20260417001',
              stateCode: 0,
              periodKey: 'month_price',
              amountTotal: 380,
              createdAt: 1776150000,
              updatedAt: 1776150300,
              plan: (await _loadTestPlans()).first,
            ),
          ],
          nodeStatusesLoader: () async => const <WebNodeStatusItemData>[
            WebNodeStatusItemData(
              nodeId: 1,
              displayName: '东京节点',
              protocolType: 'vmess',
              version: 'v2ray',
              rate: 1.0,
              tags: <String>['日本', '流媒体'],
              isOnline: true,
              lastCheckAt: 1776150300,
            ),
          ],
          ticketsLoader: () async => const <WebTicketListItemData>[
            WebTicketListItemData(
              ticketId: 8,
              subject: '无法连接',
              priorityLevel: 1,
              replyState: 0,
              stateCode: 0,
              createdAt: 1776150000,
              updatedAt: 1776150300,
            ),
          ],
          trafficLogsLoader: () async => const <WebTrafficLogItemData>[
            WebTrafficLogItemData(
              uploadedAmount: 1024,
              downloadedAmount: 2048,
              chargedAmount: 4096,
              rateMultiplier: 1.5,
              recordedAt: 1776150300,
            ),
          ],
          onOpenOrderCheckout: (orderRef, _) async {
            openedOrderRef = orderRef;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('用户中心'), findsOneWidget);
    expect(find.text('个人中心'), findsWidgets);
    expect(find.text('我的订单'), findsOneWidget);
    expect(find.text('节点状态'), findsOneWidget);
    expect(find.text('我的工单'), findsOneWidget);
    expect(find.text('流量明细'), findsOneWidget);

    expect(find.text('继续支付'), findsOneWidget);
    await tester.tap(find.text('继续支付'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(openedOrderRef, 'T20260417001');

    await tester.tap(find.byKey(const Key('web-user-subpage-nodes')));
    await tester.pumpAndSettle();
    expect(find.text('东京节点'), findsOneWidget);

    await tester.tap(find.byKey(const Key('web-user-subpage-tickets')));
    await tester.pumpAndSettle();
    expect(find.text('无法连接'), findsOneWidget);

    await tester.tap(find.byKey(const Key('web-user-subpage-traffic')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('4.00 KB', findRichText: true),
      findsOneWidget,
    );
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

  testWidgets('web auth clears verify message when returning to login',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1200);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final api = _FakePanelApi()..sendEmailCodeHandler = () async {};
    await tester.pumpWidget(
      _desktopHost(
        WebAuthPage(
          api: api,
          onAuthed: () {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('忘记密码？'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(find.byType(TextField).first, 'user@example.com');
    await tester.tap(find.text('获取验证码'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('验证码已发送，请留意邮箱'), findsOneWidget);

    await tester.tap(find.text('返回登录'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('验证码已发送，请留意邮箱'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('web auth uses structured form widgets',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1200);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      _desktopHost(
        WebAuthPage(
          api: _FakePanelApi(),
          onAuthed: () {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(Form), findsOneWidget);
    expect(find.byType(AutofillGroup), findsOneWidget);
    expect(find.byType(TextFormField), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('web auth submits login on enter and shows customer message',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1200);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final api = _FakePanelApi()
      ..loginHandler = () async => throw PanelApiException(
            statusCode: 401,
            message: 'Request failed',
            code: 'auth.invalid',
          );

    await tester.pumpWidget(
      _desktopHost(
        WebAuthPage(
          api: api,
          onAuthed: () {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.enterText(find.byType(TextField).at(0), 'user@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'wrong-password');
    await tester.tap(find.byType(TextField).at(1));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(api.loginCalls, 1);
    expect(find.text('邮箱或密码不正确，请重新输入。'), findsOneWidget);
    expect(find.text('Request failed'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('web auth submits register and reset on enter',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1200);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final api = _FakePanelApi();
    await tester.pumpWidget(
      _desktopHost(
        WebAuthPage(
          api: api,
          onAuthed: () {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('立即注册'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(find.byType(TextField).at(0), 'new@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'INVITE');
    await tester.enterText(find.byType(TextField).at(2), '123456');
    await tester.enterText(find.byType(TextField).at(3), 'password123');
    await tester.tap(find.byType(TextField).at(3));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(api.registerCalls, 1);

    await tester.tap(find.text('返回登录'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('忘记密码？'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(find.byType(TextField).at(0), 'user@example.com');
    await tester.enterText(find.byType(TextField).at(1), '654321');
    await tester.enterText(find.byType(TextField).at(2), 'new-password');
    await tester.tap(find.byType(TextField).at(2));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(api.resetCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('web shell keeps purchase and user center pages top aligned',
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
    final accountHeroTop = tester.getTopLeft(
      find.byKey(const Key('web-page-hero')),
    );
    expect(accountHeroTop.dy, lessThan(180));
    expect(find.text('用户中心'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('web shell renders all navigation on first row when width allows',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(930, 1400);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: const [Locale('en'), Locale('zh')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: WebShell(
          onLogout: () {},
          initialSection: WebShellSection.home,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final userTop = tester.getTopLeft(find.text('用户')).dy;
    final homeTop = tester.getTopLeft(find.text('主页')).dy;
    final inviteTop = tester.getTopLeft(find.text('邀请')).dy;
    final userLeft = tester.getTopLeft(find.text('用户')).dx;
    final inviteLeft = tester.getTopLeft(find.text('邀请')).dx;

    expect((userTop - homeTop).abs(), lessThan(24));
    expect((inviteTop - homeTop).abs(), lessThan(24));
    expect(userLeft, greaterThan(inviteLeft));
    expect(find.text('用户'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'web shell keeps account navigation on second row when only nav fits',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(650, 1400);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: const [Locale('en'), Locale('zh')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: WebShell(
          onLogout: () {},
          initialSection: WebShellSection.home,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final userTop = tester.getTopLeft(find.text('用户')).dy;
    final homeTop = tester.getTopLeft(find.text('主页')).dy;
    final inviteTop = tester.getTopLeft(find.text('邀请')).dy;
    final logoutTop = tester.getTopLeft(find.text('退出登录')).dy;
    final userLeft = tester.getTopLeft(find.text('用户')).dx;
    final inviteLeft = tester.getTopLeft(find.text('邀请')).dx;
    final homeCenter = tester.getCenter(find.text('主页')).dx;
    final userCenter = tester.getCenter(find.text('用户')).dx;
    final rowCenter = (homeCenter + userCenter) / 2;

    expect(userTop, greaterThan(logoutTop));
    expect((userTop - homeTop).abs(), lessThan(24));
    expect((inviteTop - homeTop).abs(), lessThan(24));
    expect(userLeft, greaterThan(inviteLeft));
    expect((rowCenter - 325).abs(), lessThan(70));
    expect(find.text('用户'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'web shell keeps account on first row between brand and logout when second row is full',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(450, 1400);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: const [Locale('en'), Locale('zh')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: WebShell(
          onLogout: () {},
          initialSection: WebShellSection.home,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final brandCenter = tester.getCenter(find.text('Capybara'));
    final userCenter = tester.getCenter(find.text('用户'));
    final logoutCenter = tester.getCenter(find.text('退出登录'));
    final logoutTop = tester.getTopLeft(find.text('退出登录')).dy;
    final userTop = tester.getTopLeft(find.text('用户')).dy;
    final helpTop = tester.getTopLeft(find.text('帮助')).dy;

    expect((userTop - logoutTop).abs(), lessThan(24));
    expect(helpTop, greaterThan(userTop));
    expect(userCenter.dx, greaterThan(brandCenter.dx));
    expect(userCenter.dx, lessThan(logoutCenter.dx));
    expect(find.text('用户'), findsOneWidget);
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
    expect(find.byKey(const Key('web-shell-confirm-dialog')), findsOneWidget);

    await tester.tap(find.text('确定'));
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

  testWidgets('web purchase payment confirmation can navigate home',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1800);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    var navigatedHome = false;
    var statusChecks = 0;
    await tester.pumpWidget(
      _desktopHost(
        WebPurchasePage(
          plansLoader: _loadTestPlans,
          onPaymentCompletedNavigateHome: () => navigatedHome = true,
          orderCreator: (_, __, ___) async => 'T20260414066',
          orderDetailLoader: (orderRef, fallbackPlan) async =>
              WebOrderDetailData(
            orderRef: orderRef,
            stateCode: 0,
            periodKey: 'month_price',
            amountTotal: 380,
            amountPayable: 390,
            amountDiscount: 0,
            amountBalance: 0,
            amountRefund: 0,
            amountSurplus: 0,
            amountHandling: 10,
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
            kind: WebCheckoutActionKind.redirect,
            code: 1,
            payload: 'https://example.com/pay',
          ),
          paymentLauncher: (_) async => true,
          orderStatusLoader: (_) async {
            statusChecks += 1;
            return statusChecks >= 2 ? 1 : 0;
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('立即购买').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.textContaining('前去支付'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('结算'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('我已完成支付'), findsOneWidget);
    await tester.tap(find.text('我已完成支付'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 300));

    expect(navigatedHome, isTrue);
    expect(tester.takeException(), isNull);
  });
}

class _FakePanelApi extends PanelApi {
  String? inviteCode;
  int loginCalls = 0;
  int registerCalls = 0;
  int resetCalls = 0;
  Future<Map<String, dynamic>> Function()? loginHandler;
  Future<void> Function()? sendEmailCodeHandler;

  @override
  Future<Map<String, dynamic>> login(String email, String password) async {
    loginCalls += 1;
    if (loginHandler != null) {
      return loginHandler!();
    }
    return <String, dynamic>{'data': const <String, dynamic>{}};
  }

  @override
  Future<Map<String, dynamic>> register(
    String email,
    String password, {
    String? inviteCode,
    String? emailCode,
    String? recaptchaData,
  }) async {
    registerCalls += 1;
    this.inviteCode = inviteCode;
    return <String, dynamic>{'data': const <String, dynamic>{}};
  }

  @override
  Future<Map<String, dynamic>> forgetPassword(
    String email,
    String emailCode,
    String password,
  ) async {
    resetCalls += 1;
    return <String, dynamic>{'data': true};
  }

  @override
  Future<Map<String, dynamic>> sendEmailVerify(
    String email, {
    String? recaptchaData,
  }) async {
    if (sendEmailCodeHandler != null) {
      await sendEmailCodeHandler!();
    }
    return <String, dynamic>{'data': true};
  }
}
