import 'dart:async';

import 'package:flutter/material.dart';

import '../models/web_account_view_data.dart';
import '../models/web_purchase_view_data.dart';
import '../models/web_user_center_view_data.dart';
import '../models/web_user_subpage.dart';
import '../services/api_config.dart';
import '../services/app_api.dart';
import '../services/web_app_facade.dart';
import '../theme/app_colors.dart';
import '../utils/formatters.dart';
import '../utils/web_error_text.dart';
import '../widgets/animated_card.dart';
import '../widgets/gradient_card.dart';
import '../widgets/web_page_frame.dart';
import '../widgets/web_page_hero.dart';

typedef WebAccountProfileLoader = Future<Map<String, dynamic>> Function();
typedef WebAccountNotificationUpdater = Future<void> Function({
  required bool expiry,
  required bool traffic,
});
typedef WebAccountPasswordChanger = Future<void> Function({
  required String oldPassword,
  required String newPassword,
});
typedef WebAccountSubscriptionResetter = Future<void> Function();
typedef WebUserOrdersLoader = Future<List<WebOrderListItemData>> Function();
typedef WebUserOrderCanceler = Future<void> Function(String orderRef);
typedef WebUserNodeStatusesLoader = Future<List<WebNodeStatusItemData>>
    Function();
typedef WebUserTicketsLoader = Future<List<WebTicketListItemData>> Function();
typedef WebUserTicketDetailLoader = Future<WebTicketDetailData> Function(
  int ticketId,
);
typedef WebUserTicketCreator = Future<void> Function({
  required String subject,
  required int priorityLevel,
  required String message,
});
typedef WebUserTicketReplier = Future<void> Function({
  required int ticketId,
  required String message,
});
typedef WebUserTicketCloser = Future<void> Function(int ticketId);
typedef WebUserTrafficLogsLoader = Future<List<WebTrafficLogItemData>>
    Function();
typedef WebOpenOrderCheckout = Future<void> Function(
  String orderRef,
  WebPlanViewData? fallbackPlan,
);

class WebAccountPage extends StatefulWidget {
  const WebAccountPage({
    super.key,
    this.initialSubpage = WebUserSubpage.profile,
    this.profileLoader,
    this.notificationUpdater,
    this.passwordChanger,
    this.subscriptionResetter,
    this.ordersLoader,
    this.orderCanceler,
    this.nodeStatusesLoader,
    this.ticketsLoader,
    this.ticketDetailLoader,
    this.ticketCreator,
    this.ticketReplier,
    this.ticketCloser,
    this.trafficLogsLoader,
    this.onOpenOrderCheckout,
    this.onUnauthorized,
  });

  final WebUserSubpage initialSubpage;
  final WebAccountProfileLoader? profileLoader;
  final WebAccountNotificationUpdater? notificationUpdater;
  final WebAccountPasswordChanger? passwordChanger;
  final WebAccountSubscriptionResetter? subscriptionResetter;
  final WebUserOrdersLoader? ordersLoader;
  final WebUserOrderCanceler? orderCanceler;
  final WebUserNodeStatusesLoader? nodeStatusesLoader;
  final WebUserTicketsLoader? ticketsLoader;
  final WebUserTicketDetailLoader? ticketDetailLoader;
  final WebUserTicketCreator? ticketCreator;
  final WebUserTicketReplier? ticketReplier;
  final WebUserTicketCloser? ticketCloser;
  final WebUserTrafficLogsLoader? trafficLogsLoader;
  final WebOpenOrderCheckout? onOpenOrderCheckout;
  final VoidCallback? onUnauthorized;

  @override
  State<WebAccountPage> createState() => _WebAccountPageState();
}

class _WebAccountPageState extends State<WebAccountPage> {
  final _facade = WebAppFacade();
  late Future<WebAccountProfileData> _profileFuture;
  Future<List<WebOrderListItemData>>? _ordersFuture;
  Future<List<WebNodeStatusItemData>>? _nodesFuture;
  Future<List<WebTicketListItemData>>? _ticketsFuture;
  Future<List<WebTrafficLogItemData>>? _trafficLogsFuture;

  late WebUserSubpage _currentSubpage;
  bool? _expireReminder;
  bool? _trafficReminder;
  bool _isSavingNotifications = false;
  bool _isChangingPassword = false;
  bool _isResettingSubscription = false;
  bool _isCreatingTicket = false;
  String? _busyOrderRef;
  int? _busyTicketId;

  @override
  void initState() {
    super.initState();
    _currentSubpage = widget.initialSubpage;
    _profileFuture = _loadProfile();
    _primeSubpageFuture(_currentSubpage);
  }

  @override
  void didUpdateWidget(covariant WebAccountPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSubpage != widget.initialSubpage) {
      _switchSubpage(widget.initialSubpage, fromWidget: true);
    }
  }

  bool _isChinese(BuildContext context) =>
      Localizations.localeOf(context).languageCode.toLowerCase().startsWith(
            'zh',
          );

  Future<WebAccountProfileData> _loadProfile() async {
    final loader = widget.profileLoader;
    final profile = loader == null
        ? await _facade.loadAccountProfile()
        : WebAccountProfileData.fromResponse(await loader());
    _expireReminder ??= profile.expireReminder;
    _trafficReminder ??= profile.trafficReminder;
    return profile;
  }

  Future<List<WebOrderListItemData>> _loadOrders() {
    final loader = widget.ordersLoader ?? _facade.loadOrders;
    return loader();
  }

  Future<List<WebNodeStatusItemData>> _loadNodeStatuses() {
    final loader = widget.nodeStatusesLoader ?? _facade.loadNodeStatuses;
    return loader();
  }

  Future<List<WebTicketListItemData>> _loadTickets() {
    final loader = widget.ticketsLoader ?? _facade.loadTickets;
    return loader();
  }

  Future<WebTicketDetailData> _loadTicketDetail(int ticketId) {
    final loader = widget.ticketDetailLoader ?? _facade.loadTicketDetail;
    return loader(ticketId);
  }

  Future<void> _createTicket({
    required String subject,
    required int priorityLevel,
    required String message,
  }) {
    final creator = widget.ticketCreator ?? _facade.createTicket;
    return creator(
      subject: subject,
      priorityLevel: priorityLevel,
      message: message,
    );
  }

  Future<void> _replyTicket({
    required int ticketId,
    required String message,
  }) {
    final replier = widget.ticketReplier ?? _facade.replyTicket;
    return replier(ticketId: ticketId, message: message);
  }

  Future<void> _closeTicket(int ticketId) {
    final closer = widget.ticketCloser ?? _facade.closeTicket;
    return closer(ticketId);
  }

  Future<List<WebTrafficLogItemData>> _loadTrafficLogs() {
    final loader = widget.trafficLogsLoader ?? _facade.loadTrafficLogs;
    return loader();
  }

  void _primeSubpageFuture(WebUserSubpage subpage) {
    switch (subpage) {
      case WebUserSubpage.profile:
        break;
      case WebUserSubpage.orders:
        _ordersFuture ??= _loadOrders();
        break;
      case WebUserSubpage.nodes:
        _nodesFuture ??= _loadNodeStatuses();
        break;
      case WebUserSubpage.tickets:
        _ticketsFuture ??= _loadTickets();
        break;
      case WebUserSubpage.traffic:
        _trafficLogsFuture ??= _loadTrafficLogs();
        break;
    }
  }

  void _switchSubpage(WebUserSubpage subpage, {bool fromWidget = false}) {
    _primeSubpageFuture(subpage);
    if (_currentSubpage == subpage && !fromWidget) return;
    setState(() => _currentSubpage = subpage);
  }

  void _reloadOrders() {
    setState(() {
      _ordersFuture = _loadOrders();
    });
  }

  void _reloadNodes() {
    setState(() {
      _nodesFuture = _loadNodeStatuses();
    });
  }

  void _reloadTickets() {
    setState(() {
      _ticketsFuture = _loadTickets();
    });
  }

  void _reloadTrafficLogs() {
    setState(() {
      _trafficLogsFuture = _loadTrafficLogs();
    });
  }

  Future<void> _updateNotifications({
    required bool expiry,
    required bool traffic,
    required bool isChinese,
  }) async {
    if (_isSavingNotifications) return;
    final previousExpiry = _expireReminder ?? false;
    final previousTraffic = _trafficReminder ?? false;
    setState(() {
      _expireReminder = expiry;
      _trafficReminder = traffic;
      _isSavingNotifications = true;
    });
    try {
      final updater = widget.notificationUpdater ??
          ({required bool expiry, required bool traffic}) async {
            await _facade.updateNotifications(
              expiry: expiry,
              traffic: traffic,
            );
          };
      await updater(expiry: expiry, traffic: traffic);
      if (!mounted) return;
      _showSnack(isChinese ? '邮件提醒设置已保存。' : 'Notification settings saved.');
    } catch (error) {
      if (mounted) {
        setState(() {
          _expireReminder = previousExpiry;
          _trafficReminder = previousTraffic;
        });
      }
      _handleActionError(error, isChinese);
    } finally {
      if (mounted) setState(() => _isSavingNotifications = false);
    }
  }

  Future<void> _changePassword(bool isChinese) async {
    final result = await showDialog<_PasswordChangeRequest>(
      context: context,
      builder: (context) => _ChangePasswordDialog(isChinese: isChinese),
    );
    if (result == null || !mounted || _isChangingPassword) return;
    setState(() => _isChangingPassword = true);
    try {
      final changer = widget.passwordChanger ??
          ({required String oldPassword, required String newPassword}) async {
            await _facade.changePassword(
              oldPassword: oldPassword,
              newPassword: newPassword,
            );
          };
      await changer(
        oldPassword: result.oldPassword,
        newPassword: result.newPassword,
      );
      if (!mounted) return;
      _showSnack(isChinese ? '密码已修改。' : 'Password changed.');
    } catch (error) {
      _handleActionError(error, isChinese);
    } finally {
      if (mounted) setState(() => _isChangingPassword = false);
    }
  }

  Future<void> _resetSubscription(bool isChinese) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _AccountConfirmDialog(
        title: isChinese ? '重置订阅链接' : 'Reset Subscription Link',
        message: isChinese
            ? '确认重置订阅链接？旧链接会立即失效，需要重新复制或扫码导入。'
            : 'Reset the subscription link? The old link will stop working.',
        cancelLabel: isChinese ? '取消' : 'Cancel',
        confirmLabel: isChinese ? '确认重置' : 'Reset',
      ),
    );
    if (confirmed != true || !mounted || _isResettingSubscription) return;
    setState(() => _isResettingSubscription = true);
    try {
      final resetter = widget.subscriptionResetter ??
          () async {
            await _facade.resetSubscriptionSecurity();
          };
      await resetter();
      if (!mounted) return;
      _showSnack(
        isChinese ? '订阅链接已重置，请重新复制新的订阅入口。' : 'Subscription link reset.',
      );
    } catch (error) {
      _handleActionError(error, isChinese);
    } finally {
      if (mounted) {
        setState(() => _isResettingSubscription = false);
      }
    }
  }

  Future<void> _continueOrder(WebOrderListItemData order) async {
    if (_busyOrderRef != null) return;
    final isChinese = _isChinese(context);
    setState(() => _busyOrderRef = order.orderRef);
    try {
      final openOrderCheckout = widget.onOpenOrderCheckout;
      if (openOrderCheckout == null) {
        throw StateError('checkout navigation missing');
      }
      await openOrderCheckout(order.orderRef, order.plan);
    } catch (error) {
      _handleActionError(error, isChinese);
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
          builder: (context) => _AccountConfirmDialog(
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

    setState(() => _busyOrderRef = order.orderRef);
    try {
      final canceler = widget.orderCanceler ?? _facade.cancelOrder;
      await canceler(order.orderRef);
      if (!mounted) return;
      _reloadOrders();
      _showSnack(isChinese ? '订单已取消。' : 'Order canceled.');
    } catch (error) {
      _handleActionError(error, isChinese);
    } finally {
      if (mounted) {
        setState(() => _busyOrderRef = null);
      }
    }
  }

  Future<void> _openCreateTicketDialog() async {
    final isChinese = _isChinese(context);
    final request = await showDialog<_TicketComposeRequest>(
      context: context,
      builder: (context) => _TicketComposeDialog(isChinese: isChinese),
    );
    if (request == null || !mounted || _isCreatingTicket) return;

    setState(() => _isCreatingTicket = true);
    try {
      await _createTicket(
        subject: request.subject,
        priorityLevel: request.priorityLevel,
        message: request.message,
      );
      if (!mounted) return;
      _reloadTickets();
      _showSnack(isChinese ? '工单已提交。' : 'Ticket submitted.');
    } catch (error) {
      _handleActionError(error, isChinese);
    } finally {
      if (mounted) {
        setState(() => _isCreatingTicket = false);
      }
    }
  }

  Future<void> _openTicketDetail(WebTicketListItemData ticket) async {
    final isChinese = _isChinese(context);
    await showDialog<void>(
      context: context,
      builder: (context) => _TicketDetailDialog(
        isChinese: isChinese,
        ticketId: ticket.ticketId,
        detailLoader: _loadTicketDetail,
        replyAction: ({required ticketId, required message}) {
          return _replyTicket(ticketId: ticketId, message: message);
        },
        closeAction: _closeTicket,
        onChanged: _reloadTickets,
        onUnauthorized: _handleUnauthorized,
      ),
    );
  }

  void _handleActionError(Object error, bool isChinese) {
    if (error is AppApiException &&
        (error.statusCode == 401 || error.statusCode == 403)) {
      _handleUnauthorized();
      return;
    }
    if (!mounted) return;
    _showSnack(
      webErrorText(
        error,
        isChinese: isChinese,
        context: WebErrorContext.general,
      ),
    );
  }

  void _handlePaneError(Object? error) {
    if (error is AppApiException &&
        (error.statusCode == 401 || error.statusCode == 403)) {
      _handleUnauthorized();
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _handleUnauthorized() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ApiConfig().clearAuth();
      if (mounted) widget.onUnauthorized?.call();
    });
  }

  String _subpageSubtitle(bool isChinese) {
    switch (_currentSubpage) {
      case WebUserSubpage.profile:
        return isChinese
            ? '查看账户余额、邮件提醒和订阅相关设置。'
            : 'Manage balance, reminders, and subscription settings.';
      case WebUserSubpage.orders:
        return isChinese
            ? '查看历史订单，继续处理待支付订单。'
            : 'Review order history and continue pending payments.';
      case WebUserSubpage.nodes:
        return isChinese
            ? '查看当前可用节点与在线状态。'
            : 'Review currently available nodes and online status.';
      case WebUserSubpage.tickets:
        return isChinese
            ? '提交问题、查看回复并继续跟进工单。'
            : 'Create tickets and follow support replies.';
      case WebUserSubpage.traffic:
        return isChinese
            ? '查看近一个月的流量使用明细。'
            : 'Review traffic usage records from the last month.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isChinese = _isChinese(context);

    return WebPageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WebPageHero(
            title: isChinese ? '用户中心' : 'User Center',
            subtitle: _subpageSubtitle(isChinese),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: WebUserSubpage.values
                  .map(
                    (subpage) => _UserSubpagePill(
                      key: Key('web-user-subpage-${subpage.name}'),
                      label: subpage.label(isChinese),
                      selected: _currentSubpage == subpage,
                      onTap: () => _switchSubpage(subpage),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 18),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: KeyedSubtree(
              key: ValueKey<WebUserSubpage>(_currentSubpage),
              child: _buildSubpageContent(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubpageContent(BuildContext context) {
    switch (_currentSubpage) {
      case WebUserSubpage.profile:
        return _buildProfilePane(context);
      case WebUserSubpage.orders:
        return _buildOrdersPane(context);
      case WebUserSubpage.nodes:
        return _buildNodesPane(context);
      case WebUserSubpage.tickets:
        return _buildTicketsPane(context);
      case WebUserSubpage.traffic:
        return _buildTrafficPane(context);
    }
  }

  Widget _buildProfilePane(BuildContext context) {
    final isChinese = _isChinese(context);
    final wide = MediaQuery.of(context).size.width >= 1080;

    return FutureBuilder<WebAccountProfileData>(
      future: _profileFuture,
      builder: (context, snapshot) {
        _handlePaneError(snapshot.error);
        final balance = _balanceLabel(snapshot, isChinese);
        final profile = snapshot.data;
        final expireReminder =
            _expireReminder ?? profile?.expireReminder ?? false;
        final trafficReminder =
            _trafficReminder ?? profile?.trafficReminder ?? false;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (wide)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _BalanceCard(
                        title: isChinese ? '账户余额（仅消费）' : 'Account Balance',
                        value: balance,
                        fillHeight: true,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _PreferenceCard(
                        isChinese: isChinese,
                        expireReminder: expireReminder,
                        trafficReminder: trafficReminder,
                        isSaving: _isSavingNotifications,
                        onExpireChanged: (value) => _updateNotifications(
                          expiry: value,
                          traffic: trafficReminder,
                          isChinese: isChinese,
                        ),
                        onTrafficChanged: (value) => _updateNotifications(
                          expiry: expireReminder,
                          traffic: value,
                          isChinese: isChinese,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              _BalanceCard(
                title: isChinese ? '账户余额（仅消费）' : 'Account Balance',
                value: balance,
              ),
              const SizedBox(height: 16),
              _PreferenceCard(
                isChinese: isChinese,
                expireReminder: expireReminder,
                trafficReminder: trafficReminder,
                isSaving: _isSavingNotifications,
                onExpireChanged: (value) => _updateNotifications(
                  expiry: value,
                  traffic: trafficReminder,
                  isChinese: isChinese,
                ),
                onTrafficChanged: (value) => _updateNotifications(
                  expiry: expireReminder,
                  traffic: value,
                  isChinese: isChinese,
                ),
              ),
            ],
            const SizedBox(height: 18),
            _RiskActionCard(
              title: isChinese ? '修改你的密码' : 'Change Password',
              description: isChinese
                  ? '如果你怀疑账户安全有风险，可以在这里及时修改密码。'
                  : 'Change your password here if you suspect account exposure.',
              buttonLabel: isChinese ? '立即修改' : 'Change Now',
              isLoading: _isChangingPassword,
              onPressed: () => _changePassword(isChinese),
            ),
            const SizedBox(height: 16),
            _RiskActionCard(
              title: isChinese ? '重置订阅链接' : 'Reset Subscription Link',
              description: isChinese
                  ? '如果订阅链接可能被他人获取，可以在这里重置并重新复制新的导入链接。'
                  : 'Reset the subscription link if it may have been leaked.',
              buttonLabel: isChinese ? '立即重置' : 'Reset Now',
              isLoading: _isResettingSubscription,
              onPressed: () => _resetSubscription(isChinese),
            ),
          ],
        );
      },
    );
  }

  String _balanceLabel(
    AsyncSnapshot<WebAccountProfileData> snapshot,
    bool isChinese,
  ) {
    if (snapshot.connectionState != ConnectionState.done && !snapshot.hasData) {
      return '...';
    }
    if (snapshot.hasError) {
      return isChinese ? '加载失败' : 'Load failed';
    }
    return '¥${Formatters.formatCurrency(snapshot.data?.balanceAmount ?? 0)}';
  }

  Widget _buildOrdersPane(BuildContext context) {
    final isChinese = _isChinese(context);
    final ordersFuture = _ordersFuture ??= _loadOrders();

    return FutureBuilder<List<WebOrderListItemData>>(
      future: ordersFuture,
      builder: (context, snapshot) {
        _handlePaneError(snapshot.error);
        if (snapshot.hasError) {
          return _UserErrorPanel(
            title: isChinese ? '订单加载失败' : 'Orders failed to load',
            message: webErrorText(
              snapshot.error!,
              isChinese: isChinese,
              context: WebErrorContext.pageLoad,
            ),
            onRetry: _reloadOrders,
          );
        }
        if (!snapshot.hasData) {
          return const _UserLoadingPanel();
        }

        final orders = snapshot.data ?? const <WebOrderListItemData>[];
        if (orders.isEmpty) {
          return _UserEmptyPanel(
            icon: Icons.receipt_long_outlined,
            title: isChinese ? '还没有订单记录' : 'No orders yet',
            message: isChinese
                ? '你的订单会显示在这里，待支付订单也可以在这里继续处理。'
                : 'Your orders will appear here.',
            actionLabel: isChinese ? '刷新列表' : 'Refresh',
            onAction: _reloadOrders,
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: _InlineActionCardButton(
                label: isChinese ? '刷新订单' : 'Refresh',
                onTap: _reloadOrders,
              ),
            ),
            const SizedBox(height: 12),
            ...orders.map(
              (order) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _OrderCard(
                  order: order,
                  isChinese: isChinese,
                  isBusy: _busyOrderRef == order.orderRef,
                  onContinue: order.isPending
                      ? () => _continueOrder(order)
                      : null,
                  onCancel: order.isPending ? () => _cancelOrder(order) : null,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildNodesPane(BuildContext context) {
    final isChinese = _isChinese(context);
    final nodesFuture = _nodesFuture ??= _loadNodeStatuses();

    return FutureBuilder<List<WebNodeStatusItemData>>(
      future: nodesFuture,
      builder: (context, snapshot) {
        _handlePaneError(snapshot.error);
        if (snapshot.hasError) {
          return _UserErrorPanel(
            title: isChinese ? '节点状态加载失败' : 'Nodes failed to load',
            message: webErrorText(
              snapshot.error!,
              isChinese: isChinese,
              context: WebErrorContext.pageLoad,
            ),
            onRetry: _reloadNodes,
          );
        }
        if (!snapshot.hasData) {
          return const _UserLoadingPanel();
        }

        final items = snapshot.data ?? const <WebNodeStatusItemData>[];
        if (items.isEmpty) {
          return _UserEmptyPanel(
            icon: Icons.hub_outlined,
            title: isChinese ? '暂时没有可用节点' : 'No nodes available',
            message: isChinese
                ? '如果你已经开通套餐但这里仍为空，可以稍后刷新或联系在线客服协助确认。'
                : 'Refresh later or contact support if your plan is already active.',
            actionLabel: isChinese ? '刷新状态' : 'Refresh',
            onAction: _reloadNodes,
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: _InlineActionCardButton(
                label: isChinese ? '刷新状态' : 'Refresh',
                onTap: _reloadNodes,
              ),
            ),
            const SizedBox(height: 12),
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _NodeStatusCard(
                  item: item,
                  isChinese: isChinese,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTicketsPane(BuildContext context) {
    final isChinese = _isChinese(context);
    final ticketsFuture = _ticketsFuture ??= _loadTickets();

    return FutureBuilder<List<WebTicketListItemData>>(
      future: ticketsFuture,
      builder: (context, snapshot) {
        _handlePaneError(snapshot.error);
        if (snapshot.hasError) {
          return _UserErrorPanel(
            title: isChinese ? '工单加载失败' : 'Tickets failed to load',
            message: webErrorText(
              snapshot.error!,
              isChinese: isChinese,
              context: WebErrorContext.pageLoad,
            ),
            onRetry: _reloadTickets,
          );
        }
        if (!snapshot.hasData) {
          return const _UserLoadingPanel();
        }

        final tickets = snapshot.data ?? const <WebTicketListItemData>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    isChinese ? '工单记录' : 'Support Tickets',
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                          fontSize: 28,
                        ),
                  ),
                ),
                const SizedBox(width: 12),
                _InlineActionCardButton(
                  label: isChinese ? '新建工单' : 'New Ticket',
                  onTap: _isCreatingTicket ? null : _openCreateTicketDialog,
                  isLoading: _isCreatingTicket,
                  emphasized: true,
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (tickets.isEmpty)
              _UserEmptyPanel(
                icon: Icons.support_agent_outlined,
                title: isChinese ? '还没有工单记录' : 'No tickets yet',
                message: isChinese
                    ? '如果你需要协助，可以随时创建一张新工单。'
                    : 'Create a ticket whenever you need support.',
              )
            else
              ...tickets.map(
                (ticket) => Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _TicketCard(
                    ticket: ticket,
                    isChinese: isChinese,
                    isBusy: _busyTicketId == ticket.ticketId,
                    onTap: () => _openTicketDetail(ticket),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildTrafficPane(BuildContext context) {
    final isChinese = _isChinese(context);
    final trafficLogsFuture = _trafficLogsFuture ??= _loadTrafficLogs();

    return FutureBuilder<List<WebTrafficLogItemData>>(
      future: trafficLogsFuture,
      builder: (context, snapshot) {
        _handlePaneError(snapshot.error);
        if (snapshot.hasError) {
          return _UserErrorPanel(
            title: isChinese ? '流量明细加载失败' : 'Traffic logs failed to load',
            message: webErrorText(
              snapshot.error!,
              isChinese: isChinese,
              context: WebErrorContext.pageLoad,
            ),
            onRetry: _reloadTrafficLogs,
          );
        }
        if (!snapshot.hasData) {
          return const _UserLoadingPanel();
        }

        final items = snapshot.data ?? const <WebTrafficLogItemData>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GradientCard(
              borderRadius: 26,
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const Icon(
                    Icons.insights_outlined,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isChinese
                          ? '这里展示近一个月的流量扣费记录，便于你查看近期使用情况。'
                          : 'This page shows traffic records from the last month.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                            height: 1.5,
                          ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (items.isEmpty)
              _UserEmptyPanel(
                icon: Icons.data_usage_outlined,
                title: isChinese ? '近一个月没有流量记录' : 'No traffic logs yet',
                message: isChinese
                    ? '当前还没有可展示的流量明细。'
                    : 'There are no traffic records to show yet.',
              )
            else
              ...items.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _TrafficLogCard(
                    item: item,
                    isChinese: isChinese,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _UserSubpagePill extends StatelessWidget {
  const _UserSubpagePill({
    super.key,
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
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accent.withValues(alpha: 0.16)
              : AppColors.surfaceAlt.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppColors.accent.withValues(alpha: 0.9)
                : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color:
                selected ? AppColors.textPrimary : AppColors.textSecondary,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _UserLoadingPanel extends StatelessWidget {
  const _UserLoadingPanel();

  @override
  Widget build(BuildContext context) {
    return const GradientCard(
      borderRadius: 30,
      padding: EdgeInsets.all(28),
      child: Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _UserEmptyPanel extends StatelessWidget {
  const _UserEmptyPanel({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return GradientCard(
      borderRadius: 30,
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.textSecondary, size: 28),
          const SizedBox(height: 14),
          Text(
            title,
            style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  fontSize: 28,
                ),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.6,
                ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 18),
            _InlineActionCardButton(
              label: actionLabel!,
              onTap: onAction,
            ),
          ],
        ],
      ),
    );
  }
}

class _UserErrorPanel extends StatelessWidget {
  const _UserErrorPanel({
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _UserEmptyPanel(
      icon: Icons.error_outline_rounded,
      title: title,
      message: message,
      actionLabel: Localizations.localeOf(context)
              .languageCode
              .toLowerCase()
              .startsWith('zh')
          ? '重新加载'
          : 'Retry',
      onAction: onRetry,
    );
  }
}

class _InlineActionCardButton extends StatelessWidget {
  const _InlineActionCardButton({
    required this.label,
    required this.onTap,
    this.isLoading = false,
    this.emphasized = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool isLoading;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: AnimatedCard(
        onTap: onTap,
        enableBreathing: false,
        hoverScale: 1.01,
        borderRadius: 18,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        gradientColors: emphasized
            ? null
            : [
                AppColors.surface.withValues(alpha: 0.7),
                AppColors.surfaceAlt.withValues(alpha: 0.6),
              ],
        baseBorderColor:
            emphasized ? null : AppColors.border.withValues(alpha: 0.9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading) ...[
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
            ],
            Text(
              label,
              style: TextStyle(
                color:
                    emphasized ? AppColors.textPrimary : AppColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
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
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  order.plan?.title ??
                      (isChinese ? '未命名套餐' : 'Untitled plan'),
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(
                        fontSize: 28,
                      ),
                ),
              ),
              _StatusBadge(
                label: _orderStatusLabel(order.stateCode, isChinese),
                color: order.isPending ? AppColors.warning : AppColors.accent,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 18,
            runSpacing: 10,
            children: [
              _MetaText(
                label: isChinese ? '订单号' : 'Order',
                value: order.orderRef,
              ),
              _MetaText(
                label: isChinese ? '周期' : 'Period',
                value: _periodLabel(order.periodKey, isChinese),
              ),
              _MetaText(
                label: isChinese ? '金额' : 'Amount',
                value: '¥${Formatters.formatCurrency(order.amountTotal)}',
              ),
              _MetaText(
                label: isChinese ? '创建时间' : 'Created',
                value: Formatters.formatEpoch(order.createdAt),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              if (order.isPending && onContinue != null)
                _InlineActionCardButton(
                  label: isChinese ? '继续支付' : 'Continue',
                  onTap: isBusy ? null : onContinue,
                  isLoading: isBusy,
                  emphasized: true,
                ),
              if (order.isPending && onCancel != null) ...[
                const SizedBox(width: 12),
                _InlineActionCardButton(
                  label: isChinese ? '取消订单' : 'Cancel',
                  onTap: isBusy ? null : onCancel,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _NodeStatusCard extends StatelessWidget {
  const _NodeStatusCard({
    required this.item,
    required this.isChinese,
  });

  final WebNodeStatusItemData item;
  final bool isChinese;

  @override
  Widget build(BuildContext context) {
    final lastCheck = item.lastCheckAt > 0
        ? Formatters.formatEpoch(item.lastCheckAt)
        : (isChinese ? '等待检查' : 'Waiting');

    return GradientCard(
      borderRadius: 28,
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.displayName.isEmpty
                      ? (isChinese ? '未命名节点' : 'Unnamed node')
                      : item.displayName,
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(
                        fontSize: 28,
                      ),
                ),
              ),
              _StatusBadge(
                label: item.isOnline
                    ? (isChinese ? '在线' : 'Online')
                    : (isChinese ? '离线' : 'Offline'),
                color: item.isOnline ? AppColors.success : AppColors.accentWarm,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 18,
            runSpacing: 10,
            children: [
              _MetaText(
                label: isChinese ? '协议' : 'Protocol',
                value: item.protocolType.isEmpty
                    ? '--'
                    : item.protocolType.toUpperCase(),
              ),
              _MetaText(
                label: isChinese ? '版本' : 'Version',
                value: item.version.isEmpty ? '--' : item.version,
              ),
              _MetaText(
                label: isChinese ? '倍率' : 'Rate',
                value: item.rate <= 0 ? '1x' : '${item.rate}x',
              ),
              _MetaText(
                label: isChinese ? '最近检查' : 'Last check',
                value: lastCheck,
              ),
            ],
          ),
          if (item.tags.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: item.tags
                  .map(
                    (tag) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceAlt.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        tag,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({
    required this.ticket,
    required this.isChinese,
    required this.isBusy,
    required this.onTap,
  });

  final WebTicketListItemData ticket;
  final bool isChinese;
  final bool isBusy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedCard(
      onTap: onTap,
      enableBreathing: false,
      hoverScale: 1.008,
      borderRadius: 28,
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  ticket.subject.isEmpty
                      ? (isChinese ? '未命名工单' : 'Untitled ticket')
                      : ticket.subject,
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(
                        fontSize: 28,
                      ),
                ),
              ),
              if (isBusy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              const SizedBox(width: 10),
              _StatusBadge(
                label: _ticketStateLabel(ticket.stateCode, isChinese),
                color:
                    ticket.isClosed ? AppColors.accentWarm : AppColors.success,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 18,
            runSpacing: 10,
            children: [
              _MetaText(
                label: isChinese ? '优先级' : 'Priority',
                value: _ticketPriorityLabel(ticket.priorityLevel, isChinese),
              ),
              _MetaText(
                label: isChinese ? '回复状态' : 'Reply status',
                value: _ticketReplyStatusLabel(ticket.replyState, isChinese),
              ),
              _MetaText(
                label: isChinese ? '最后更新' : 'Updated',
                value: Formatters.formatEpoch(ticket.updatedAt),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrafficLogCard extends StatelessWidget {
  const _TrafficLogCard({
    required this.item,
    required this.isChinese,
  });

  final WebTrafficLogItemData item;
  final bool isChinese;

  @override
  Widget build(BuildContext context) {
    return GradientCard(
      borderRadius: 28,
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            Formatters.formatEpoch(item.recordedAt),
            style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  fontSize: 26,
                ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 18,
            runSpacing: 10,
            children: [
              _MetaText(
                label: isChinese ? '上行' : 'Upload',
                value: Formatters.formatBytes(item.uploadedAmount),
              ),
              _MetaText(
                label: isChinese ? '下行' : 'Download',
                value: Formatters.formatBytes(item.downloadedAmount),
              ),
              _MetaText(
                label: isChinese ? '倍率' : 'Rate',
                value: '${item.rateMultiplier}x',
              ),
              _MetaText(
                label: isChinese ? '扣费流量' : 'Charged',
                value: Formatters.formatBytes(item.chargedAmount),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetaText extends StatelessWidget {
  const _MetaText({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$label: ',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          TextSpan(
            text: value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.title,
    required this.value,
    this.fillHeight = false,
  });

  final String title;
  final String value;
  final bool fillHeight;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('web-account-balance-card'),
      child: GradientCard(
        borderRadius: 30,
        padding: const EdgeInsets.all(28),
        child: fillHeight
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.max,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                          fontSize: 28,
                        ),
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: Center(
                      child: Text(
                        value,
                        style:
                            Theme.of(context).textTheme.displayMedium?.copyWith(
                                  fontSize: 84,
                                  height: 0.9,
                                ),
                      ),
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                          fontSize: 28,
                        ),
                  ),
                  const SizedBox(height: 54),
                  Center(
                    child: Text(
                      value,
                      style:
                          Theme.of(context).textTheme.displayMedium?.copyWith(
                                fontSize: 84,
                                height: 0.9,
                              ),
                    ),
                  ),
                  const SizedBox(height: 54),
                ],
              ),
      ),
    );
  }
}

class _PreferenceCard extends StatelessWidget {
  const _PreferenceCard({
    required this.isChinese,
    required this.expireReminder,
    required this.trafficReminder,
    required this.isSaving,
    required this.onExpireChanged,
    required this.onTrafficChanged,
  });

  final bool isChinese;
  final bool expireReminder;
  final bool trafficReminder;
  final bool isSaving;
  final ValueChanged<bool> onExpireChanged;
  final ValueChanged<bool> onTrafficChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('web-account-preference-card'),
      child: GradientCard(
        borderRadius: 30,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.max,
          children: [
            Text(
              isChinese ? '邮件通知' : 'Email Notifications',
              style: Theme.of(context).textTheme.displayMedium?.copyWith(
                    fontSize: 28,
                  ),
            ),
            const SizedBox(height: 20),
            _PreferenceTile(
              title: isChinese ? '到期邮件提醒' : 'Expiry Reminder',
              subtitle: isChinese
                  ? '我们会在套餐到期之前将邮件发送给您。'
                  : 'We will send an email reminder before the plan expires.',
              value: expireReminder,
              onChanged: isSaving ? null : onExpireChanged,
            ),
            const SizedBox(height: 14),
            _PreferenceTile(
              title: isChinese ? '流量邮件提醒' : 'Traffic Reminder',
              subtitle: isChinese
                  ? '我们会在流量用尽之前将邮件发送给您。'
                  : 'We will send an email reminder before traffic runs out.',
              value: trafficReminder,
              onChanged: isSaving ? null : onTrafficChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _PreferenceTile extends StatelessWidget {
  const _PreferenceTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: 18,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: 15,
                        height: 1.4,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.accent,
            activeTrackColor: AppColors.accent.withValues(alpha: 0.4),
          ),
        ],
      ),
    );
  }
}

class _RiskActionCard extends StatelessWidget {
  const _RiskActionCard({
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.isLoading,
    required this.onPressed,
  });

  final String title;
  final String description;
  final String buttonLabel;
  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GradientCard(
      borderRadius: 30,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(
                        fontSize: 28,
                      ),
                ),
              ),
              const SizedBox(width: 16),
              FilledButton(
                onPressed: isLoading ? null : onPressed,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.warning,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                ),
                child: isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(buttonLabel),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              description,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textPrimary,
                    height: 1.5,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PasswordChangeRequest {
  const _PasswordChangeRequest({
    required this.oldPassword,
    required this.newPassword,
  });

  final String oldPassword;
  final String newPassword;
}

class _TicketComposeRequest {
  const _TicketComposeRequest({
    required this.subject,
    required this.priorityLevel,
    required this.message,
  });

  final String subject;
  final int priorityLevel;
  final String message;
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog({required this.isChinese});

  final bool isChinese;

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _oldController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  String? _error;
  bool _obscure = true;

  @override
  void dispose() {
    _oldController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _submit() {
    final oldPassword = _oldController.text;
    final newPassword = _newController.text;
    final confirm = _confirmController.text;
    if (oldPassword.isEmpty || newPassword.length < 8) {
      setState(() {
        _error = widget.isChinese
            ? '旧密码不能为空，新密码至少 8 位。'
            : 'Old password is required and new password needs 8+ chars.';
      });
      return;
    }
    if (newPassword != confirm) {
      setState(() {
        _error = widget.isChinese ? '两次新密码不一致。' : 'Passwords do not match.';
      });
      return;
    }
    Navigator.of(context).pop(
      _PasswordChangeRequest(
        oldPassword: oldPassword,
        newPassword: newPassword,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      key: const Key('web-account-change-password-dialog'),
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: GradientCard(
          borderRadius: 34,
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.isChinese ? '修改密码' : 'Change Password',
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      fontSize: 32,
                    ),
              ),
              const SizedBox(height: 18),
              _DialogTextField(
                controller: _oldController,
                label: widget.isChinese ? '旧密码' : 'Old Password',
                obscureText: _obscure,
              ),
              const SizedBox(height: 12),
              _DialogTextField(
                controller: _newController,
                label: widget.isChinese ? '新密码' : 'New Password',
                obscureText: _obscure,
              ),
              const SizedBox(height: 12),
              _DialogTextField(
                controller: _confirmController,
                label: widget.isChinese ? '确认新密码' : 'Confirm Password',
                obscureText: _obscure,
                onSubmitted: (_) => _submit(),
                suffix: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.accentWarm,
                      ),
                ),
              ],
              const SizedBox(height: 22),
              _DialogButtonRow(
                cancelLabel: widget.isChinese ? '取消' : 'Cancel',
                confirmLabel: widget.isChinese ? '确认修改' : 'Change',
                onCancel: () => Navigator.of(context).pop(),
                onConfirm: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TicketComposeDialog extends StatefulWidget {
  const _TicketComposeDialog({
    required this.isChinese,
    this.title,
    this.subjectHint,
    this.confirmLabel,
  });

  final bool isChinese;
  final String? title;
  final String? subjectHint;
  final String? confirmLabel;

  @override
  State<_TicketComposeDialog> createState() => _TicketComposeDialogState();
}

class _TicketComposeDialogState extends State<_TicketComposeDialog> {
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();
  int _priorityLevel = 1;
  String? _error;

  @override
  void initState() {
    super.initState();
    _subjectController.text = widget.subjectHint ?? '';
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _submit() {
    final subject = _subjectController.text.trim();
    final message = _messageController.text.trim();
    if (subject.isEmpty || message.isEmpty) {
      setState(() {
        _error = widget.isChinese ? '请填写完整主题和内容。' : 'Fill in subject and message.';
      });
      return;
    }
    Navigator.of(context).pop(
      _TicketComposeRequest(
        subject: subject,
        priorityLevel: _priorityLevel,
        message: message,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      key: const Key('web-user-ticket-compose-dialog'),
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: GradientCard(
          borderRadius: 34,
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title ?? (widget.isChinese ? '新建工单' : 'New Ticket'),
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      fontSize: 32,
                    ),
              ),
              const SizedBox(height: 18),
              _DialogTextField(
                controller: _subjectController,
                label: widget.isChinese ? '工单主题' : 'Subject',
                obscureText: false,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _priorityLevel,
                dropdownColor: AppColors.surface,
                decoration: InputDecoration(
                  labelText: widget.isChinese ? '优先级' : 'Priority',
                  filled: true,
                  fillColor: AppColors.surfaceAlt.withValues(alpha: 0.7),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                ),
                items: [0, 1, 2]
                    .map(
                      (level) => DropdownMenuItem<int>(
                        value: level,
                        child: Text(
                          _ticketPriorityLabel(level, widget.isChinese),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _priorityLevel = value);
                },
              ),
              const SizedBox(height: 12),
              _DialogTextField(
                controller: _messageController,
                label: widget.isChinese ? '问题描述' : 'Message',
                obscureText: false,
                minLines: 5,
                maxLines: 8,
                onSubmitted: (_) {},
              ),
              const SizedBox(height: 10),
              Text(
                _ticketPriorityLabel(_priorityLevel, widget.isChinese),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.accentWarm,
                      ),
                ),
              ],
              const SizedBox(height: 22),
              _DialogButtonRow(
                cancelLabel: widget.isChinese ? '取消' : 'Cancel',
                confirmLabel:
                    widget.confirmLabel ?? (widget.isChinese ? '提交工单' : 'Submit'),
                onCancel: () => Navigator.of(context).pop(),
                onConfirm: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TicketDetailDialog extends StatefulWidget {
  const _TicketDetailDialog({
    required this.isChinese,
    required this.ticketId,
    required this.detailLoader,
    required this.replyAction,
    required this.closeAction,
    required this.onChanged,
    required this.onUnauthorized,
  });

  final bool isChinese;
  final int ticketId;
  final Future<WebTicketDetailData> Function(int ticketId) detailLoader;
  final Future<void> Function({
    required int ticketId,
    required String message,
  }) replyAction;
  final Future<void> Function(int ticketId) closeAction;
  final VoidCallback onChanged;
  final VoidCallback onUnauthorized;

  @override
  State<_TicketDetailDialog> createState() => _TicketDetailDialogState();
}

class _TicketDetailDialogState extends State<_TicketDetailDialog> {
  late Future<WebTicketDetailData> _detailFuture;
  bool _isReplying = false;
  bool _isClosing = false;

  @override
  void initState() {
    super.initState();
    _detailFuture = widget.detailLoader(widget.ticketId);
  }

  void _reload() {
    setState(() {
      _detailFuture = widget.detailLoader(widget.ticketId);
    });
  }

  void _handleError(Object error) {
    if (error is AppApiException &&
        (error.statusCode == 401 || error.statusCode == 403)) {
      widget.onUnauthorized();
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          webErrorText(
            error,
            isChinese: widget.isChinese,
            context: WebErrorContext.general,
          ),
        ),
      ),
    );
  }

  Future<void> _reply(WebTicketDetailData detail) async {
    if (_isReplying) return;
    final request = await showDialog<_TicketComposeRequest>(
      context: context,
      builder: (context) => _TicketComposeDialog(
        isChinese: widget.isChinese,
        title: widget.isChinese ? '回复工单' : 'Reply Ticket',
        subjectHint: detail.subject,
        confirmLabel: widget.isChinese ? '发送回复' : 'Send Reply',
      ),
    );
    if (request == null || !mounted) return;
    setState(() => _isReplying = true);
    try {
      await widget.replyAction(
        ticketId: detail.ticketId,
        message: request.message,
      );
      if (!mounted) return;
      widget.onChanged();
      _reload();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(widget.isChinese ? '回复已发送。' : 'Reply sent successfully.'),
        ),
      );
    } catch (error) {
      _handleError(error);
    } finally {
      if (mounted) {
        setState(() => _isReplying = false);
      }
    }
  }

  Future<void> _closeTicket(WebTicketDetailData detail) async {
    if (_isClosing || detail.isClosed) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => _AccountConfirmDialog(
            title: widget.isChinese ? '关闭这张工单？' : 'Close this ticket?',
            message: widget.isChinese
                ? '关闭后仍可查看历史内容，但新的处理会以当前状态为准。'
                : 'The ticket history will remain visible after closing.',
            cancelLabel: widget.isChinese ? '取消' : 'Cancel',
            confirmLabel: widget.isChinese ? '确认关闭' : 'Close Ticket',
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    setState(() => _isClosing = true);
    try {
      await widget.closeAction(detail.ticketId);
      if (!mounted) return;
      widget.onChanged();
      _reload();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.isChinese ? '工单已关闭。' : 'Ticket closed.'),
        ),
      );
    } catch (error) {
      _handleError(error);
    } finally {
      if (mounted) {
        setState(() => _isClosing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      key: const Key('web-user-ticket-detail-dialog'),
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780, maxHeight: 720),
        child: GradientCard(
          borderRadius: 34,
          padding: const EdgeInsets.all(28),
          child: SizedBox(
            height: 620,
            child: FutureBuilder<WebTicketDetailData>(
              future: _detailFuture,
              builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.isChinese ? '工单详情加载失败' : 'Ticket failed to load',
                      style:
                          Theme.of(context).textTheme.displayMedium?.copyWith(
                                fontSize: 30,
                              ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      webErrorText(
                        snapshot.error!,
                        isChinese: widget.isChinese,
                        context: WebErrorContext.pageLoad,
                      ),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                    const SizedBox(height: 24),
                    _DialogButtonRow(
                      cancelLabel: widget.isChinese ? '关闭' : 'Close',
                      confirmLabel: widget.isChinese ? '重新加载' : 'Retry',
                      onCancel: () => Navigator.of(context).pop(),
                      onConfirm: _reload,
                    ),
                  ],
                );
              }
              if (!snapshot.hasData) {
                return const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }

              final detail = snapshot.data!;
              final timeline = <WebTicketMessageData>[
                WebTicketMessageData(
                  messageId: 0,
                  ticketId: detail.ticketId,
                  isMine: true,
                  body: detail.body,
                  createdAt: detail.createdAt,
                  updatedAt: detail.updatedAt,
                ),
                ...detail.messages,
              ];

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          detail.subject,
                          style: Theme.of(context)
                              .textTheme
                              .displayMedium
                              ?.copyWith(fontSize: 30),
                        ),
                      ),
                      const SizedBox(width: 12),
                      _StatusBadge(
                        label: _ticketStateLabel(detail.stateCode, widget.isChinese),
                        color: detail.isClosed
                            ? AppColors.accentWarm
                            : AppColors.success,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 18,
                    runSpacing: 10,
                    children: [
                      _MetaText(
                        label: widget.isChinese ? '优先级' : 'Priority',
                        value: _ticketPriorityLabel(
                          detail.priorityLevel,
                          widget.isChinese,
                        ),
                      ),
                      _MetaText(
                        label: widget.isChinese ? '回复状态' : 'Reply status',
                        value: _ticketReplyStatusLabel(
                          detail.replyState,
                          widget.isChinese,
                        ),
                      ),
                      _MetaText(
                        label: widget.isChinese ? '创建时间' : 'Created',
                        value: Formatters.formatEpoch(detail.createdAt),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: timeline
                            .map(
                              (message) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _TicketMessageBubble(
                                  message: message,
                                  isChinese: widget.isChinese,
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: _DialogCardButton(
                          label: widget.isChinese ? '关闭窗口' : 'Close',
                          emphasized: false,
                          onTap: () => Navigator.of(context).pop(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _DialogCardButton(
                          label: widget.isChinese ? '回复工单' : 'Reply',
                          emphasized: false,
                          onTap: _isReplying ? () {} : () => _reply(detail),
                        ),
                      ),
                      if (!detail.isClosed) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: _DialogCardButton(
                            label: widget.isChinese ? '关闭工单' : 'Close Ticket',
                            emphasized: true,
                            onTap:
                                _isClosing ? () {} : () => _closeTicket(detail),
                          ),
                        ),
                      ],
                    ],
                  ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _TicketMessageBubble extends StatelessWidget {
  const _TicketMessageBubble({
    required this.message,
    required this.isChinese,
  });

  final WebTicketMessageData message;
  final bool isChinese;

  @override
  Widget build(BuildContext context) {
    final fromMe = message.isMine;
    return Align(
      alignment: fromMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: fromMe
              ? AppColors.accent.withValues(alpha: 0.12)
              : AppColors.surfaceAlt.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: fromMe
                ? AppColors.accent.withValues(alpha: 0.55)
                : AppColors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment:
              fromMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              fromMe
                  ? (isChinese ? '我' : 'You')
                  : (isChinese ? '客服回复' : 'Support'),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontSize: 15,
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              message.body,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.6,
                  ),
            ),
            const SizedBox(height: 10),
            Text(
              Formatters.formatEpoch(message.createdAt),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountConfirmDialog extends StatelessWidget {
  const _AccountConfirmDialog({
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
      key: const Key('web-account-confirm-dialog'),
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: GradientCard(
          borderRadius: 34,
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      fontSize: 32,
                    ),
              ),
              const SizedBox(height: 16),
              Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      height: 1.5,
                      color: AppColors.textSecondary,
                    ),
              ),
              const SizedBox(height: 24),
              _DialogButtonRow(
                cancelLabel: cancelLabel,
                confirmLabel: confirmLabel,
                onConfirm: () => Navigator.of(context).pop(true),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogButtonRow extends StatelessWidget {
  const _DialogButtonRow({
    required this.cancelLabel,
    required this.confirmLabel,
    required this.onConfirm,
    this.onCancel,
  });

  final String cancelLabel;
  final String confirmLabel;
  final VoidCallback onConfirm;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _DialogCardButton(
            label: cancelLabel,
            emphasized: false,
            onTap: onCancel ?? () => Navigator.of(context).pop(false),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _DialogCardButton(
            label: confirmLabel,
            emphasized: true,
            onTap: onConfirm,
          ),
        ),
      ],
    );
  }
}

class _DialogCardButton extends StatelessWidget {
  const _DialogCardButton({
    required this.label,
    required this.emphasized,
    required this.onTap,
  });

  final String label;
  final bool emphasized;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: AnimatedCard(
        onTap: onTap,
        enableBreathing: false,
        borderRadius: 18,
        hoverScale: 1.01,
        padding: EdgeInsets.zero,
        gradientColors: emphasized
            ? null
            : [
                AppColors.surface.withValues(alpha: 0.62),
                AppColors.surfaceAlt.withValues(alpha: 0.44),
              ],
        baseBorderColor:
            emphasized ? null : AppColors.border.withValues(alpha: 0.85),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color:
                  emphasized ? AppColors.textPrimary : AppColors.textSecondary,
              fontSize: 15,
              fontWeight: emphasized ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _DialogTextField extends StatelessWidget {
  const _DialogTextField({
    required this.controller,
    required this.label,
    required this.obscureText,
    this.suffix,
    this.minLines,
    this.maxLines = 1,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final bool obscureText;
  final Widget? suffix;
  final int? minLines;
  final int? maxLines;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      minLines: obscureText ? 1 : minLines,
      maxLines: obscureText ? 1 : maxLines,
      onSubmitted: onSubmitted,
      style: Theme.of(context).textTheme.titleMedium,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: suffix,
        filled: true,
        fillColor: AppColors.surfaceAlt.withValues(alpha: 0.7),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.border),
        ),
      ),
    );
  }
}

String _orderStatusLabel(int stateCode, bool isChinese) {
  switch (stateCode) {
    case 0:
      return isChinese ? '待支付' : 'Pending';
    case 1:
      return isChinese ? '已完成' : 'Completed';
    case 2:
      return isChinese ? '已取消' : 'Canceled';
    default:
      return isChinese ? '已关闭' : 'Closed';
  }
}

String _periodLabel(String periodKey, bool isChinese) {
  switch (periodKey) {
    case 'month_price':
      return isChinese ? '月付' : 'Monthly';
    case 'quarter_price':
      return isChinese ? '季付' : 'Quarterly';
    case 'half_year_price':
      return isChinese ? '半年付' : 'Half-year';
    case 'year_price':
      return isChinese ? '年付' : 'Yearly';
    case 'two_year_price':
      return isChinese ? '两年付' : 'Two years';
    case 'three_year_price':
      return isChinese ? '三年付' : 'Three years';
    case 'onetime_price':
      return isChinese ? '一次性' : 'One-time';
    case 'reset_price':
      return isChinese ? '重置流量' : 'Traffic reset';
    default:
      return periodKey;
  }
}

String _ticketPriorityLabel(int level, bool isChinese) {
  switch (level) {
    case 0:
      return isChinese ? '普通优先级' : 'Normal priority';
    case 1:
      return isChinese ? '较高优先级' : 'Higher priority';
    case 2:
      return isChinese ? '紧急优先级' : 'Urgent priority';
    default:
      return isChinese ? '未设置' : 'Unknown';
  }
}

String _ticketReplyStatusLabel(int replyState, bool isChinese) {
  switch (replyState) {
    case 0:
      return isChinese ? '等待回复' : 'Waiting';
    case 1:
      return isChinese ? '已有更新' : 'Updated';
    default:
      return isChinese ? '处理中' : 'In progress';
  }
}

String _ticketStateLabel(int stateCode, bool isChinese) {
  return stateCode == 0
      ? (isChinese ? '处理中' : 'Open')
      : (isChinese ? '已关闭' : 'Closed');
}
