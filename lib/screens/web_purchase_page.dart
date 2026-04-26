import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/web_purchase_view_data.dart';
import '../services/web_app_facade.dart';
import '../theme/app_colors.dart';
import '../utils/formatters.dart';
import '../utils/web_error_text.dart';
import '../widgets/animated_card.dart';
import '../widgets/capybara_loader.dart';
import '../widgets/gradient_card.dart';
import '../widgets/rich_content_view.dart';
import '../widgets/web_layout_metrics.dart';
import '../widgets/web_page_frame.dart';
import '../widgets/web_page_hero.dart';

typedef WebPlansLoader = Future<List<WebPlanViewData>> Function();
typedef WebCouponValidator = Future<void> Function(
  int planId,
  String periodKey,
  String couponCode,
);
typedef WebOrderCreator = Future<String> Function(
  int planId,
  String periodKey,
  String? couponCode,
);
typedef WebPendingOrderRecoverer = Future<String?> Function(
  WebPlanViewData plan,
  WebPlanPeriod period,
  String? couponCode,
);
typedef WebOrderDetailLoader = Future<WebOrderDetailData> Function(
  String orderRef,
  WebPlanViewData? fallbackPlan,
);
typedef WebPaymentMethodsLoader = Future<List<WebPaymentMethodData>> Function();
typedef WebOrderCheckout = Future<WebCheckoutActionData> Function(
  String orderRef,
  int methodId,
);
typedef WebOrderStatusLoader = Future<int> Function(String orderRef);
typedef WebPaymentLauncher = Future<bool> Function(Uri uri);
typedef WebOrdersLoader = Future<List<WebOrderListItemData>> Function();
typedef WebOrderCanceler = Future<void> Function(String orderRef);
typedef WebActiveSubscriptionPlanLoader = Future<int?> Function();
typedef WebPaymentCompletedNavigateHome = void Function();

enum _PurchaseStage { catalog, orders, orderSetup, checkout, paymentPending }

enum _CheckoutOrigin { orderSetup, orderList, externalOrder }

class WebPurchasePage extends StatefulWidget {
  const WebPurchasePage({
    super.key,
    this.initialOrderRef,
    this.initialFallbackPlan,
    this.onOpenUserOrders,
    this.plansLoader,
    this.couponValidator,
    this.orderCreator,
    this.pendingOrderRecoverer,
    this.orderDetailLoader,
    this.paymentMethodsLoader,
    this.orderCheckout,
    this.orderStatusLoader,
    this.paymentLauncher,
    this.ordersLoader,
    this.orderCanceler,
    this.activeSubscriptionPlanLoader,
    this.onPaymentCompletedNavigateHome,
  });

  final String? initialOrderRef;
  final WebPlanViewData? initialFallbackPlan;
  final VoidCallback? onOpenUserOrders;
  final WebPlansLoader? plansLoader;
  final WebCouponValidator? couponValidator;
  final WebOrderCreator? orderCreator;
  final WebPendingOrderRecoverer? pendingOrderRecoverer;
  final WebOrderDetailLoader? orderDetailLoader;
  final WebPaymentMethodsLoader? paymentMethodsLoader;
  final WebOrderCheckout? orderCheckout;
  final WebOrderStatusLoader? orderStatusLoader;
  final WebPaymentLauncher? paymentLauncher;
  final WebOrdersLoader? ordersLoader;
  final WebOrderCanceler? orderCanceler;
  final WebActiveSubscriptionPlanLoader? activeSubscriptionPlanLoader;
  final WebPaymentCompletedNavigateHome? onPaymentCompletedNavigateHome;

  @override
  State<WebPurchasePage> createState() => _WebPurchasePageState();
}

class _WebPurchasePageState extends State<WebPurchasePage> {
  final _facade = WebAppFacade();
  final _couponController = TextEditingController();

  late Future<List<WebPlanViewData>> _plansFuture;
  Future<List<WebOrderListItemData>>? _ordersFuture;
  WebPlanFilter _filter = WebPlanFilter.all;
  _PurchaseStage _stage = _PurchaseStage.catalog;
  WebPlanViewData? _selectedPlan;
  WebPlanPeriod? _selectedPeriod;
  WebOrderDetailData? _order;
  List<WebPaymentMethodData> _paymentMethods = const <WebPaymentMethodData>[];
  WebPaymentMethodData? _selectedPaymentMethod;
  WebCheckoutActionData? _checkoutAction;
  _CheckoutOrigin _checkoutOrigin = _CheckoutOrigin.orderSetup;
  String? _message;
  String? _messageActionLabel;
  VoidCallback? _messageOnTap;
  String? _couponMessage;
  bool _isBusy = false;
  bool _isCheckingCoupon = false;
  bool _isPolling = false;
  bool _isDisposed = false;
  String? _busyOrderRef;

  bool _isChinese(BuildContext context) =>
      Localizations.localeOf(context).languageCode.toLowerCase().startsWith(
            'zh',
          );

  @override
  void initState() {
    super.initState();
    _plansFuture = _loadPlans();
    final initialOrderRef = widget.initialOrderRef;
    if (initialOrderRef != null && initialOrderRef.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(
            _openExistingOrder(initialOrderRef, widget.initialFallbackPlan));
      });
    }
  }

  @override
  void didUpdateWidget(covariant WebPurchasePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextOrderRef = widget.initialOrderRef;
    if (nextOrderRef != null &&
        nextOrderRef.isNotEmpty &&
        nextOrderRef != oldWidget.initialOrderRef) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_openExistingOrder(nextOrderRef, widget.initialFallbackPlan));
      });
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _couponController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WebPageFrame(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        layoutBuilder: (currentChild, previousChildren) => Stack(
          alignment: Alignment.topCenter,
          children: <Widget>[
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        ),
        child: KeyedSubtree(
          key: ValueKey<_PurchaseStage>(_stage),
          child: _buildStage(context),
        ),
      ),
    );
  }

  Widget _buildStage(BuildContext context) {
    switch (_stage) {
      case _PurchaseStage.catalog:
        return _buildCatalog(context);
      case _PurchaseStage.orders:
        return _buildOrders(context);
      case _PurchaseStage.orderSetup:
        return _buildOrderSetup(context);
      case _PurchaseStage.checkout:
        return _buildCheckout(context);
      case _PurchaseStage.paymentPending:
        return _buildPaymentPending(context);
    }
  }

  Widget _buildCatalog(BuildContext context) {
    final isChinese = _isChinese(context);
    final width = MediaQuery.of(context).size.width;
    final gap = WebLayoutMetrics.sectionGap(width);
    return FutureBuilder<List<WebPlanViewData>>(
      future: _plansFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _ErrorState(
            title: isChinese ? '套餐加载失败' : 'Plans failed to load',
            message: isChinese ? '请稍后重试，或刷新页面。' : 'Refresh and try again.',
            onRetry: _reloadPlans,
          );
        }
        if (!snapshot.hasData) {
          return const _LoadingState();
        }

        final plans = snapshot.data ?? const <WebPlanViewData>[];
        final filteredPlans = _filter == WebPlanFilter.all
            ? plans
            : plans.where((plan) => plan.filter == _filter).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            WebPageHero(
              title: isChinese ? '选择更适合你的套餐' : 'Choose a plan that fits you',
              subtitle: isChinese
                  ? '选择套餐后继续确认周期、优惠码和支付方式。'
                  : 'Choose a plan, then confirm the billing period, coupon code, and payment method.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: WebPlanFilter.values
                        .map(
                          (filter) => _FilterPill(
                            label: filter.label(isChinese),
                            selected: _filter == filter,
                            onTap: () => setState(() => _filter = filter),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
            SizedBox(height: gap),
            if (filteredPlans.isEmpty)
              _EmptyPanel(
                icon: Icons.inventory_2_outlined,
                title: isChinese ? '暂无可购买套餐' : 'No plans available',
                message: isChinese
                    ? '当前暂时没有可购买的套餐。'
                    : 'There are no purchasable plans right now.',
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final crossAxisCount = width >= 1320
                      ? 3
                      : width >= 820
                          ? 2
                          : 1;
                  final mainAxisExtent = crossAxisCount == 1
                      ? (width >= 640 ? 356.0 : 366.0)
                      : width >= 1180
                          ? 356.0
                          : 368.0;

                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      mainAxisExtent: mainAxisExtent,
                    ),
                    itemCount: filteredPlans.length,
                    itemBuilder: (context, index) {
                      final plan = filteredPlans[index];
                      return _PlanCard(
                        plan: plan,
                        selected: _selectedPlan?.id == plan.id,
                        isChinese: isChinese,
                        onTap: () => _openOrderSetup(plan),
                      );
                    },
                  );
                },
              ),
          ],
        );
      },
    );
  }

  Widget _buildOrderSetup(BuildContext context) {
    final isChinese = _isChinese(context);
    final plan = _selectedPlan;
    final period = _selectedPeriod;
    if (plan == null || period == null) {
      return _ErrorState(
        title: isChinese ? '未选择套餐' : 'No plan selected',
        message: isChinese ? '请返回套餐页重新选择。' : 'Go back and select a plan.',
        onRetry: _backToCatalog,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _BackHeader(
          title: isChinese ? '确认套餐' : 'Confirm plan',
          subtitle: isChinese
              ? '选择购买周期，可选填写优惠券。'
              : 'Choose a period and optionally apply a coupon.',
          label: isChinese ? '返回套餐' : 'Back to plans',
          onTap: _backToCatalog,
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 860;
            final children = <Widget>[
              Expanded(
                  child: _PlanSummaryCard(plan: plan, isChinese: isChinese)),
              const SizedBox(width: 16, height: 16),
              Expanded(
                child: _PeriodSelectorCard(
                  periods: plan.periods,
                  selected: period,
                  isChinese: isChinese,
                  onSelected: (value) {
                    setState(() {
                      _selectedPeriod = value;
                      _couponMessage = null;
                    });
                  },
                ),
              ),
            ];
            if (isWide) {
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _PlanSummaryCard(plan: plan, isChinese: isChinese),
                const SizedBox(height: 16),
                _PeriodSelectorCard(
                  periods: plan.periods,
                  selected: period,
                  isChinese: isChinese,
                  onSelected: (value) {
                    setState(() {
                      _selectedPeriod = value;
                      _couponMessage = null;
                    });
                  },
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        GradientCard(
          borderRadius: 28,
          padding: const EdgeInsets.all(18),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final validateLabel = isChinese ? '验证' : 'Validate';
              final buttonWidth = _estimateInlineButtonWidth(
                context,
                validateLabel,
                compact: true,
              );
              final stacked = buttonWidth + 220 > constraints.maxWidth;
              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _couponController,
                      enabled: !_isBusy,
                      decoration: InputDecoration(
                        labelText: isChinese ? '优惠券码' : 'Coupon code',
                        helperText: _couponMessage,
                      ),
                      onChanged: (_) {
                        if (_couponMessage != null) {
                          setState(() => _couponMessage = null);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    _InlineButton(
                      label: validateLabel,
                      isLoading: _isCheckingCoupon,
                      lowEmphasis: true,
                      expand: true,
                      compact: true,
                      onTap: _isBusy ? null : _validateCoupon,
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _couponController,
                      enabled: !_isBusy,
                      decoration: InputDecoration(
                        labelText: isChinese ? '优惠券码' : 'Coupon code',
                        helperText: _couponMessage,
                      ),
                      onChanged: (_) {
                        if (_couponMessage != null) {
                          setState(() => _couponMessage = null);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  _InlineButton(
                    label: validateLabel,
                    isLoading: _isCheckingCoupon,
                    lowEmphasis: true,
                    compact: true,
                    onTap: _isBusy ? null : _validateCoupon,
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        _CheckoutBar(
          amountLabel: period.moneyLabel,
          buttonLabel: isChinese
              ? '${period.moneyLabel} 前去支付'
              : 'Pay ${period.moneyLabel}',
          isLoading: _isBusy,
          onTap: _isBusy ? null : _createOrder,
        ),
        if (_message != null) ...[
          const SizedBox(height: 12),
          _MessageBanner(
            message: _message!,
            actionLabel: _messageActionLabel,
            onTap: _messageOnTap,
          ),
        ],
      ],
    );
  }

  Widget _buildOrders(BuildContext context) {
    final isChinese = _isChinese(context);
    final ordersFuture = _ordersFuture ??= _loadOrders();
    return FutureBuilder<List<WebOrderListItemData>>(
      future: ordersFuture,
      builder: (context, snapshot) {
        final cards = <Widget>[
          WebPageHero(
            title: isChinese ? '我的订单' : 'My Orders',
            subtitle: isChinese
                ? '查看待支付订单和历史订单，也可以继续支付或取消待支付订单。'
                : 'Review pending and historical orders.',
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _FilterPill(
                  label: isChinese ? '套餐' : 'Plans',
                  selected: false,
                  onTap: _backToCatalog,
                ),
                _FilterPill(
                  label: isChinese ? '我的订单' : 'My Orders',
                  selected: true,
                  onTap: _openOrders,
                ),
                _FilterPill(
                  label: isChinese ? '刷新列表' : 'Refresh',
                  selected: false,
                  onTap: _reloadOrders,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
        ];

        if (snapshot.hasError) {
          cards.add(
            _ErrorState(
              title: isChinese ? '订单加载失败' : 'Orders failed to load',
              message: webErrorText(
                snapshot.error!,
                isChinese: isChinese,
                context: WebErrorContext.pageLoad,
              ),
              onRetry: _reloadOrders,
            ),
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: cards,
          );
        }

        if (!snapshot.hasData) {
          cards.add(const _LoadingState());
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: cards,
          );
        }

        final orders = snapshot.data ?? const <WebOrderListItemData>[];
        if (orders.isEmpty) {
          cards.add(
            _EmptyPanel(
              icon: Icons.receipt_long_outlined,
              title: isChinese ? '还没有订单记录' : 'No orders yet',
              message: isChinese
                  ? '你创建过的订单会显示在这里。'
                  : 'Your orders will appear here.',
            ),
          );
        } else {
          cards.addAll(
            orders.map(
              (order) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _OrderListCard(
                  order: order,
                  isChinese: isChinese,
                  isBusy: _busyOrderRef == order.orderRef,
                  onContinue:
                      order.isPending ? () => _continueOrder(order) : null,
                  onCancel: order.isPending ? () => _cancelOrder(order) : null,
                ),
              ),
            ),
          );
        }

        if (_message != null) {
          cards.add(const SizedBox(height: 8));
          cards.add(
            _MessageBanner(
              message: _message!,
              actionLabel: _messageActionLabel,
              onTap: _messageOnTap,
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: cards,
        );
      },
    );
  }

  Widget _buildCheckout(BuildContext context) {
    final isChinese = _isChinese(context);
    final order = _order;
    final plan = order?.plan ?? _selectedPlan;
    if (order == null || plan == null) {
      return _ErrorState(
        title: isChinese ? '订单加载失败' : 'Order failed to load',
        message:
            isChinese ? '请返回购买页重新创建订单。' : 'Go back and create the order again.',
        onRetry: _backToCatalog,
      );
    }

    final method = _selectedPaymentMethod;
    final fee = method == null
        ? order.amountHandling
        : method.feeFor(order.amountDueBeforeFee);
    final payable = order.amountDueBeforeFee + fee;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _BackHeader(
          title: isChinese ? '订单支付' : 'Order payment',
          subtitle: isChinese
              ? '选择你想使用的支付方式完成结算。'
              : 'Choose your preferred payment method to complete checkout.',
          label: _checkoutOrigin == _CheckoutOrigin.orderSetup
              ? (isChinese ? '返回周期选择' : 'Back')
              : (isChinese ? '返回订单' : 'Back to orders'),
          onTap: _handleCheckoutBack,
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 860;
            final infoCards = <Widget>[
              Expanded(
                child: _OrderInfoCard(
                  title: isChinese ? '订阅信息' : 'Subscription',
                  icon: Icons.layers_outlined,
                  rows: <_InfoRowData>[
                    _InfoRowData(isChinese ? '订阅名称' : 'Plan', plan.title),
                    _InfoRowData(
                      isChinese ? '订阅类型' : 'Period',
                      _periodLabel(order.periodKey, isChinese),
                    ),
                    _InfoRowData(
                      isChinese ? '订阅流量' : 'Traffic',
                      plan.trafficLabel,
                    ),
                    _InfoRowData(
                      isChinese ? '订阅价格' : 'Price',
                      _money(order.amountOriginal),
                    ),
                    _InfoRowData(
                      isChinese ? '优惠金额' : 'Discount',
                      '- ${_money(order.amountDiscountApplied)}',
                    ),
                    _InfoRowData(
                      isChinese ? '使用余额' : 'Balance Used',
                      _money(order.amountBalanceUsed),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16, height: 16),
              Expanded(
                child: _OrderInfoCard(
                  title: isChinese ? '订单信息' : 'Order',
                  icon: Icons.receipt_long_outlined,
                  trailing: _StatusPill(
                    label: _statusLabel(order.stateCode, isChinese),
                  ),
                  rows: <_InfoRowData>[
                    _InfoRowData(
                        isChinese ? '订单号' : 'Order ref', order.orderRef),
                    _InfoRowData(
                      isChinese ? '创建时间' : 'Created',
                      Formatters.formatEpoch(order.createdAt),
                    ),
                    _InfoRowData(
                      isChinese ? '使用余额' : 'Balance',
                      _money(order.amountBalanceUsed),
                    ),
                    _InfoRowData(
                      isChinese ? '剩余价值抵扣' : 'Surplus Credit',
                      _money(order.amountSurplusCredit),
                    ),
                    _InfoRowData(isChinese ? '手续费' : 'Fee', _money(fee)),
                  ],
                ),
              ),
            ];
            if (isWide) {
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: infoCards,
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _OrderInfoCard(
                  title: isChinese ? '订阅信息' : 'Subscription',
                  icon: Icons.layers_outlined,
                  rows: <_InfoRowData>[
                    _InfoRowData(isChinese ? '订阅名称' : 'Plan', plan.title),
                    _InfoRowData(
                      isChinese ? '订阅类型' : 'Period',
                      _periodLabel(order.periodKey, isChinese),
                    ),
                    _InfoRowData(
                      isChinese ? '订阅流量' : 'Traffic',
                      plan.trafficLabel,
                    ),
                    _InfoRowData(
                      isChinese ? '订阅价格' : 'Price',
                      _money(order.amountOriginal),
                    ),
                    _InfoRowData(
                      isChinese ? '优惠金额' : 'Discount',
                      '- ${_money(order.amountDiscountApplied)}',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _OrderInfoCard(
                  title: isChinese ? '订单信息' : 'Order',
                  icon: Icons.receipt_long_outlined,
                  trailing: _StatusPill(
                    label: _statusLabel(order.stateCode, isChinese),
                  ),
                  rows: <_InfoRowData>[
                    _InfoRowData(
                        isChinese ? '订单号' : 'Order ref', order.orderRef),
                    _InfoRowData(
                      isChinese ? '创建时间' : 'Created',
                      Formatters.formatEpoch(order.createdAt),
                    ),
                    _InfoRowData(isChinese ? '手续费' : 'Fee', _money(fee)),
                  ],
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _PaymentMethodsCard(
          methods: _paymentMethods,
          selected: method,
          amountCents: order.amountDueBeforeFee,
          isChinese: isChinese,
          onSelected: (value) => setState(() => _selectedPaymentMethod = value),
        ),
        const SizedBox(height: 16),
        _CheckoutBar(
          amountLabel: _money(payable),
          buttonLabel: isChinese ? '结算' : 'Checkout',
          isLoading: _isBusy,
          onTap: _canCheckout(order) ? _checkoutOrder : null,
        ),
        if (_message != null) ...[
          const SizedBox(height: 12),
          _MessageBanner(
            message: _message!,
            actionLabel: _messageActionLabel,
            onTap: _messageOnTap,
          ),
        ],
      ],
    );
  }

  Widget _buildPaymentPending(BuildContext context) {
    final isChinese = _isChinese(context);
    final order = _order;
    final action = _checkoutAction;
    final payload = action?.payload?.toString() ?? '';
    final completed = action?.kind == WebCheckoutActionKind.completed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _BackHeader(
          title: completed
              ? (isChinese ? '订单已完成' : 'Order completed')
              : (isChinese ? '等待支付结果' : 'Waiting for payment'),
          subtitle: completed
              ? (isChinese
                  ? '订阅状态稍后会自动同步。'
                  : 'Subscription status will refresh shortly.')
              : (isChinese
                  ? '如果已经打开支付页面，请完成付款后返回这里确认结果。'
                  : 'Complete payment in the provider page, then confirm here.'),
          label: isChinese ? '返回支付方式' : 'Back to payment methods',
          onTap: () => setState(() => _stage = _PurchaseStage.checkout),
        ),
        const SizedBox(height: 16),
        GradientCard(
          borderRadius: 34,
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      completed
                          ? Icons.check_circle_outline_rounded
                          : Icons.payments_outlined,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      completed
                          ? (isChinese ? '支付已确认' : 'Payment confirmed')
                          : (isChinese ? '支付请求已创建' : 'Payment request created'),
                      style:
                          Theme.of(context).textTheme.displayMedium?.copyWith(
                                fontSize: 30,
                              ),
                    ),
                  ),
                  if (_isPolling)
                    const SizedBox(
                      width: 34,
                      height: 34,
                      child: CapybaraLoader(size: 34),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                _pendingMessage(action, isChinese),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 16,
                    ),
              ),
              if (action?.kind == WebCheckoutActionKind.qrCode &&
                  payload.isNotEmpty) ...[
                const SizedBox(height: 22),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: QrImageView(
                      data: payload,
                      size: 220,
                      backgroundColor: Colors.white,
                    ),
                  ),
                ),
              ] else if (action?.kind == WebCheckoutActionKind.inlineFallback &&
                  payload.isNotEmpty) ...[
                const SizedBox(height: 18),
                SelectableText(
                  payload,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _InlineButton(
                    label: completed
                        ? (isChinese ? '返回首页' : 'Back to Home')
                        : (isChinese ? '我已完成支付' : 'I have paid'),
                    isLoading: _isBusy,
                    onTap: order == null
                        ? null
                        : (completed
                            ? _returnHomeAfterPayment
                            : _checkPaymentOnce),
                  ),
                  _InlineButton(
                    label: isChinese ? '返回套餐' : 'Back to plans',
                    onTap: _backToCatalog,
                    lowEmphasis: true,
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_message != null) ...[
          const SizedBox(height: 12),
          _MessageBanner(
            message: _message!,
            actionLabel: _messageActionLabel,
            onTap: _messageOnTap,
          ),
        ],
      ],
    );
  }

  Future<List<WebPlanViewData>> _loadPlans() {
    return (widget.plansLoader ?? _loadPlansFromApi)();
  }

  Future<void> _openExistingOrder(
    String orderRef,
    WebPlanViewData? fallbackPlan,
  ) async {
    setState(() {
      _isBusy = true;
      _clearMessage();
    });
    try {
      _checkoutOrigin = _CheckoutOrigin.externalOrder;
      await _loadCheckoutData(orderRef, fallbackPlan);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = webErrorText(
          error,
          isChinese: _isChinese(context),
          context: WebErrorContext.pageLoad,
        );
      });
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<List<WebOrderListItemData>> _loadOrders() {
    final loader = widget.ordersLoader ?? _loadOrdersFromApi;
    return loader();
  }

  Future<List<WebPlanViewData>> _loadPlansFromApi() async {
    return _facade.loadPlans();
  }

  Future<List<WebOrderListItemData>> _loadOrdersFromApi() async {
    return _facade.loadOrders();
  }

  void _reloadPlans() {
    setState(() {
      _plansFuture = _loadPlans();
      _clearMessage();
    });
  }

  void _reloadOrders() {
    setState(() {
      _ordersFuture = _loadOrders();
      _clearMessage();
    });
  }

  void _openOrders() {
    setState(() {
      _stage = _PurchaseStage.orders;
      _ordersFuture = _loadOrders();
      _clearMessage();
    });
  }

  void _openOrderSetup(WebPlanViewData plan) {
    final period = plan.primaryPeriod;
    if (period == null) return;
    setState(() {
      _selectedPlan = plan;
      _selectedPeriod = period;
      _order = null;
      _paymentMethods = const <WebPaymentMethodData>[];
      _selectedPaymentMethod = null;
      _checkoutAction = null;
      _checkoutOrigin = _CheckoutOrigin.orderSetup;
      _couponController.clear();
      _couponMessage = null;
      _clearMessage();
      _stage = _PurchaseStage.orderSetup;
    });
  }

  void _backToCatalog() {
    setState(() {
      _stage = _PurchaseStage.catalog;
      _clearMessage();
      _couponMessage = null;
      _checkoutAction = null;
      _isPolling = false;
    });
  }

  void _clearMessage() {
    _message = null;
    _messageActionLabel = null;
    _messageOnTap = null;
  }

  Future<void> _validateCoupon() async {
    final plan = _selectedPlan;
    final period = _selectedPeriod;
    final code = _couponController.text.trim();
    if (plan == null || period == null) return;
    if (code.isEmpty) {
      setState(() => _couponMessage =
          _isChinese(context) ? '请输入优惠券码' : 'Enter a coupon code');
      return;
    }
    setState(() {
      _isCheckingCoupon = true;
      _couponMessage = null;
    });
    try {
      final validator = widget.couponValidator ?? _validateCouponFromApi;
      await validator(plan.id, period.key, code);
      if (!mounted) return;
      setState(() {
        _couponMessage = _isChinese(context)
            ? '优惠券可用，创建订单时会自动应用。'
            : 'Coupon is valid and will be applied.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _couponMessage = _isChinese(context)
            ? '优惠券不可用或不适用于当前套餐。'
            : 'Coupon is not available for this plan.';
      });
    } finally {
      if (mounted) {
        setState(() => _isCheckingCoupon = false);
      }
    }
  }

  Future<void> _validateCouponFromApi(
    int planId,
    String periodKey,
    String couponCode,
  ) async {
    await _facade.validateCoupon(planId, periodKey, couponCode);
  }

  Future<void> _createOrder() async {
    final plan = _selectedPlan;
    final period = _selectedPeriod;
    if (plan == null || period == null) return;
    final couponCode = _couponController.text.trim().isEmpty
        ? null
        : _couponController.text.trim();
    final confirmed = await _confirmPlanChangeIfNeeded(plan, period);
    if (!confirmed || !mounted) {
      return;
    }
    setState(() {
      _isBusy = true;
      _clearMessage();
    });
    try {
      final create = widget.orderCreator ?? _createOrderFromApi;
      final tradeNo = await create(
        plan.id,
        period.key,
        couponCode,
      );
      _checkoutOrigin = _CheckoutOrigin.orderSetup;
      await _loadCheckoutData(tradeNo, plan);
    } on PendingOrderExistsException {
      final recovered = await _recoverPendingOrder(plan, period, couponCode);
      if (!recovered && mounted) {
        setState(() {
          _message = _isChinese(context)
              ? '检测到已有待支付订单，请前往我的订单继续处理。'
              : 'A pending order already exists.';
          _messageActionLabel =
              _isChinese(context) ? '查看我的订单' : 'Open My Orders';
          _messageOnTap = widget.onOpenUserOrders ?? _openOrders;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = webErrorText(
            error,
            isChinese: _isChinese(context),
            context: WebErrorContext.general,
          );
          _messageActionLabel = null;
          _messageOnTap = null;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<String> _createOrderFromApi(
    int planId,
    String periodKey,
    String? couponCode,
  ) async {
    return _facade.createOrder(planId, periodKey, couponCode);
  }

  Future<int?> _loadActiveSubscriptionPlanIdFromApi() {
    return _facade.loadActiveSubscriptionPlanId();
  }

  Future<bool> _confirmPlanChangeIfNeeded(
    WebPlanViewData plan,
    WebPlanPeriod period,
  ) async {
    if (period.key == 'reset_price') {
      return true;
    }
    if (widget.activeSubscriptionPlanLoader == null &&
        widget.orderCreator != null) {
      return true;
    }
    final loader = widget.activeSubscriptionPlanLoader ??
        _loadActiveSubscriptionPlanIdFromApi;
    final currentPlanId = await loader();
    if (!mounted || currentPlanId == null || currentPlanId <= 0) {
      return true;
    }
    if (currentPlanId == plan.id) {
      return true;
    }
    final isChinese = _isChinese(context);
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => _OrderConfirmDialog(
            title: isChinese ? '请确认订阅变更' : 'Confirm subscription change',
            message: isChinese
                ? '当前已有有效订阅。继续购买新的套餐后，现有订阅将被覆盖。'
                : 'You already have an active subscription. Continuing will replace the current subscription.',
            cancelLabel: isChinese ? '取消' : 'Cancel',
            confirmLabel: isChinese ? '继续购买' : 'Continue',
          ),
        ) ??
        false;
    return confirmed;
  }

  Future<bool> _recoverPendingOrder(
    WebPlanViewData fallbackPlan,
    WebPlanPeriod selectedPeriod,
    String? couponCode,
  ) async {
    if (couponCode != null && couponCode.trim().isNotEmpty) {
      return false;
    }
    try {
      final recover =
          widget.pendingOrderRecoverer ?? _recoverPendingOrderFromApi;
      final orderRef = await recover(
        fallbackPlan,
        selectedPeriod,
        couponCode,
      );
      if (orderRef == null) return false;
      await _loadCheckoutData(orderRef, fallbackPlan);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _recoverPendingOrderFromApi(
    WebPlanViewData plan,
    WebPlanPeriod period,
    String? couponCode,
  ) {
    return _facade.recoverMatchingPendingOrderRef(
      plan: plan,
      period: period,
      couponCode: couponCode,
    );
  }

  Future<void> _loadCheckoutData(
    String orderRef,
    WebPlanViewData? fallbackPlan,
  ) async {
    final detailLoader = widget.orderDetailLoader ?? _loadOrderDetailFromApi;
    final methodsLoader =
        widget.paymentMethodsLoader ?? _loadPaymentMethodsFromApi;
    final results = await Future.wait<Object>([
      detailLoader(orderRef, fallbackPlan),
      methodsLoader(),
    ]);
    final order = results[0] as WebOrderDetailData;
    final methods = results[1] as List<WebPaymentMethodData>;
    if (!mounted) return;
    setState(() {
      _order = order;
      _paymentMethods = methods;
      _selectedPaymentMethod = methods.isEmpty ? null : methods.first;
      _checkoutAction = null;
      _clearMessage();
      _stage = _PurchaseStage.checkout;
    });
  }

  Future<WebOrderDetailData> _loadOrderDetailFromApi(
    String orderRef,
    WebPlanViewData? fallbackPlan,
  ) async {
    return _facade.loadOrderDetail(orderRef, fallbackPlan);
  }

  Future<List<WebPaymentMethodData>> _loadPaymentMethodsFromApi() async {
    return _facade.loadPaymentMethods();
  }

  Future<void> _continueOrder(WebOrderListItemData order) async {
    if (_busyOrderRef != null) return;
    setState(() {
      _busyOrderRef = order.orderRef;
      _clearMessage();
    });
    try {
      _checkoutOrigin = _CheckoutOrigin.orderList;
      await _loadCheckoutData(order.orderRef, order.plan);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = webErrorText(
          error,
          isChinese: _isChinese(context),
          context: WebErrorContext.pageLoad,
        );
      });
    } finally {
      if (mounted) {
        setState(() => _busyOrderRef = null);
      }
    }
  }

  Future<void> _cancelOrder(WebOrderListItemData order) async {
    if (_busyOrderRef != null) return;
    final isChinese = _isChinese(context);
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => _OrderConfirmDialog(
            title: isChinese ? '取消这个订单？' : 'Cancel this order?',
            message: isChinese
                ? '取消后，这笔待支付订单将无法继续支付。'
                : 'This pending order will no longer be payable.',
            cancelLabel: isChinese ? '再想想' : 'Keep',
            confirmLabel: isChinese ? '确认取消' : 'Cancel Order',
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    setState(() {
      _busyOrderRef = order.orderRef;
      _clearMessage();
    });
    try {
      final canceler = widget.orderCanceler ?? _cancelOrderFromApi;
      await canceler(order.orderRef);
      if (!mounted) return;
      setState(() {
        _ordersFuture = _loadOrders();
        _message = isChinese ? '订单已取消。' : 'Order canceled.';
        _messageActionLabel = null;
        _messageOnTap = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = webErrorText(
          error,
          isChinese: isChinese,
          context: WebErrorContext.general,
        );
      });
    } finally {
      if (mounted) {
        setState(() => _busyOrderRef = null);
      }
    }
  }

  Future<void> _cancelOrderFromApi(String orderRef) async {
    await _facade.cancelOrder(orderRef);
  }

  bool _canCheckout(WebOrderDetailData order) {
    if (_isBusy) return false;
    if (order.amountDueBeforeFee <= 0) return true;
    return _selectedPaymentMethod != null;
  }

  Future<void> _checkoutOrder() async {
    final order = _order;
    if (order == null) return;
    final method = _selectedPaymentMethod;
    if (order.amountDueBeforeFee > 0 && method == null) {
      setState(() {
        _message =
            _isChinese(context) ? '请选择支付方式。' : 'Select a payment method.';
        _messageActionLabel = null;
        _messageOnTap = null;
      });
      return;
    }
    setState(() {
      _isBusy = true;
      _clearMessage();
    });
    try {
      final checkout = widget.orderCheckout ?? _checkoutOrderFromApi;
      final action = await checkout(order.orderRef, method?.id ?? 0);
      if (!mounted) return;
      setState(() {
        _checkoutAction = action;
        _stage = _PurchaseStage.paymentPending;
      });
      await _handleCheckoutAction(action, order.orderRef);
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = webErrorText(
            error,
            isChinese: _isChinese(context),
            context: WebErrorContext.general,
          );
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<WebCheckoutActionData> _checkoutOrderFromApi(
    String orderRef,
    int methodId,
  ) async {
    return _facade.checkoutOrder(orderRef, methodId);
  }

  Future<void> _handleCheckoutAction(
    WebCheckoutActionData action,
    String orderRef,
  ) async {
    switch (action.kind) {
      case WebCheckoutActionKind.redirect:
        final url = action.payload?.toString() ?? '';
        final uri = Uri.tryParse(url);
        if (uri == null || !uri.hasScheme) {
          setState(() {
            _message =
                _isChinese(context) ? '支付链接无效。' : 'Invalid payment link.';
          });
          return;
        }
        final launcher = widget.paymentLauncher ?? _launchPaymentUrl;
        final launched = await launcher(uri);
        if (!mounted) return;
        setState(() {
          _message = launched
              ? (_isChinese(context)
                  ? '已打开支付页面，完成后返回这里确认。'
                  : 'Payment page opened. Return here after payment.')
              : (_isChinese(context)
                  ? '浏览器未能打开支付页面，请复制链接手动打开。'
                  : 'Could not open payment page. Copy the link manually.');
        });
        unawaited(_startPolling(orderRef));
        break;
      case WebCheckoutActionKind.qrCode:
      case WebCheckoutActionKind.inlineFallback:
        unawaited(_startPolling(orderRef));
        break;
      case WebCheckoutActionKind.completed:
        await _markPaymentComplete(orderRef);
        break;
    }
  }

  Future<bool> _launchPaymentUrl(Uri uri) {
    return launchUrl(uri, webOnlyWindowName: '_blank');
  }

  Future<void> _startPolling(String orderRef) async {
    if (_isPolling) return;
    _isPolling = true;
    if (mounted) setState(() {});
    try {
      for (var attempt = 0; attempt < 60; attempt++) {
        if (_isDisposed) return;
        final state = await _loadOrderStatus(orderRef);
        if (state == 1 || state == 3) {
          await _markPaymentComplete(orderRef);
          return;
        }
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      if (mounted) {
        setState(() {
          _message = _isChinese(context)
              ? '暂未确认支付结果。若已支付，请稍后刷新账户状态。'
              : 'Payment has not been confirmed yet. Check again later.';
        });
      }
    } finally {
      _isPolling = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _checkPaymentOnce() async {
    final order = _order;
    if (order == null) return;
    setState(() {
      _isBusy = true;
      _message = null;
    });
    try {
      final state = await _loadOrderStatus(order.orderRef);
      if (state == 1 || state == 3) {
        await _markPaymentComplete(order.orderRef, navigateHome: true);
      } else if (mounted) {
        setState(() {
          _message = _isChinese(context)
              ? '还没有收到支付确认。'
              : 'Payment is not confirmed yet.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<int> _loadOrderStatus(String orderRef) {
    final loader = widget.orderStatusLoader ?? _loadOrderStatusFromApi;
    return loader(orderRef);
  }

  Future<int> _loadOrderStatusFromApi(String orderRef) async {
    return _facade.loadOrderStatus(orderRef);
  }

  Future<void> _markPaymentComplete(
    String orderRef, {
    bool navigateHome = false,
  }) async {
    final action = WebCheckoutActionData(
      kind: WebCheckoutActionKind.completed,
      code: -1,
      payload: true,
    );
    WebOrderDetailData? latest;
    try {
      latest = await (widget.orderDetailLoader ?? _loadOrderDetailFromApi)(
        orderRef,
        _selectedPlan,
      );
    } catch (_) {
      latest = _order;
    }
    if (!mounted) return;
    if (navigateHome) {
      _returnHomeAfterPayment();
      return;
    }
    setState(() {
      _checkoutAction = action;
      _order = latest;
      _stage = _PurchaseStage.paymentPending;
      _message = _isChinese(context) ? '订单已完成，订阅状态会自动同步。' : 'Order completed.';
      _messageActionLabel = null;
      _messageOnTap = null;
    });
  }

  void _returnHomeAfterPayment() {
    if (widget.onPaymentCompletedNavigateHome != null) {
      widget.onPaymentCompletedNavigateHome!.call();
      return;
    }
    _backToCatalog();
  }

  void _handleCheckoutBack() {
    switch (_checkoutOrigin) {
      case _CheckoutOrigin.orderSetup:
        setState(() {
          _stage = _PurchaseStage.orderSetup;
          _clearMessage();
        });
        break;
      case _CheckoutOrigin.orderList:
        setState(() {
          _stage = _PurchaseStage.orders;
          _ordersFuture ??= _loadOrders();
          _clearMessage();
        });
        break;
      case _CheckoutOrigin.externalOrder:
        if (widget.onOpenUserOrders != null) {
          widget.onOpenUserOrders!.call();
          return;
        }
        setState(() {
          _stage = _PurchaseStage.orders;
          _ordersFuture ??= _loadOrders();
          _clearMessage();
        });
        break;
    }
  }

  String _money(int cents) => '¥${Formatters.formatCurrency(cents)}';

  String _periodLabel(String key, bool isChinese) {
    final period = WebPlanPeriod.all.firstWhere(
      (item) => item.key == key,
      orElse: () => WebPlanPeriod(
        key: key,
        amountField: key,
        zhLabel: key,
        enLabel: key,
        amountCents: 0,
      ),
    );
    return period.label(isChinese);
  }

  String _statusLabel(int state, bool isChinese) {
    switch (state) {
      case 1:
      case 3:
        return isChinese ? '已完成' : 'Completed';
      case 2:
        return isChinese ? '已取消' : 'Canceled';
      default:
        return isChinese ? '待支付' : 'Pending';
    }
  }

  String _pendingMessage(WebCheckoutActionData? action, bool isChinese) {
    switch (action?.kind) {
      case WebCheckoutActionKind.redirect:
        return isChinese
            ? '支付页面已在新窗口打开。完成付款后，系统会自动检测订单状态。'
            : 'The payment page opened in a new window. We will check the order automatically.';
      case WebCheckoutActionKind.qrCode:
        return isChinese
            ? '请使用对应支付 App 扫描二维码完成付款。'
            : 'Scan the QR code with the matching payment app.';
      case WebCheckoutActionKind.completed:
        return isChinese ? '订单已经开通成功。' : 'The order has been activated.';
      case WebCheckoutActionKind.inlineFallback:
      case null:
        return isChinese
            ? '支付商返回了非跳转结果，请按页面提示完成付款。'
            : 'The provider returned an inline payment action. Follow the instructions shown.';
    }
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accent.withValues(alpha: 0.14)
              : AppColors.surfaceAlt.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? AppColors.accent.withValues(alpha: 0.3)
                : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.textPrimary : AppColors.textSecondary,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.selected,
    required this.isChinese,
    required this.onTap,
  });

  final WebPlanViewData plan;
  final bool selected;
  final bool isChinese;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final compact = WebLayoutMetrics.compact(width);
    final primary = plan.primaryPeriod;
    return AnimatedCard(
      onTap: onTap,
      padding: EdgeInsets.all(compact ? 18 : 20),
      enableBreathing: selected,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  plan.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(
                        fontSize: compact ? 24 : 26,
                        height: 1.05,
                      ),
                ),
              ),
              const SizedBox(width: 12),
              _SoftBadge(label: plan.trafficLabel),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            plan.summary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: 15,
                ),
          ),
          const SizedBox(height: 18),
          ...plan.features.take(3).map(
                (feature) => Padding(
                  padding: EdgeInsets.only(bottom: compact ? 6 : 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 5),
                        child: Icon(
                          Icons.brightness_1_rounded,
                          size: 6,
                          color: AppColors.accent,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          feature,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: AppColors.textPrimary,
                                    height: 1.4,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          const Spacer(),
          Text(
            plan.deviceLimit == null
                ? (isChinese
                    ? '设备数量以当前套餐说明为准'
                    : 'Device availability follows the current plan details')
                : (isChinese
                    ? '最多支持 ${plan.deviceLimit} 台设备同时在线使用'
                    : 'Up to ${plan.deviceLimit} devices online'),
            style:
                Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13),
          ),
          SizedBox(height: compact ? 14 : 18),
          Row(
            children: [
              Text(
                primary?.label(isChinese) ?? (isChinese ? '可购买' : 'Available'),
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontSize: 13),
              ),
              const Spacer(),
              Text(
                primary?.moneyLabel ?? '¥0',
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      fontSize: compact ? 30 : 34,
                    ),
              ),
            ],
          ),
          SizedBox(height: compact ? 12 : 14),
          _OutlineAction(
            label: isChinese ? '立即购买' : 'Purchase Now',
            selected: selected,
            onTap: onTap,
          ),
        ],
      ),
    );
  }
}

class _PlanSummaryCard extends StatelessWidget {
  const _PlanSummaryCard({
    required this.plan,
    required this.isChinese,
  });

  final WebPlanViewData plan;
  final bool isChinese;

  @override
  Widget build(BuildContext context) {
    final hasRichContent = plan.richContentHtml.trim().isNotEmpty;
    final width = MediaQuery.of(context).size.width;
    final compact = WebLayoutMetrics.compact(width);

    return GradientCard(
      borderRadius: 32,
      padding: EdgeInsets.all(compact ? 20 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            plan.title,
            style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  fontSize: compact ? 28 : 30,
                ),
          ),
          const SizedBox(height: 12),
          Text(
            isChinese
                ? '包含流量 ${plan.trafficLabel}'
                : 'Traffic ${plan.trafficLabel}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: compact ? 16 : 18,
                ),
          ),
          SizedBox(height: compact ? 20 : 28),
          if (hasRichContent)
            RichContentView(
              key: Key('web-plan-rich-content-${plan.id}'),
              html: plan.richContentHtml,
            )
          else
            ...plan.features.take(5).map(
                  (feature) => Padding(
                    padding: EdgeInsets.only(bottom: compact ? 8 : 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.check_circle_outline_rounded,
                          color: AppColors.textSecondary,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            feature,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: AppColors.textPrimary,
                                  height: 1.45,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          SizedBox(height: compact ? 20 : 24),
          Text(
            plan.deviceLimit == null
                ? (isChinese
                    ? '设备数量以当前套餐说明为准'
                    : 'Device availability follows the current plan details')
                : (isChinese
                    ? '最多支持 ${plan.deviceLimit} 台设备同时在线使用'
                    : 'Up to ${plan.deviceLimit} devices online'),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _PeriodSelectorCard extends StatelessWidget {
  const _PeriodSelectorCard({
    required this.periods,
    required this.selected,
    required this.isChinese,
    required this.onSelected,
  });

  final List<WebPlanPeriod> periods;
  final WebPlanPeriod selected;
  final bool isChinese;
  final ValueChanged<WebPlanPeriod> onSelected;

  @override
  Widget build(BuildContext context) {
    final compact = WebLayoutMetrics.compact(MediaQuery.of(context).size.width);
    return GradientCard(
      borderRadius: 32,
      padding: EdgeInsets.all(compact ? 20 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isChinese ? '选择周期' : 'Choose period',
            style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  fontSize: compact ? 24 : 26,
                ),
          ),
          SizedBox(height: compact ? 14 : 18),
          ...periods.map(
            (period) => Padding(
              padding: EdgeInsets.only(bottom: compact ? 10 : 12),
              child: _SelectableRow(
                selected: selected.key == period.key,
                onTap: () => onSelected(period),
                leading: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      period.label(isChinese),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      period.moneyLabel,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderInfoCard extends StatelessWidget {
  const _OrderInfoCard({
    required this.title,
    required this.icon,
    required this.rows,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final List<_InfoRowData> rows;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final compact = WebLayoutMetrics.compact(MediaQuery.of(context).size.width);
    return GradientCard(
      borderRadius: 32,
      padding: EdgeInsets.all(compact ? 20 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.textSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(
                        fontSize: compact ? 24 : 26,
                      ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          SizedBox(height: compact ? 18 : 22),
          ...rows.map(
            (row) => Padding(
              padding: EdgeInsets.only(bottom: compact ? 12 : 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      row.label,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      row.value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentMethodsCard extends StatelessWidget {
  const _PaymentMethodsCard({
    required this.methods,
    required this.selected,
    required this.amountCents,
    required this.isChinese,
    required this.onSelected,
  });

  final List<WebPaymentMethodData> methods;
  final WebPaymentMethodData? selected;
  final int amountCents;
  final bool isChinese;
  final ValueChanged<WebPaymentMethodData> onSelected;

  @override
  Widget build(BuildContext context) {
    return GradientCard(
      borderRadius: 32,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_wallet_outlined,
                  color: AppColors.accent),
              const SizedBox(width: 10),
              Text(
                isChinese ? '选择支付方式' : 'Payment method',
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      fontSize: 24,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (methods.isEmpty)
            _EmptyPanel(
              icon: Icons.credit_card_off_outlined,
              title: isChinese ? '暂无可用支付方式' : 'No payment methods',
              message: isChinese
                  ? '当前暂时没有可用的支付方式，请稍后再试或联系客服。'
                  : 'There are no payment methods available right now. Please try again later or contact support.',
            )
          else
            ...methods.map(
              (method) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _SelectableRow(
                  selected: selected?.id == method.id,
                  onTap: () => onSelected(method),
                  leading: Row(
                    children: [
                      _PaymentIcon(method: method),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              method.label.isEmpty
                                  ? (isChinese ? '支付方式' : 'Payment method')
                                  : method.label,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            if (method.feeFixedCents > 0 || method.feeRate > 0)
                              Text(
                                isChinese
                                    ? '手续费 ${_feeText(method)}'
                                    : 'Fee ${_feeText(method)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _feeText(WebPaymentMethodData method) {
    final parts = <String>[];
    if (method.feeFixedCents > 0) {
      parts.add('¥${Formatters.formatCurrency(method.feeFixedCents)}');
    }
    if (method.feeRate > 0) {
      parts.add(
          '${method.feeRate.toStringAsFixed(method.feeRate % 1 == 0 ? 0 : 2)}%');
    }
    if (parts.isEmpty) return '0';
    final estimate = method.feeFor(amountCents);
    return '${parts.join(' + ')} · 预计 ¥${Formatters.formatCurrency(estimate)}';
  }
}

class _PaymentIcon extends StatelessWidget {
  const _PaymentIcon({required this.method});

  final WebPaymentMethodData method;

  @override
  Widget build(BuildContext context) {
    final icon = method.iconUrl;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: AppColors.surfaceAlt.withValues(alpha: 0.9),
      ),
      child: icon != null && Uri.tryParse(icon)?.hasScheme == true
          ? ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                icon,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.account_balance_wallet_outlined,
                  color: AppColors.textSecondary,
                ),
              ),
            )
          : Center(
              child: Text(
                icon?.isNotEmpty == true ? icon! : '¥',
                style: const TextStyle(fontSize: 18),
              ),
            ),
    );
  }
}

class _SelectableRow extends StatelessWidget {
  const _SelectableRow({
    required this.selected,
    required this.onTap,
    required this.leading,
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget leading;

  @override
  Widget build(BuildContext context) {
    return AnimatedCard(
      onTap: onTap,
      enableBreathing: selected,
      borderRadius: 22,
      hoverScale: 1.01,
      baseBorderColor: selected ? AppColors.accent : AppColors.border,
      hoverBorderColor: AppColors.accent,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Row(
        children: [
          Expanded(child: leading),
          const SizedBox(width: 14),
          Icon(
            selected
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
            color: selected ? AppColors.accent : AppColors.textSecondary,
          ),
        ],
      ),
    );
  }
}

class _BackHeader extends StatelessWidget {
  const _BackHeader({
    required this.title,
    required this.subtitle,
    required this.label,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.displayLarge?.copyWith(
                      fontSize: 42,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 16,
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        _InlineButton(
          label: label,
          icon: Icons.arrow_back_rounded,
          lowEmphasis: true,
          onTap: onTap,
        ),
      ],
    );
  }
}

class _CheckoutBar extends StatelessWidget {
  const _CheckoutBar({
    required this.amountLabel,
    required this.buttonLabel,
    required this.isLoading,
    required this.onTap,
  });

  final String amountLabel;
  final String buttonLabel;
  final bool isLoading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GradientCard(
      borderRadius: 30,
      padding: const EdgeInsets.all(18),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final amountText = '总计：$amountLabel';
          final amountStyle =
              Theme.of(context).textTheme.displayMedium?.copyWith(
                        fontSize: 24,
                      ) ??
                  const TextStyle(fontSize: 24);
          final amountWidth =
              _measureTextWidth(context, amountText, amountStyle) + 4;
          final buttonWidth = math.min(
            320.0,
            math.max(220.0, constraints.maxWidth * 0.44),
          );
          final stacked = amountWidth + 16 + buttonWidth > constraints.maxWidth;
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    amountText,
                    style: amountStyle,
                  ),
                ),
                const SizedBox(height: 14),
                _InlineButton(
                  label: buttonLabel,
                  isLoading: isLoading,
                  expand: true,
                  onTap: onTap,
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    amountText,
                    style: amountStyle,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: buttonWidth,
                child: _InlineButton(
                  label: buttonLabel,
                  isLoading: isLoading,
                  onTap: onTap,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _InlineButton extends StatelessWidget {
  const _InlineButton({
    required this.label,
    this.onTap,
    this.icon,
    this.isLoading = false,
    this.lowEmphasis = false,
    this.expand = false,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool isLoading;
  final bool lowEmphasis;
  final bool expand;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !isLoading;
    return AnimatedCard(
      onTap: isLoading ? null : onTap,
      enableBreathing: false,
      borderRadius: 18,
      hoverScale: 1.008,
      baseBorderColor: enabled
          ? (lowEmphasis
              ? AppColors.border.withValues(alpha: 0.95)
              : AppColors.accent.withValues(alpha: 0.48))
          : AppColors.border.withValues(alpha: 0.9),
      hoverBorderColor: AppColors.accent,
      gradientColors: lowEmphasis
          ? [
              AppColors.surfaceAlt.withValues(alpha: 0.98),
              AppColors.surface.withValues(alpha: 0.98),
            ]
          : [
              const Color(0xFF1C1F27),
              const Color(0xFF15171D),
            ],
      baseBoxShadows: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.22),
          blurRadius: 18,
          offset: const Offset(0, 10),
        ),
      ],
      hoverBoxShadows: [
        BoxShadow(
          color: AppColors.accent.withValues(alpha: 0.12),
          blurRadius: 24,
          offset: const Offset(0, 12),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.26),
          blurRadius: 20,
          offset: const Offset(0, 10),
        ),
      ],
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 16 : 18,
        vertical: compact ? 12 : 14,
      ),
      child: Center(
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              const SizedBox(
                width: 18,
                height: 18,
                child: CapybaraLoader(size: 18),
              )
            else if (icon != null)
              Icon(
                icon,
                size: 18,
                color:
                    enabled ? AppColors.textPrimary : AppColors.textSecondary,
              ),
            if (isLoading || icon != null) const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color:
                    enabled ? AppColors.textPrimary : AppColors.textSecondary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

double _measureTextWidth(
  BuildContext context,
  String text,
  TextStyle? style,
) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    maxLines: 1,
    textDirection: Directionality.of(context),
  )..layout();
  return painter.width;
}

double _estimateInlineButtonWidth(
  BuildContext context,
  String label, {
  bool compact = false,
}) {
  final textStyle = const TextStyle(fontWeight: FontWeight.w800);
  final horizontal = compact ? 16.0 : 18.0;
  return _measureTextWidth(context, label, textStyle) + horizontal * 2 + 8;
}

class _OutlineAction extends StatelessWidget {
  const _OutlineAction({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected
                    ? AppColors.accent.withValues(alpha: 0.82)
                    : AppColors.border.withValues(alpha: 0.95),
                width: selected ? 1.2 : 1,
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  selected
                      ? AppColors.accent.withValues(alpha: 0.10)
                      : AppColors.surface.withValues(alpha: 0.36),
                  AppColors.surfaceAlt.withValues(alpha: 0.64),
                ],
              ),
            ),
            child: Center(
              child: Text(
                label,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: AppColors.accent.withValues(alpha: 0.12),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SoftBadge extends StatelessWidget {
  const _SoftBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: AppColors.surfaceAlt.withValues(alpha: 0.9),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _OrderListCard extends StatelessWidget {
  const _OrderListCard({
    required this.order,
    required this.isChinese,
    required this.isBusy,
    this.onContinue,
    this.onCancel,
  });

  final WebOrderListItemData order;
  final bool isChinese;
  final bool isBusy;
  final VoidCallback? onContinue;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return GradientCard(
      borderRadius: 28,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  order.plan?.title ?? (isChinese ? '套餐订单' : 'Order'),
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(
                        fontSize: 26,
                      ),
                ),
              ),
              const SizedBox(width: 12),
              _StatusPill(label: _orderStatusLabel(order.stateCode, isChinese)),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 18,
            runSpacing: 12,
            children: [
              _OrderMetaItem(
                label: isChinese ? '订单号' : 'Order Ref',
                value: order.orderRef,
              ),
              _OrderMetaItem(
                label: isChinese ? '周期' : 'Period',
                value: _orderPeriodLabel(order.periodKey, isChinese),
              ),
              _OrderMetaItem(
                label: isChinese ? '金额' : 'Amount',
                value: '¥${Formatters.formatCurrency(order.amountDueAfterFee)}',
              ),
              _OrderMetaItem(
                label: isChinese ? '创建时间' : 'Created',
                value: Formatters.formatEpoch(order.createdAt),
              ),
            ],
          ),
          if (order.isPending) ...[
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _InlineButton(
                    label: isChinese ? '继续支付' : 'Continue Payment',
                    isLoading: isBusy,
                    onTap: onContinue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _InlineButton(
                    label: isChinese ? '取消订单' : 'Cancel Order',
                    lowEmphasis: true,
                    onTap: isBusy ? null : onCancel,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _OrderMetaItem extends StatelessWidget {
  const _OrderMetaItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final compact = WebLayoutMetrics.compact(MediaQuery.of(context).size.width);
    return SizedBox(
      width: compact ? 170 : 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _MessageBanner extends StatelessWidget {
  const _MessageBanner({
    required this.message,
    this.actionLabel,
    this.onTap,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GradientCard(
      borderRadius: 22,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded,
              color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          if (actionLabel != null && onTap != null) ...[
            const SizedBox(width: 12),
            _InlineButton(
              label: actionLabel!,
              lowEmphasis: true,
              onTap: onTap,
            ),
          ],
        ],
      ),
    );
  }
}

class _OrderConfirmDialog extends StatelessWidget {
  const _OrderConfirmDialog({
    required this.title,
    required this.message,
    required this.cancelLabel,
    required this.confirmLabel,
  });

  final String title;
  final String message;
  final String cancelLabel;
  final String confirmLabel;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: GradientCard(
        borderRadius: 32,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.displayMedium?.copyWith(
                    fontSize: 30,
                  ),
            ),
            const SizedBox(height: 14),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: _InlineButton(
                    label: cancelLabel,
                    lowEmphasis: true,
                    onTap: () => Navigator.of(context).pop(false),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _InlineButton(
                    label: confirmLabel,
                    onTap: () => Navigator.of(context).pop(true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _orderPeriodLabel(String key, bool isChinese) {
  final period = WebPlanPeriod.all.firstWhere(
    (item) => item.key == key,
    orElse: () => WebPlanPeriod(
      key: key,
      amountField: key,
      zhLabel: key,
      enLabel: key,
      amountCents: 0,
    ),
  );
  return period.label(isChinese);
}

String _orderStatusLabel(int state, bool isChinese) {
  switch (state) {
    case 1:
    case 3:
      return isChinese ? '已完成' : 'Completed';
    case 2:
      return isChinese ? '已取消' : 'Canceled';
    case 4:
      return isChinese ? '已关闭' : 'Closed';
    default:
      return isChinese ? '待支付' : 'Pending';
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return GradientCard(
      borderRadius: 28,
      padding: const EdgeInsets.all(28),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textSecondary, size: 34),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 6),
                Text(message, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: math.max(360, MediaQuery.of(context).size.height * 0.5),
      child: const Center(child: CapybaraLoader()),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: GradientCard(
          borderRadius: 34,
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: AppColors.textSecondary,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.displayMedium,
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              _InlineButton(
                label: '重新加载',
                icon: Icons.refresh_rounded,
                onTap: onRetry,
                lowEmphasis: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRowData {
  const _InfoRowData(this.label, this.value);

  final String label;
  final String value;
}
