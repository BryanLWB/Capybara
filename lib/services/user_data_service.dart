import '../models/user_info.dart';
import 'panel_api.dart';

/// 用户数据缓存服务
/// 减少重复 API 请求，提升页面切换速度
class UserDataService {
  static final UserDataService _instance = UserDataService._internal();
  factory UserDataService() => _instance;
  UserDataService._internal();

  final PanelApi _api = PanelApi();

  // 缓存数据
  UserInfo? _userInfo;
  Map<String, dynamic>? _commConfig;
  Map<String, dynamic>? _subscribeInfo;
  List<Map<String, dynamic>>? _plans;
  List<Map<String, dynamic>>? _notices;

  // 缓存时间戳
  DateTime? _userInfoFetchTime;
  DateTime? _commConfigFetchTime;
  DateTime? _subscribeFetchTime;
  DateTime? _plansFetchTime;
  DateTime? _noticesFetchTime;

  // 缓存有效期 (秒)
  static const int _userCacheSeconds = 60;      // 用户信息 60秒
  static const int _commConfigCacheSeconds = 3600; // 通用配置 1小时 (很少变)
  static const int _subscribeCacheSeconds = 30;  // 订阅信息 30秒
  static const int _plansCacheSeconds = 300;     // 套餐列表 5分钟
  static const int _noticesCacheSeconds = 120;   // 公告 2分钟

  /// 检查缓存是否有效
  bool _isCacheValid(DateTime? fetchTime, int validSeconds) {
    if (fetchTime == null) return false;
    return DateTime.now().difference(fetchTime).inSeconds < validSeconds;
  }

  /// 获取用户信息 (带缓存)
  Future<UserInfo> getUserInfo({bool forceRefresh = false}) async {
    if (!forceRefresh && _userInfo != null && 
        _isCacheValid(_userInfoFetchTime, _userCacheSeconds)) {
      return _userInfo!;
    }

    final response = await _api.getUserInfo();
    _userInfo = UserInfo.fromJson(response['data'] ?? {});
    _userInfoFetchTime = DateTime.now();
    return _userInfo!;
  }

  /// 获取通用配置 (带缓存，很少变)
  Future<Map<String, dynamic>> getCommConfig({bool forceRefresh = false}) async {
    if (!forceRefresh && _commConfig != null && 
        _isCacheValid(_commConfigFetchTime, _commConfigCacheSeconds)) {
      return _commConfig!;
    }

    final response = await _api.getUserCommonConfig();
    _commConfig = response['data'] ?? {};
    _commConfigFetchTime = DateTime.now();
    return _commConfig!;
  }

  /// 获取订阅信息 (带缓存)
  Future<Map<String, dynamic>> getSubscribeInfo({bool forceRefresh = false}) async {
    if (!forceRefresh && _subscribeInfo != null && 
        _isCacheValid(_subscribeFetchTime, _subscribeCacheSeconds)) {
      return _subscribeInfo!;
    }

    final response = await _api.getUserSubscribe();
    _subscribeInfo = response['data'] ?? {};
    _subscribeFetchTime = DateTime.now();
    return _subscribeInfo!;
  }

  /// 获取套餐列表 (带缓存)
  Future<List<Map<String, dynamic>>> getPlans({bool forceRefresh = false}) async {
    if (!forceRefresh && _plans != null && 
        _isCacheValid(_plansFetchTime, _plansCacheSeconds)) {
      return _plans!;
    }

    final response = await _api.getPlans();
    final data = response['data'];
    if (data is List) {
      _plans = data
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } else {
      _plans = [];
    }
    _plansFetchTime = DateTime.now();
    return _plans!;
  }

  /// 获取公告列表 (带缓存)
  Future<List<Map<String, dynamic>>> getNotices({bool forceRefresh = false}) async {
    if (!forceRefresh && _notices != null && 
        _isCacheValid(_noticesFetchTime, _noticesCacheSeconds)) {
      return _notices!;
    }

    final response = await _api.fetchNotice();
    final data = response['data'];
    if (data is List) {
      _notices = data
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } else {
      _notices = [];
    }
    _noticesFetchTime = DateTime.now();
    return _notices!;
  }

  /// 并行获取账户页所需的所有数据 (智能缓存)
  Future<Map<String, dynamic>> getAccountPageData({bool forceRefresh = false}) async {
    // comm_config 有长缓存，单独处理
    final commConfigFuture = getCommConfig(forceRefresh: forceRefresh);
    
    // 其他数据并行获取
    final results = await Future.wait([
      getUserInfo(forceRefresh: forceRefresh),
      getSubscribeInfo(forceRefresh: forceRefresh),
      commConfigFuture,
    ]);

    return {
      'user': results[0] as UserInfo,
      'subscribe': results[1] as Map<String, dynamic>,
      'config': results[2] as Map<String, dynamic>,
    };
  }

  /// 清除所有缓存 (用于登出)
  void clearCache() {
    _userInfo = null;
    _commConfig = null;
    _subscribeInfo = null;
    _plans = null;
    _notices = null;
    
    _userInfoFetchTime = null;
    _commConfigFetchTime = null;
    _subscribeFetchTime = null;
    _plansFetchTime = null;
    _noticesFetchTime = null;
  }

  /// 刷新用户相关数据 (用于支付成功后)
  Future<void> refreshUserData() async {
    await Future.wait([
      getUserInfo(forceRefresh: true),
      getSubscribeInfo(forceRefresh: true),
    ]);
  }
}
