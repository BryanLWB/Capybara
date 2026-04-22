import '../models/invite_data.dart';
import 'api_config.dart';
import 'app_api.dart';

class PanelApiException implements Exception {
  PanelApiException({
    required this.statusCode,
    required this.message,
    this.code,
    this.body,
  });

  final int statusCode;
  final String message;
  final String? code;
  final String? body;

  @override
  String toString() => message;
}

class PanelApi {
  PanelApi({ApiConfig? config, AppApi? appApi})
      : _config = config ?? ApiConfig(),
        _appApi = appApi ?? AppApi(config: config ?? ApiConfig());

  final ApiConfig _config;
  final AppApi _appApi;

  Future<Map<String, dynamic>> getPlans() async {
    try {
      final response = await _appApi.getPlans();
      final data = Map<String, dynamic>.from(response['data'] as Map? ?? const {});
      final items = (data['items'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => _mapPlan(Map<String, dynamic>.from(item)))
          .toList();
      return <String, dynamic>{'data': items};
    } on AppApiException catch (error) {
      throw _toLegacy(error);
    }
  }

  Future<Map<String, dynamic>> getGuestPlans() async {
    return getPlans();
  }

  Future<Map<String, dynamic>> getGuestConfig() async {
    try {
      final response = await _appApi.getGuestConfig();
      final data = Map<String, dynamic>.from(response['data'] as Map? ?? const {});
      final config = Map<String, dynamic>.from(data['config'] as Map? ?? const {});
      return <String, dynamic>{
        'data': _mapGuestConfig(config),
      };
    } on AppApiException catch (error) {
      throw _toLegacy(error);
    }
  }

  Future<Map<String, dynamic>> getUserCommonConfig() async {
    try {
      final response = await _appApi.getUserConfig();
      final data = Map<String, dynamic>.from(response['data'] as Map? ?? const {});
      final config = Map<String, dynamic>.from(data['config'] as Map? ?? const {});
      return <String, dynamic>{
        'data': _mapUserConfig(config),
      };
    } on AppApiException catch (error) {
      throw _toLegacy(error);
    }
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final response = await _appApi.login(email, password);
      final data = response['data'] as Map? ?? const {};
      final session = Map<String, dynamic>.from(data['session'] as Map? ?? const {});
      return <String, dynamic>{
        'data': <String, dynamic>{
          'session_token': session['token'],
          'expires_at': session['expires_at'],
          'account': data['account'],
        },
      };
    } on AppApiException catch (error) {
      throw _toLegacy(error);
    }
  }

  Future<Map<String, dynamic>> register(
    String email,
    String password, {
    String? inviteCode,
    String? emailCode,
    String? recaptchaData,
  }) async {
    try {
      final response = await _appApi.register(
        email,
        password,
        inviteCode: inviteCode,
        emailCode: emailCode,
        recaptchaData: recaptchaData,
      );
      final data = response['data'] as Map? ?? const {};
      final session = Map<String, dynamic>.from(data['session'] as Map? ?? const {});
      return <String, dynamic>{
        'data': <String, dynamic>{
          'session_token': session['token'],
          'expires_at': session['expires_at'],
          'account': data['account'],
        },
      };
    } on AppApiException catch (error) {
      throw _toLegacy(error);
    }
  }

  Future<Map<String, dynamic>> authCheck() async {
    final response = await getUserInfo();
    return <String, dynamic>{
      'data': <String, dynamic>{
        'is_login': (response['data'] as Map?)?.isNotEmpty == true,
      },
    };
  }

  Future<Map<String, dynamic>> forgetPassword(
    String email,
    String emailCode,
    String password,
  ) async {
    try {
      await _appApi.resetPassword(email, emailCode, password);
      return <String, dynamic>{'data': true};
    } on AppApiException catch (error) {
      throw _toLegacy(error);
    }
  }

  Future<Map<String, dynamic>> sendEmailVerify(
    String email, {
    String? recaptchaData,
  }) async {
    try {
      await _appApi.sendEmailCode(email, recaptchaData: recaptchaData);
      return <String, dynamic>{'data': true};
    } on AppApiException catch (error) {
      throw _toLegacy(error);
    }
  }

  Future<Map<String, dynamic>> getTempToken() async {
    final session = await _config.getSessionToken();
    return <String, dynamic>{'data': <String, dynamic>{'session_token': session}};
  }

  Future<Map<String, dynamic>> getAppConfig() async {
    try {
      final response = await _appApi.getClientConfig();
      final data = Map<String, dynamic>.from(response['data'] as Map? ?? const {});
      return <String, dynamic>{
        'data': data['config'] ?? const <String, dynamic>{},
      };
    } on AppApiException catch (error) {
      throw _toLegacy(error);
    }
  }

  Future<Map<String, dynamic>> getAppVersion() async {
    try {
      final response = await _appApi.getClientVersion();
      final data = Map<String, dynamic>.from(response['data'] as Map? ?? const {});
      return <String, dynamic>{
        'data': data['version'] ?? const <String, dynamic>{},
      };
    } on AppApiException catch (error) {
      throw _toLegacy(error);
    }
  }

  Future<Map<String, dynamic>> getClientSubscribe({String? flag}) async {
    try {
      final content = await _appApi.getSubscriptionContent(flag: flag);
      return <String, dynamic>{'data': content};
    } on AppApiException catch (error) {
      throw _toLegacy(error);
    }
  }

  Future<Map<String, dynamic>> getUserInfo() async {
    try {
      final response = await _appApi.getProfile();
      final data = Map<String, dynamic>.from(response['data'] as Map? ?? const {});
      final account =
          Map<String, dynamic>.from(data['account'] as Map? ?? const {});
      return <String, dynamic>{'data': _mapAccount(account)};
    } on AppApiException catch (error) {
      throw _toLegacy(error);
    }
  }

  Future<Map<String, dynamic>> getUserSubscribe() async {
    try {
      final response = await _appApi.getSubscriptionSummary();
      final data = Map<String, dynamic>.from(response['data'] as Map? ?? const {});
      final subscription = Map<String, dynamic>.from(
        data['subscription'] as Map? ?? const {},
      );
      return <String, dynamic>{'data': _mapSubscription(subscription)};
    } on AppApiException catch (error) {
      throw _toLegacy(error);
    }
  }

  Future<Map<String, dynamic>> fetchNotice() async {
    try {
      final response = await _appApi.getNotices();
      final data = Map<String, dynamic>.from(response['data'] as Map? ?? const {});
      final items = (data['items'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => _mapNotice(Map<String, dynamic>.from(item)))
          .toList();
      return <String, dynamic>{'data': items};
    } on AppApiException catch (error) {
      throw _toLegacy(error);
    }
  }

  Future<Map<String, dynamic>> logout() async {
    try {
      await _appApi.logout();
      return <String, dynamic>{'data': true};
    } on AppApiException catch (error) {
      throw _toLegacy(error);
    }
  }

  Future<Map<String, dynamic>> getPlanDetail(String id) async {
    final plans = await getPlans();
    final list = (plans['data'] as List? ?? const [])
        .whereType<Map>()
        .cast<Map<String, dynamic>>();
    final target = list.firstWhere(
      (item) => item['id'].toString() == id,
      orElse: () => <String, dynamic>{},
    );
    return <String, dynamic>{'data': target};
  }

  Future<Map<String, dynamic>> saveOrder(
    int planId,
    String period, {
    String? couponCode,
  }) async {
    try {
      final response = await _appApi.createOrder(
        planId,
        period,
        couponCode: couponCode,
      );
      final data = Map<String, dynamic>.from(response['data'] as Map? ?? const {});
      return <String, dynamic>{
        'data': data['order_ref'],
      };
    } on AppApiException catch (error) {
      throw _toLegacy(error);
    }
  }

  Future<Map<String, dynamic>> checkoutOrder(
    String tradeNo,
    int methodId,
  ) async {
    try {
      final response = await _appApi.checkoutOrder(tradeNo, methodId);
      final data = Map<String, dynamic>.from(response['data'] as Map? ?? const {});
      final action = Map<String, dynamic>.from(
        data['action'] as Map? ?? const {},
      );
      return <String, dynamic>{
        'type': action['code'],
        'data': action['payload'],
      };
    } on AppApiException catch (error) {
      throw _toLegacy(error);
    }
  }

  Future<Map<String, dynamic>> checkOrder(String tradeNo) async {
    try {
      final response = await _appApi.getOrderStatus(tradeNo);
      final data = Map<String, dynamic>.from(response['data'] as Map? ?? const {});
      return <String, dynamic>{'data': data['state_code'] ?? 0};
    } on AppApiException catch (error) {
      throw _toLegacy(error);
    }
  }

  Future<Map<String, dynamic>> getPaymentMethods() async {
    try {
      final response = await _appApi.getPaymentMethods();
      final data = Map<String, dynamic>.from(response['data'] as Map? ?? const {});
      final items = (data['items'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => _mapPaymentMethod(Map<String, dynamic>.from(item)))
          .toList();
      return <String, dynamic>{'data': items};
    } on AppApiException catch (error) {
      throw _toLegacy(error);
    }
  }

  Future<Map<String, dynamic>> cancelOrder(String tradeNo) async {
    try {
      await _appApi.cancelOrder(tradeNo);
      return <String, dynamic>{'data': true};
    } on AppApiException catch (error) {
      throw _toLegacy(error);
    }
  }

  Future<Map<String, dynamic>> fetchOrders() async {
    try {
      final response = await _appApi.getOrders();
      final data = Map<String, dynamic>.from(response['data'] as Map? ?? const {});
      final items = (data['items'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => _mapOrder(Map<String, dynamic>.from(item)))
          .toList();
      return <String, dynamic>{'data': items};
    } on AppApiException catch (error) {
      throw _toLegacy(error);
    }
  }

  Future<InviteFetchData> fetchInviteData() async {
    try {
      final response = await _appApi.getInviteOverview();
      final data = Map<String, dynamic>.from(response['data'] as Map? ?? const {});
      final metrics = Map<String, dynamic>.from(data['metrics'] as Map? ?? const {});
      final codes = (data['codes'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => _mapInviteCode(Map<String, dynamic>.from(item)))
          .toList();
      return InviteFetchData.fromJson(<String, dynamic>{
        'codes': codes,
        'stat': <dynamic>[
          metrics['registered_users'] ?? 0,
          metrics['settled_amount'] ?? 0,
          metrics['pending_amount'] ?? 0,
          metrics['rate_percent'] ?? 0,
          metrics['withdrawable_amount'] ?? 0,
        ],
      });
    } on AppApiException catch (error) {
      throw _toLegacy(error);
    }
  }

  Future<void> generateInviteCode() async {
    try {
      await _appApi.createInviteCode();
    } on AppApiException catch (error) {
      throw _toLegacy(error);
    }
  }

  Future<List<InviteDetail>> fetchInviteDetails() async {
    try {
      final response = await _appApi.getInviteRecords();
      final data = Map<String, dynamic>.from(response['data'] as Map? ?? const {});
      final items = (data['items'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => InviteDetail.fromJson(_mapInviteRecord(Map<String, dynamic>.from(item))))
          .toList();
      return items;
    } on AppApiException catch (error) {
      throw _toLegacy(error);
    }
  }

  Future<bool> redeemGiftCard(String code) async {
    try {
      final response = await _appApi.redeemGiftCode(code);
      final data = Map<String, dynamic>.from(response['data'] as Map? ?? const {});
      final result = data['result'];
      return result is Map ? result['ok'] == true : false;
    } on AppApiException catch (error) {
      throw _toLegacy(error);
    }
  }

  PanelApiException _toLegacy(AppApiException error) {
    return PanelApiException(
      statusCode: error.statusCode,
      message: error.message,
      code: error.code,
      body: error.body,
    );
  }

  Map<String, dynamic> _mapAccount(Map<String, dynamic> account) {
    return <String, dynamic>{
      'email': account['email'] ?? '',
      'transfer_enable': account['transfer_bytes'] ?? 0,
      'expired_at': account['expiry_at'] ?? 0,
      'balance': account['balance_amount'] ?? 0,
      'plan_id': account['plan_id'] ?? 0,
      'avatar_url': account['avatar_url'],
      'uuid': account['user_ref'],
    };
  }

  Map<String, dynamic> _mapSubscription(Map<String, dynamic> subscription) {
    return <String, dynamic>{
      'u': subscription['upload_bytes'] ?? 0,
      'd': subscription['download_bytes'] ?? 0,
      'transfer_enable': subscription['total_bytes'] ?? 0,
      'expired_at': subscription['expiry_at'] ?? 0,
      'reset_day': subscription['reset_days'] ?? 0,
      'subscribe_url': subscription['download_endpoint'],
    };
  }

  Map<String, dynamic> _mapPlan(Map<String, dynamic> plan) {
    return <String, dynamic>{
      'id': plan['plan_id'] ?? 0,
      'name': plan['title'] ?? 'Plan',
      'content': plan['summary'],
      'transfer_enable': _toNum(plan['transfer_bytes']).toInt() ~/ 1024 ~/ 1024 ~/ 1024,
      'month_price': plan['monthly_amount'],
      'quarter_price': plan['quarterly_amount'],
      'half_year_price': plan['half_year_amount'],
      'year_price': plan['yearly_amount'],
      'two_year_price': plan['biennial_amount'],
      'three_year_price': plan['triennial_amount'],
      'onetime_price': plan['once_amount'],
      'reset_price': plan['reset_amount'],
      'reset_traffic_method': plan['reset_method'],
    };
  }

  Map<String, dynamic> _mapNotice(Map<String, dynamic> notice) {
    return <String, dynamic>{
      'id': notice['notice_id'] ?? 0,
      'title': notice['headline'] ?? '',
      'content': notice['body'] ?? '',
      'created_at': notice['created_at'] ?? 0,
      'updated_at': notice['updated_at'] ?? 0,
    };
  }

  Map<String, dynamic> _mapPaymentMethod(Map<String, dynamic> method) {
    return <String, dynamic>{
      'id': method['method_id'] ?? 0,
      'name': method['label'] ?? '',
      'payment': method['provider'] ?? '',
      'icon': method['icon_url'],
      'handling_fee_fixed': method['fee_fixed'] ?? 0,
      'handling_fee_percent': method['fee_rate'] ?? 0,
    };
  }

  Map<String, dynamic> _mapOrder(Map<String, dynamic> order) {
    final plan = order['plan'];
    return <String, dynamic>{
      'trade_no': order['order_ref'] ?? '',
      'status': order['state_code'] ?? 0,
      'total_amount': order['amount_total'] ?? 0,
      'created_at': order['created_at'] ?? 0,
      'updated_at': order['updated_at'] ?? 0,
      if (plan is Map) 'plan': _mapPlan(Map<String, dynamic>.from(plan)),
    };
  }

  Map<String, dynamic> _mapInviteCode(Map<String, dynamic> code) {
    return <String, dynamic>{
      'id': code['code_id'] ?? 0,
      'user_id': code['owner_ref'] ?? 0,
      'code': code['invite_code'] ?? '',
      'status': code['state_code'] ?? 0,
      'pv': code['visit_count'] ?? 0,
      'created_at': code['created_at'] ?? 0,
      'updated_at': code['updated_at'] ?? 0,
    };
  }

  Map<String, dynamic> _mapInviteRecord(Map<String, dynamic> record) {
    return <String, dynamic>{
      'id': record['record_id'] ?? 0,
      'amount': record['amount'] ?? 0,
      'trade_no': record['trade_ref'],
      'order_amount': record['order_amount'] ?? 0,
      'created_at': record['created_at'] ?? 0,
      'status_text': record['status_text'],
    };
  }

  Map<String, dynamic> _mapGuestConfig(Map<String, dynamic> config) {
    return <String, dynamic>{
      'tos_url': config['tos_link'],
      'is_email_verify': config['email_verification_required'] ?? 0,
      'is_invite_force': config['invite_code_required'] ?? 0,
      'email_whitelist_suffix': config['email_whitelist_suffix'] ?? 0,
      'is_captcha': config['captcha_enabled'] ?? 0,
      'captcha_type': config['captcha_kind'],
      'recaptcha_site_key': config['captcha_site_key'],
      'recaptcha_v3_site_key': config['captcha_site_key_v3'],
      'recaptcha_v3_score_threshold': config['captcha_score_threshold'],
      'turnstile_site_key': config['turnstile_site_key'],
      'app_description': config['service_summary'],
      'app_url': config['website_link'],
      'logo': config['logo_url'],
      'is_recaptcha': config['captcha_enabled'] ?? 0,
    };
  }

  Map<String, dynamic> _mapUserConfig(Map<String, dynamic> config) {
    return <String, dynamic>{
      'is_telegram': config['telegram_enabled'] ?? 0,
      'telegram_discuss_link': config['telegram_discuss_link'],
      'stripe_pk': config['stripe_publishable_key'],
      'withdraw_methods': config['payout_methods'] ?? const [],
      'withdraw_close': config['payout_closed'] ?? 0,
      'currency': config['currency_code'] ?? 'CNY',
      'currency_symbol': config['currency_symbol'] ?? '¥',
      'commission_distribution_enable': config['commission_tiers_enabled'] ?? 0,
      'commission_distribution_l1': config['commission_l1'],
      'commission_distribution_l2': config['commission_l2'],
      'commission_distribution_l3': config['commission_l3'],
    };
  }

  num _toNum(Object? value) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value) ?? 0;
    return 0;
  }
}
