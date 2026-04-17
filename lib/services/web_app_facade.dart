import '../models/help_article.dart';
import '../models/user_info.dart';
import '../models/web_account_view_data.dart';
import '../models/web_client_download.dart';
import '../models/web_home_view_data.dart';
import '../models/web_invite_view_data.dart';
import '../models/web_purchase_view_data.dart';
import '../models/web_user_center_view_data.dart';
import '../models/web_withdraw_config.dart';
import 'api_config.dart';
import 'app_api.dart';
import 'user_data_service.dart';

class PendingOrderExistsException implements Exception {
  const PendingOrderExistsException();
}

class WebAppFacade {
  WebAppFacade({
    AppApi? api,
    ApiConfig? config,
    UserDataService? userDataService,
  })  : _api = api ?? AppApi(config: config),
        _config = config ?? ApiConfig(),
        _userDataService = userDataService ?? UserDataService();

  final AppApi _api;
  final ApiConfig _config;
  final UserDataService _userDataService;

  Future<List<HelpCategory>> loadHelpCategories(String language) async {
    await _config.refreshSessionCache();
    final response = await _api.getHelpArticles(language: language);
    final data = Map<String, dynamic>.from(
      response['data'] as Map? ?? const {},
    );
    return (data['categories'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => HelpCategory.fromMap(Map<String, dynamic>.from(item)))
        .where((category) =>
            category.name.isNotEmpty && category.articles.isNotEmpty)
        .toList();
  }

  Future<HelpArticleDetail> loadHelpArticleDetail(
    int articleId,
    String language,
  ) async {
    await _config.refreshSessionCache();
    final response = await _api.getHelpArticle(
      articleId,
      language: language,
    );
    final data = Map<String, dynamic>.from(
      response['data'] as Map? ?? const {},
    );
    return HelpArticleDetail.fromMap(
      Map<String, dynamic>.from(data['article'] as Map? ?? const {}),
    );
  }

  Future<void> logoutCurrentSession() async {
    await _api.logout();
  }

  Future<WebHomeViewData> loadHomeData({bool forceRefresh = false}) async {
    await _config.refreshSessionCache();
    final results = await Future.wait([
      _userDataService.getAccountPageData(forceRefresh: forceRefresh),
      _userDataService.getPlans(forceRefresh: forceRefresh),
      _userDataService.getNotices(forceRefresh: forceRefresh),
    ]);
    final accountData = Map<String, dynamic>.from(
      results[0] as Map<String, dynamic>,
    );
    return WebHomeViewData.fromSources(
      user: accountData['user'] as UserInfo,
      subscription: Map<String, dynamic>.from(
        accountData['subscribe'] as Map? ?? const {},
      ),
      plans: results[1] as List<Map<String, dynamic>>,
      notices: results[2] as List<Map<String, dynamic>>,
    );
  }

  Future<String> createSubscriptionAccessLink({String? flag}) async {
    final response = await _api.createSubscriptionAccessLink(flag: flag);
    final data = Map<String, dynamic>.from(
      response['data'] as Map? ?? const {},
    );
    final subscription = Map<String, dynamic>.from(
      data['subscription'] as Map? ?? const {},
    );
    return subscription['access_url']?.toString() ?? '';
  }

  Future<List<WebClientDownloadItem>> loadClientDownloads() async {
    final response = await _api.getClientDownloads();
    final data = Map<String, dynamic>.from(
      response['data'] as Map? ?? const {},
    );
    return (data['items'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => WebClientDownloadItem.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .toList();
  }

  Future<WebAccountProfileData> loadAccountProfile() async {
    await _config.refreshSessionCache();
    return WebAccountProfileData.fromResponse(await _api.getProfile());
  }

  Future<WebAccountProfileData> updateNotifications({
    required bool expiry,
    required bool traffic,
  }) async {
    return WebAccountProfileData.fromResponse(
      await _api.updateNotifications(expiry: expiry, traffic: traffic),
    );
  }

  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    await _api.changePassword(
      oldPassword: oldPassword,
      newPassword: newPassword,
    );
  }

  Future<void> resetSubscriptionSecurity() async {
    await _api.resetSubscriptionSecurity();
  }

  Future<WebInviteViewData> loadInviteData() async {
    await _config.refreshSessionCache();
    final responses = await Future.wait<Map<String, dynamic>>([
      _api.getInviteOverview(),
      _api.getInviteRecords(),
    ]);
    return WebInviteViewData.fromResponses(responses[0], responses[1]);
  }

  Future<void> createInviteCode() async {
    await _api.createInviteCode();
  }

  Future<void> transferReferralBalance(int amountCents) async {
    await _api.transferReferralBalance(amountCents);
  }

  Future<WebWithdrawConfig> loadWithdrawConfig() async {
    return WebWithdrawConfig.fromResponse(await _api.getUserConfig());
  }

  Future<void> requestReferralWithdrawal({
    required String method,
    required String account,
  }) async {
    await _api.requestReferralWithdrawal(method: method, account: account);
  }

  Future<List<WebNodeStatusItemData>> loadNodeStatuses() async {
    final response = await _api.getNodeStatuses();
    final data = Map<String, dynamic>.from(
      response['data'] as Map? ?? const {},
    );
    return (data['items'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => WebNodeStatusItemData.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .where((item) => item.nodeId > 0)
        .toList();
  }

  Future<List<WebTicketListItemData>> loadTickets() async {
    final response = await _api.getTickets();
    final data = Map<String, dynamic>.from(
      response['data'] as Map? ?? const {},
    );
    return (data['items'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => WebTicketListItemData.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .where((item) => item.ticketId > 0)
        .toList()
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
  }

  Future<WebTicketDetailData> loadTicketDetail(int ticketId) async {
    final response = await _api.getTicketDetail(ticketId);
    final data = Map<String, dynamic>.from(
      response['data'] as Map? ?? const {},
    );
    return WebTicketDetailData.fromJson(
      Map<String, dynamic>.from(data['ticket'] as Map? ?? const {}),
    );
  }

  Future<void> createTicket({
    required String subject,
    required int priorityLevel,
    required String message,
  }) async {
    await _api.createTicket(
      subject: subject,
      priorityLevel: priorityLevel,
      message: message,
    );
  }

  Future<void> replyTicket({
    required int ticketId,
    required String message,
  }) async {
    await _api.replyTicket(
      ticketId: ticketId,
      message: message,
    );
  }

  Future<void> closeTicket(int ticketId) async {
    await _api.closeTicket(ticketId);
  }

  Future<List<WebTrafficLogItemData>> loadTrafficLogs() async {
    final response = await _api.getTrafficLogs();
    final data = Map<String, dynamic>.from(
      response['data'] as Map? ?? const {},
    );
    return (data['items'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => WebTrafficLogItemData.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .toList()
      ..sort((left, right) => right.recordedAt.compareTo(left.recordedAt));
  }

  Future<List<WebPlanViewData>> loadPlans() async {
    final response = await _api.getPlans();
    final data = Map<String, dynamic>.from(
      response['data'] as Map? ?? const {},
    );
    return (data['items'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => WebPlanViewData.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .where((plan) => plan.canBuy)
        .toList();
  }

  Future<List<WebOrderListItemData>> loadOrders() async {
    final response = await _api.getOrders();
    final data = Map<String, dynamic>.from(
      response['data'] as Map? ?? const {},
    );
    final items = (data['items'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => WebOrderListItemData.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .where((item) => item.orderRef.isNotEmpty)
        .toList()
      ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
    return items;
  }

  Future<void> validateCoupon(
    int planId,
    String periodKey,
    String couponCode,
  ) async {
    await _api.validateCoupon(planId, periodKey, couponCode);
  }

  Future<String> createOrder(
    int planId,
    String periodKey,
    String? couponCode,
  ) async {
    try {
      final response = await _api.createOrder(
        planId,
        periodKey,
        couponCode: couponCode,
      );
      final data = Map<String, dynamic>.from(
        response['data'] as Map? ?? const {},
      );
      final orderRef = data['order_ref']?.toString() ?? '';
      if (orderRef.isEmpty) {
        throw StateError('order reference missing');
      }
      return orderRef;
    } on AppApiException catch (error) {
      if (error.code == 'commerce.pending_order_exists') {
        throw const PendingOrderExistsException();
      }
      rethrow;
    }
  }

  Future<String?> recoverMatchingPendingOrderRef({
    required WebPlanViewData plan,
    required WebPlanPeriod period,
    String? couponCode,
    DateTime Function()? now,
  }) async {
    if (_trimmedOrNull(couponCode) != null) {
      return null;
    }

    final response = await _api.getOrders();
    final data = Map<String, dynamic>.from(
      response['data'] as Map? ?? const {},
    );
    final items = (data['items'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where(
          (item) =>
              _toInt(item['state_code']) == 0 &&
              (item['order_ref']?.toString().trim().isNotEmpty ?? false),
        )
        .toList()
      ..sort(
        (left, right) =>
            _toInt(right['created_at']).compareTo(_toInt(left['created_at'])),
      );

    if (items.isEmpty) {
      return null;
    }

    final latestPending = items.first;
    final orderRef = latestPending['order_ref']?.toString().trim() ?? '';
    if (orderRef.isEmpty) {
      return null;
    }

    final createdAt = _toInt(latestPending['created_at']);
    if (createdAt <= 0) {
      return null;
    }

    final nowUtc = (now ?? DateTime.now).call().toUtc();
    final createdAtUtc = DateTime.fromMillisecondsSinceEpoch(
      createdAt * 1000,
      isUtc: true,
    );
    if (createdAtUtc.isBefore(nowUtc.subtract(const Duration(minutes: 30)))) {
      return null;
    }

    final detail = await loadOrderDetail(orderRef, plan);
    if (detail.stateCode != 0) {
      return null;
    }
    if (detail.plan?.id != plan.id || detail.periodKey != period.key) {
      return null;
    }

    return orderRef;
  }

  Future<WebOrderDetailData> loadOrderDetail(
    String orderRef,
    WebPlanViewData? fallbackPlan,
  ) async {
    final response = await _api.getOrderDetail(orderRef);
    final data = Map<String, dynamic>.from(
      response['data'] as Map? ?? const {},
    );
    final order = Map<String, dynamic>.from(data['order'] as Map? ?? const {});
    return WebOrderDetailData.fromJson(order, fallbackPlan: fallbackPlan);
  }

  Future<List<WebPaymentMethodData>> loadPaymentMethods() async {
    final response = await _api.getPaymentMethods();
    final data = Map<String, dynamic>.from(
      response['data'] as Map? ?? const {},
    );
    return (data['items'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => WebPaymentMethodData.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .where((method) => method.id > 0 && method.label.isNotEmpty)
        .toList();
  }

  Future<WebCheckoutActionData> checkoutOrder(
    String orderRef,
    int methodId,
  ) async {
    final response = await _api.checkoutOrder(orderRef, methodId);
    final data = Map<String, dynamic>.from(
      response['data'] as Map? ?? const {},
    );
    final action = Map<String, dynamic>.from(
      data['action'] as Map? ?? const {},
    );
    return WebCheckoutActionData.fromJson(action);
  }

  Future<void> cancelOrder(String orderRef) async {
    await _api.cancelOrder(orderRef);
  }

  Future<int> loadOrderStatus(String orderRef) async {
    final response = await _api.getOrderStatus(orderRef);
    final data = Map<String, dynamic>.from(
      response['data'] as Map? ?? const {},
    );
    return _toInt(data['state_code']);
  }
}

int _toInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

String? _trimmedOrNull(String? raw) {
  final value = raw?.trim();
  if (value == null || value.isEmpty) return null;
  return value;
}
