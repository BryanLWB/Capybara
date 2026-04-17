class UpstreamAuth {
  UpstreamAuth({
    required this.token,
    required this.authorization,
  });

  final String token;
  final String authorization;
}

class UpstreamException implements Exception {
  UpstreamException({
    required this.statusCode,
    required this.message,
    this.body,
  });

  final int statusCode;
  final String message;
  final String? body;

  @override
  String toString() => message;
}

abstract class UpstreamApi {
  Future<UpstreamAuth> login({
    required String email,
    required String password,
  });

  Future<UpstreamAuth> register({
    required String email,
    required String password,
    String? inviteCode,
    String? emailCode,
    String? recaptchaData,
  });

  Future<void> sendEmailCode({
    required String email,
    String? recaptchaData,
  });

  Future<void> resetPassword({
    required String email,
    required String emailCode,
    required String password,
  });

  Future<Map<String, dynamic>> fetchGuestConfig();

  Future<List<Map<String, dynamic>>> fetchGuestPlans();

  Future<Map<String, dynamic>> fetchUserConfig(UpstreamAuth auth);

  Future<void> updateUserNotifications(
    UpstreamAuth auth, {
    required bool remindExpire,
    required bool remindTraffic,
  });

  Future<void> changePassword(
    UpstreamAuth auth, {
    required String oldPassword,
    required String newPassword,
  });

  Future<List<Map<String, dynamic>>> fetchPlans(UpstreamAuth auth);

  Future<Map<String, dynamic>> fetchUserProfile(UpstreamAuth auth);

  Future<Map<String, dynamic>> fetchSubscriptionSummary(UpstreamAuth auth);

  Future<String> fetchSubscriptionContent(UpstreamAuth auth, {String? flag});

  Future<void> resetSubscriptionSecurity(UpstreamAuth auth);

  Future<List<Map<String, dynamic>>> fetchNotices(UpstreamAuth auth);

  Future<List<Map<String, dynamic>>> fetchServers(UpstreamAuth auth);

  Future<List<Map<String, dynamic>>> fetchTrafficLogs(UpstreamAuth auth);

  Future<List<Map<String, dynamic>>> fetchPaymentMethods(UpstreamAuth auth);

  Future<String> createOrder(
    UpstreamAuth auth, {
    required int planId,
    required String period,
    String? couponCode,
  });

  Future<Map<String, dynamic>> validateCoupon(
    UpstreamAuth auth, {
    required int planId,
    required String period,
    required String couponCode,
  });

  Future<Map<String, dynamic>> fetchOrderDetail(
    UpstreamAuth auth, {
    required String tradeNo,
  });

  Future<Map<String, dynamic>> checkoutOrder(
    UpstreamAuth auth, {
    required String tradeNo,
    required int methodId,
  });

  Future<int> checkOrder(UpstreamAuth auth, {required String tradeNo});

  Future<void> cancelOrder(UpstreamAuth auth, {required String tradeNo});

  Future<List<Map<String, dynamic>>> fetchOrders(UpstreamAuth auth);

  Future<Map<String, dynamic>> fetchInviteOverview(UpstreamAuth auth);

  Future<List<Map<String, dynamic>>> fetchInviteRecords(UpstreamAuth auth);

  Future<void> generateInviteCode(UpstreamAuth auth);

  Future<void> transferCommissionToBalance(
    UpstreamAuth auth, {
    required int amountCents,
  });

  Future<void> requestCommissionWithdrawal(
    UpstreamAuth auth, {
    required String method,
    required String account,
  });

  Future<List<Map<String, dynamic>>> fetchTickets(UpstreamAuth auth);

  Future<Map<String, dynamic>> fetchTicketDetail(
    UpstreamAuth auth, {
    required int ticketId,
  });

  Future<void> createTicket(
    UpstreamAuth auth, {
    required String subject,
    required int level,
    required String message,
  });

  Future<void> replyTicket(
    UpstreamAuth auth, {
    required int ticketId,
    required String message,
  });

  Future<void> closeTicket(
    UpstreamAuth auth, {
    required int ticketId,
  });

  Future<Map<String, dynamic>> redeemGiftCard(
    UpstreamAuth auth, {
    required String code,
  });

  Future<Map<String, dynamic>> fetchClientConfig(UpstreamAuth auth);

  Future<Map<String, dynamic>> fetchClientVersion(UpstreamAuth auth);

  Future<Map<String, dynamic>> fetchHelpArticles(
    UpstreamAuth auth, {
    required String language,
  });

  Future<Map<String, dynamic>> fetchHelpArticleDetail(
    UpstreamAuth auth, {
    required int articleId,
    required String language,
  });
}
