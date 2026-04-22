import 'remote_config_service.dart';
import 'user_data_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiConfig {
  static const _sessionTokenKey = 'app_session_token';
  static const _legacyTokenKey = 'api_token';
  static const _legacyAuthDataKey = 'api_auth_data';

  static String? _sessionTokenCache;

  Future<String> getBaseUrl() async {
    final domain = await RemoteConfigService().getActiveDomain();
    final cleanDomain = domain.endsWith('/')
        ? domain.substring(0, domain.length - 1) 
        : domain;
    return '$cleanDomain/api/app/v1';
  }

  Future<String?> getSessionToken() async {
    final cached = _sessionTokenCache;
    if (cached != null) return cached;
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_sessionTokenKey);
    _sessionTokenCache = value;
    return value;
  }

  Future<void> setSessionToken(String? token) async {
    _sessionTokenCache = token;
    final prefs = await SharedPreferences.getInstance();
    if (token == null || token.isEmpty) {
      await prefs.remove(_sessionTokenKey);
      return;
    }
    await prefs.setString(_sessionTokenKey, token);
  }

  Future<void> clearAuth() async {
    _sessionTokenCache = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionTokenKey);
    await prefs.remove(_legacyTokenKey);
    await prefs.remove(_legacyAuthDataKey);
    // 清除用户数据缓存
    UserDataService().clearCache();
  }

  Future<void> refreshSessionCache() async {
    final prefs = await SharedPreferences.getInstance();
    _sessionTokenCache = prefs.getString(_sessionTokenKey);
  }

  Future<void> dropLegacyAuth() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_legacyTokenKey);
    await prefs.remove(_legacyAuthDataKey);
  }

  Future<bool> hasLegacyAuth() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_legacyTokenKey) ||
        prefs.containsKey(_legacyAuthDataKey);
  }
}
